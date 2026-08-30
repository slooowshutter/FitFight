import CoreFoundation
import CryptoKit
import Foundation
import HealthKit

enum HealthKitStepArchiveError: Error {
    case archiveTooLarge
}

struct HealthKitPreparedArchive {
    let url: URL
    let byteSize: Int
    let sha256: String
    let candidateAnchor: Data
    let earliestSample: Date
}

enum HealthKitStepArchive {
    static let maximumBytes = 512 * 1_024 * 1_024
    private static let pageLimit = 500

    static func prepare(
        store: HKHealthStore,
        type: HKQuantityType,
        userId: UUID,
        uploadId: UUID,
        activeAnchorData: Data?,
        previousEarliestSample: Date?,
        fightWindows: [FitFightHealthKitContext.FightWindow]
    ) async throws -> HealthKitPreparedArchive? {
        let activeAnchor = try activeAnchorData.flatMap {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let isInitialArchive = activeAnchor == nil
        let directory = try HealthKitUploadState.directory(userId: userId)
        let archiveURL = directory.appendingPathComponent("\(uploadId.uuidString.lowercased()).ndjson")
        FileManager.default.createFile(
            atPath: archiveURL.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try HealthKitUploadState.protectAndExcludeFromBackup(archiveURL)

        let writer = try NDJSONWriter(url: archiveURL, maximumBytes: maximumBytes)
        var queryAnchor = activeAnchor
        var candidateAnchor = activeAnchor
        var earliestSample = previousEarliestSample
        var sawDeletion = false
        var earliestChangedSample: Date?
        let calendar = Calendar.current
        let now = Date()

        do {
            while true {
                let page = try await changes(store: store, type: type, anchor: queryAnchor)
                candidateAnchor = page.anchor ?? candidateAnchor
                for sample in page.samples {
                    earliestChangedSample = min(earliestChangedSample ?? sample.startDate, sample.startDate)
                    earliestSample = min(earliestSample ?? sample.startDate, sample.startDate)
                    try writer.append(sampleRecord(
                        sample,
                        operation: "add",
                        calendar: calendar
                    ))
                }
                for deletion in page.deletions {
                    sawDeletion = true
                    try writer.append(DeletionRecord(
                        type: "deletion",
                        operation: "delete",
                        sampleId: deletion.uuid,
                        occurredAt: iso8601(now)
                    ))
                }
                guard page.samples.count + page.deletions.count >= pageLimit,
                      let nextAnchor = page.anchor else { break }
                queryAnchor = nextAnchor
            }

            guard let earliestSample, let candidateAnchor else {
                try writer.cancel()
                return nil
            }

            let today = calendar.startOfDay(for: now)
            let statisticsStart: Date
            if isInitialArchive || sawDeletion {
                statisticsStart = calendar.startOfDay(for: earliestSample)
            } else if let earliestChangedSample {
                statisticsStart = calendar.startOfDay(for: earliestChangedSample)
            } else {
                statisticsStart = today
            }
            try await appendDays(
                writer: writer,
                store: store,
                type: type,
                start: statisticsStart,
                end: now,
                calendar: calendar
            )
            for window in fightWindows {
                let steps = try await aggregate(
                    store: store,
                    type: type,
                    start: window.startsAt,
                    end: window.cutoffAt
                )
                try writer.append(FightAggregateRecord(
                    type: "fight_aggregate",
                    fightId: window.fightId,
                    startsAt: iso8601(window.startsAt),
                    endsAt: iso8601(window.endsAt),
                    cutoffAt: iso8601(window.cutoffAt),
                    steps: Int(steps.rounded())
                ))
            }
            try writer.append(CheckpointRecord(
                type: "checkpoint",
                timeZone: calendar.timeZone.identifier,
                accessibleFrom: iso8601(max(earliestSample, store.earliestPermittedSampleDate())),
                completeThrough: iso8601(now)
            ))
            let result = try writer.finish()
            return HealthKitPreparedArchive(
                url: archiveURL,
                byteSize: result.byteSize,
                sha256: result.sha256,
                candidateAnchor: try NSKeyedArchiver.archivedData(
                    withRootObject: candidateAnchor,
                    requiringSecureCoding: true
                ),
                earliestSample: earliestSample
            )
        } catch {
            try? writer.cancel()
            throw error
        }
    }

    private struct ChangePage {
        let samples: [HKQuantitySample]
        let deletions: [HKDeletedObject]
        let anchor: HKQueryAnchor?
    }

    private static func changes(
        store: HKHealthStore,
        type: HKQuantityType,
        anchor: HKQueryAnchor?
    ) async throws -> ChangePage {
        try await withCheckedThrowingContinuation { continuation in
            store.execute(HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: pageLimit
            ) { _, samples, deletions, anchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ChangePage(
                        samples: (samples ?? []).compactMap { $0 as? HKQuantitySample },
                        deletions: deletions ?? [],
                        anchor: anchor
                    ))
                }
            })
        }
    }

    private static func appendDays(
        writer: NDJSONWriter,
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws {
        let merged = try await statisticsDays(
            store: store,
            type: type,
            start: start,
            end: end,
            calendar: calendar,
            separateBySource: false
        )
        let bySource = try await statisticsDays(
            store: store,
            type: type,
            start: start,
            end: end,
            calendar: calendar,
            separateBySource: true
        )
        let mergedByDay = Dictionary(uniqueKeysWithValues: merged.map {
            (dayString($0.start, calendar: calendar), $0)
        })
        let sourceByDay = Dictionary(uniqueKeysWithValues: bySource.map {
            (dayString($0.start, calendar: calendar), $0)
        })
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let day = dayString(cursor, calendar: calendar)
            let effectiveEnd = min(next, end)
            try writer.append(MergedDayRecord(
                type: "merged_day",
                day: day,
                startsAt: iso8601(cursor),
                endsAt: iso8601(effectiveEnd),
                timeZone: calendar.timeZone.identifier,
                steps: Int((mergedByDay[day]?.total ?? 0).rounded())
            ))
            for source in sourceByDay[day]?.sources ?? [] {
                try writer.append(SourceDayRecord(
                    type: "source_day",
                    day: day,
                    startsAt: iso8601(cursor),
                    endsAt: iso8601(effectiveEnd),
                    timeZone: calendar.timeZone.identifier,
                    sourceName: source.source.name,
                    sourceBundleIdentifier: source.source.bundleIdentifier,
                    steps: source.value
                ))
            }
            cursor = next
        }
    }

    private struct StatisticsDay {
        let start: Date
        let total: Double
        let sources: [(source: HKSource, value: Double)]
    }

    private static func statisticsDays(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date,
        calendar: Calendar,
        separateBySource: Bool
    ) async throws -> [StatisticsDay] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            var options: HKStatisticsOptions = [.cumulativeSum]
            if separateBySource { options.insert(.separateBySource) }
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var result: [StatisticsDay] = []
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    result.append(StatisticsDay(
                        start: statistics.startDate,
                        total: statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0,
                        sources: separateBySource ? (statistics.sources ?? []).compactMap { source in
                            statistics.sumQuantity(for: source).map {
                                (source, $0.doubleValue(for: .count()))
                            }
                        } : []
                    ))
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    private static func aggregate(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: [.strictStartDate, .strictEndDate]
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum]
        )
        return try await descriptor.result(for: store)?
            .sumQuantity()?.doubleValue(for: .count()) ?? 0
    }

    private static func sampleRecord(
        _ sample: HKQuantitySample,
        operation: String,
        calendar: Calendar
    ) -> SampleRecord {
        let revision = sample.sourceRevision
        let os = revision.operatingSystemVersion
        let device = sample.device
        return SampleRecord(
            type: "sample",
            operation: operation,
            sampleId: sample.uuid,
            value: sample.quantity.doubleValue(for: .count()),
            unit: "count",
            startsAt: iso8601(sample.startDate),
            endsAt: iso8601(sample.endDate),
            localDay: dayString(sample.startDate, calendar: calendar),
            timeZone: calendar.timeZone.identifier,
            sourceName: revision.source.name,
            sourceBundleIdentifier: revision.source.bundleIdentifier,
            sourceVersion: revision.version,
            sourceProductType: revision.productType,
            sourceOSVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            deviceName: device?.name,
            deviceManufacturer: device?.manufacturer,
            deviceModel: device?.model,
            deviceHardwareVersion: device?.hardwareVersion,
            deviceFirmwareVersion: device?.firmwareVersion,
            deviceSoftwareVersion: device?.softwareVersion,
            deviceLocalIdentifier: device?.localIdentifier,
            deviceUDIIdentifier: device?.udiDeviceIdentifier,
            metadata: (sample.metadata ?? [:]).mapValues(metadataValue),
            userEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue
        )
    }

    private static func metadataValue(_ raw: Any) -> MetadataValue {
        if let date = raw as? Date {
            return MetadataValue(kind: "date", value: iso8601(date), objcType: nil)
        }
        if let number = raw as? NSNumber {
            let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
            return MetadataValue(
                kind: isBoolean ? "boolean" : "number",
                value: isBoolean ? String(number.boolValue) : number.stringValue,
                objcType: String(cString: number.objCType)
            )
        }
        if let string = raw as? String {
            return MetadataValue(kind: "string", value: string, objcType: nil)
        }
        return MetadataValue(
            kind: String(reflecting: type(of: raw)),
            value: String(describing: raw),
            objcType: nil
        )
    }

    private static func dayString(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

final class NDJSONWriter {
    private let url: URL
    private let handle: FileHandle
    private let maximumBytes: Int
    private var hasher = SHA256()
    private(set) var byteSize = 0

    init(url: URL, maximumBytes: Int) throws {
        self.url = url
        self.maximumBytes = maximumBytes
        handle = try FileHandle(forWritingTo: url)
    }

    func append<Record: Encodable>(_ record: Record) throws {
        var data = try Self.encoder.encode(record)
        data.append(0x0a)
        guard byteSize + data.count <= maximumBytes else {
            throw HealthKitStepArchiveError.archiveTooLarge
        }
        try handle.write(contentsOf: data)
        hasher.update(data: data)
        byteSize += data.count
    }

    func finish() throws -> (byteSize: Int, sha256: String) {
        try handle.synchronize()
        try handle.close()
        return (byteSize, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    func cancel() throws {
        try? handle.close()
        try FileManager.default.removeItem(at: url)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

private struct SampleRecord: Encodable {
    let type: String
    let operation: String
    let sampleId: UUID
    let value: Double
    let unit: String
    let startsAt: String
    let endsAt: String
    let localDay: String
    let timeZone: String
    let sourceName: String
    let sourceBundleIdentifier: String
    let sourceVersion: String?
    let sourceProductType: String?
    let sourceOSVersion: String?
    let deviceName: String?
    let deviceManufacturer: String?
    let deviceModel: String?
    let deviceHardwareVersion: String?
    let deviceFirmwareVersion: String?
    let deviceSoftwareVersion: String?
    let deviceLocalIdentifier: String?
    let deviceUDIIdentifier: String?
    let metadata: [String: MetadataValue]
    let userEntered: Bool?

    enum CodingKeys: String, CodingKey {
        case type, operation, value, unit, metadata
        case sampleId = "sample_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case localDay = "local_day"
        case timeZone = "time_zone"
        case sourceName = "source_name"
        case sourceBundleIdentifier = "source_bundle_identifier"
        case sourceVersion = "source_version"
        case sourceProductType = "source_product_type"
        case sourceOSVersion = "source_os_version"
        case deviceName = "device_name"
        case deviceManufacturer = "device_manufacturer"
        case deviceModel = "device_model"
        case deviceHardwareVersion = "device_hardware_version"
        case deviceFirmwareVersion = "device_firmware_version"
        case deviceSoftwareVersion = "device_software_version"
        case deviceLocalIdentifier = "device_local_identifier"
        case deviceUDIIdentifier = "device_udi_identifier"
        case userEntered = "user_entered"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(operation, forKey: .operation)
        try container.encode(sampleId, forKey: .sampleId)
        try container.encode(value, forKey: .value)
        try container.encode(unit, forKey: .unit)
        try container.encode(startsAt, forKey: .startsAt)
        try container.encode(endsAt, forKey: .endsAt)
        try container.encode(localDay, forKey: .localDay)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(sourceName, forKey: .sourceName)
        try container.encode(sourceBundleIdentifier, forKey: .sourceBundleIdentifier)
        try container.encode(sourceVersion, forKey: .sourceVersion)
        try container.encode(sourceProductType, forKey: .sourceProductType)
        try container.encode(sourceOSVersion, forKey: .sourceOSVersion)
        try container.encode(deviceName, forKey: .deviceName)
        try container.encode(deviceManufacturer, forKey: .deviceManufacturer)
        try container.encode(deviceModel, forKey: .deviceModel)
        try container.encode(deviceHardwareVersion, forKey: .deviceHardwareVersion)
        try container.encode(deviceFirmwareVersion, forKey: .deviceFirmwareVersion)
        try container.encode(deviceSoftwareVersion, forKey: .deviceSoftwareVersion)
        try container.encode(deviceLocalIdentifier, forKey: .deviceLocalIdentifier)
        try container.encode(deviceUDIIdentifier, forKey: .deviceUDIIdentifier)
        try container.encode(metadata, forKey: .metadata)
        try container.encode(userEntered, forKey: .userEntered)
    }
}

private struct MetadataValue: Encodable {
    let kind: String
    let value: String
    let objcType: String?

    enum CodingKeys: String, CodingKey {
        case kind, value
        case objcType = "objc_type"
    }


    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(value, forKey: .value)
        try container.encode(objcType, forKey: .objcType)
    }
}

private struct DeletionRecord: Encodable {
    let type: String
    let operation: String
    let sampleId: UUID
    let occurredAt: String

    enum CodingKeys: String, CodingKey {
        case type, operation
        case sampleId = "sample_id"
        case occurredAt = "occurred_at"
    }
}

private struct MergedDayRecord: Encodable {
    let type: String
    let day: String
    let startsAt: String
    let endsAt: String
    let timeZone: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case type, day, steps
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeZone = "time_zone"
    }
}

private struct SourceDayRecord: Encodable {
    let type: String
    let day: String
    let startsAt: String
    let endsAt: String
    let timeZone: String
    let sourceName: String
    let sourceBundleIdentifier: String
    let steps: Double

    enum CodingKeys: String, CodingKey {
        case type, day, steps
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeZone = "time_zone"
        case sourceName = "source_name"
        case sourceBundleIdentifier = "source_bundle_identifier"
    }
}

private struct FightAggregateRecord: Encodable {
    let type: String
    let fightId: UUID
    let startsAt: String
    let endsAt: String
    let cutoffAt: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case type, steps
        case fightId = "fight_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case cutoffAt = "cutoff_at"
    }
}

private struct CheckpointRecord: Encodable {
    let type: String
    let timeZone: String
    let accessibleFrom: String?
    let completeThrough: String

    enum CodingKeys: String, CodingKey {
        case type
        case timeZone = "time_zone"
        case accessibleFrom = "accessible_from"
        case completeThrough = "complete_through"
    }


    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(timeZone, forKey: .timeZone)
        try container.encode(accessibleFrom, forKey: .accessibleFrom)
        try container.encode(completeThrough, forKey: .completeThrough)
    }
}

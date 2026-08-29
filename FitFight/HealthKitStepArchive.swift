import CoreFoundation
import Foundation
import HealthKit
import Supabase

/// Archives every accessible Steps representation while leaving Apple's merged
/// statistic as the only authoritative value in `step_days`.
enum HealthKitStepArchive {
    private static let healthKitPageLimit = 500
    private static let rawUploadLimit = 250
    private static let deletionUploadLimit = 500
    private static let dayUploadLimit = 31

    static func sync(
        store: HKHealthStore,
        type: HKQuantityType,
        client: SupabaseClient,
        userId: UUID
    ) async throws {
        let defaults = UserDefaults.standard
        let keys = SyncKeys(userId: userId)
        let savedAnchor = loadAnchor(defaults: defaults, key: keys.anchor)
        let isInitialArchive = savedAnchor == nil

        var queryAnchor = savedAnchor
        var finalAnchor = savedAnchor
        var earliestChangedSample: Date?
        var sawSamples = false
        var sawDeletions = false

        while true {
            let page = try await changes(store: store, type: type, anchor: queryAnchor)
            finalAnchor = page.anchor ?? finalAnchor

            if !page.samples.isEmpty {
                sawSamples = true
                let calendar = Calendar.current
                let uploads = page.samples.map { sampleUpload($0, calendar: calendar) }
                earliestChangedSample = minimum(
                    earliestChangedSample,
                    page.samples.map(\.startDate).min()
                )
                for chunk in chunks(of: uploads, limit: rawUploadLimit) {
                    try await ingest(
                        client: client,
                        payload: HealthKitStepPayload(samples: chunk)
                    )
                }
            }

            if !page.deletions.isEmpty {
                sawDeletions = true
                let uploads = page.deletions.map {
                    HealthKitStepDeletionUpload(sampleId: $0.uuid)
                }
                for chunk in chunks(of: uploads, limit: deletionUploadLimit) {
                    try await ingest(
                        client: client,
                        payload: HealthKitStepPayload(deletions: chunk)
                    )
                }
            }

            let objectCount = page.samples.count + page.deletions.count
            guard objectCount >= healthKitPageLimit, let nextAnchor = page.anchor else {
                break
            }
            queryAnchor = nextAnchor
        }

        if let earliestChangedSample {
            let previous = defaults.object(forKey: keys.earliestSample) as? Double
            let earliest = min(previous ?? earliestChangedSample.timeIntervalSince1970,
                               earliestChangedSample.timeIntervalSince1970)
            defaults.set(earliest, forKey: keys.earliestSample)
        }

        guard let earliestTimestamp = defaults.object(forKey: keys.earliestSample) as? Double else {
            // An empty initial query may mean no data or denied read access. Do
            // not advance the anchor and accidentally skip history granted later.
            if !isInitialArchive, let finalAnchor {
                try saveAnchor(finalAnchor, defaults: defaults, key: keys.anchor)
            }
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        let earliestArchived = Date(timeIntervalSince1970: earliestTimestamp)
        let statisticsStart: Date
        if isInitialArchive || sawDeletions {
            statisticsStart = calendar.startOfDay(for: earliestArchived)
        } else if let earliestChangedSample {
            statisticsStart = min(today, calendar.startOfDay(for: earliestChangedSample))
        } else {
            // Refresh the current Apple total on every app sync, even if the
            // anchored query reports no newly saved raw objects.
            statisticsStart = today
        }

        let bundles = try await dayBundles(
            store: store,
            type: type,
            start: statisticsStart,
            end: now,
            calendar: calendar
        )
        for chunk in chunks(of: bundles, limit: dayUploadLimit) {
            try await ingest(
                client: client,
                payload: HealthKitStepPayload(
                    mergedDays: chunk.map(\.merged),
                    sourceDays: chunk.flatMap(\.sources)
                )
            )
        }

        try await ingest(
            client: client,
            payload: HealthKitStepPayload(
                sync: HealthKitStepSyncUpload(
                    timeZone: calendar.timeZone.identifier,
                    accessibleFrom: iso8601(earliestArchived),
                    completeThrough: iso8601(now)
                )
            )
        )

        // Save only after every server write succeeds. A retry may resend rows,
        // but UUID/day upserts make that safe and prevent lost HealthKit changes.
        if let finalAnchor, sawSamples || sawDeletions || !isInitialArchive {
            try saveAnchor(finalAnchor, defaults: defaults, key: keys.anchor)
        }
    }

    // MARK: - HealthKit changes

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
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: nil,
                anchor: anchor,
                limit: healthKitPageLimit
            ) { _, samples, deletions, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(
                    returning: ChangePage(
                        samples: (samples ?? []).compactMap { $0 as? HKQuantitySample },
                        deletions: deletions ?? [],
                        anchor: newAnchor
                    )
                )
            }
            store.execute(query)
        }
    }

    // MARK: - Apple-merged and per-source statistics

    private struct StatisticsDay {
        let start: Date
        let end: Date
        let total: Double
        let sources: [SourceTotal]
    }

    private struct SourceTotal {
        let source: HKSource
        let value: Double
    }

    private struct DayBundle {
        let merged: HealthKitMergedStepDayUpload
        let sources: [HealthKitStepSourceDayUpload]
    }

    private static func dayBundles(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [DayBundle] {
        let merged = try await statisticsDays(
            store: store,
            type: type,
            start: start,
            end: end,
            calendar: calendar,
            separateBySource: false
        )
        let separated = try await statisticsDays(
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
        let separatedByDay = Dictionary(uniqueKeysWithValues: separated.map {
            (dayString($0.start, calendar: calendar), $0)
        })

        var result: [DayBundle] = []
        var cursor = calendar.startOfDay(for: start)
        while cursor <= end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let day = dayString(cursor, calendar: calendar)
            let effectiveEnd = min(next, end)
            let mergedValue = mergedByDay[day]?.total ?? 0
            let sourceRows = (separatedByDay[day]?.sources ?? []).map { total in
                HealthKitStepSourceDayUpload(
                    day: day,
                    startsAt: iso8601(cursor),
                    endsAt: iso8601(effectiveEnd),
                    timeZone: calendar.timeZone.identifier,
                    sourceName: total.source.name,
                    sourceBundleIdentifier: total.source.bundleIdentifier,
                    steps: total.value
                )
            }
            result.append(
                DayBundle(
                    merged: HealthKitMergedStepDayUpload(
                        day: day,
                        steps: Int(mergedValue.rounded())
                    ),
                    sources: sourceRows
                )
            )
            cursor = next
        }
        return result
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
            if separateBySource {
                options.insert(.separateBySource)
            }
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
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var days: [StatisticsDay] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let sourceTotals: [SourceTotal]
                    if separateBySource {
                        sourceTotals = (statistics.sources ?? []).compactMap { source in
                            guard let quantity = statistics.sumQuantity(for: source) else { return nil }
                            return SourceTotal(
                                source: source,
                                value: quantity.doubleValue(for: .count())
                            )
                        }
                    } else {
                        sourceTotals = []
                    }
                    days.append(
                        StatisticsDay(
                            start: statistics.startDate,
                            end: statistics.endDate,
                            total: statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0,
                            sources: sourceTotals
                        )
                    )
                }
                continuation.resume(returning: days)
            }
            store.execute(query)
        }
    }

    // MARK: - Raw sample fidelity

    private static func sampleUpload(
        _ sample: HKQuantitySample,
        calendar: Calendar
    ) -> HealthKitStepSampleUpload {
        let revision = sample.sourceRevision
        let os = revision.operatingSystemVersion
        let device = sample.device
        let metadata = (sample.metadata ?? [:]).mapValues(metadataValue)
        let userEntered = (sample.metadata?[HKMetadataKeyWasUserEntered] as? NSNumber)?.boolValue

        return HealthKitStepSampleUpload(
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
            metadata: metadata,
            userEntered: userEntered
        )
    }

    private static func metadataValue(_ raw: Any) -> HealthKitMetadataValueUpload {
        if let date = raw as? Date {
            return HealthKitMetadataValueUpload(kind: "date", value: iso8601(date), objcType: nil)
        }
        if let number = raw as? NSNumber {
            let isBoolean = CFGetTypeID(number) == CFBooleanGetTypeID()
            return HealthKitMetadataValueUpload(
                kind: isBoolean ? "boolean" : "number",
                value: isBoolean ? String(number.boolValue) : number.stringValue,
                objcType: String(cString: number.objCType)
            )
        }
        if let string = raw as? String {
            return HealthKitMetadataValueUpload(kind: "string", value: string, objcType: nil)
        }
        return HealthKitMetadataValueUpload(
            kind: String(reflecting: type(of: raw)),
            value: String(describing: raw),
            objcType: nil
        )
    }

    // MARK: - Persistence helpers

    private static func ingest(
        client: SupabaseClient,
        payload: HealthKitStepPayload
    ) async throws {
        try await client
            .rpc("ingest_healthkit_steps", params: HealthKitStepRPCParameters(payload: payload))
            .execute()
    }

    private static func loadAnchor(defaults: UserDefaults, key: String) -> HKQueryAnchor? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func saveAnchor(
        _ anchor: HKQueryAnchor,
        defaults: UserDefaults,
        key: String
    ) throws {
        let data = try NSKeyedArchiver.archivedData(
            withRootObject: anchor,
            requiringSecureCoding: true
        )
        defaults.set(data, forKey: key)
    }

    private static func chunks<Element>(of values: [Element], limit: Int) -> [[Element]] {
        guard !values.isEmpty else { return [] }
        return stride(from: 0, to: values.count, by: limit).map { offset in
            Array(values[offset..<min(offset + limit, values.count)])
        }
    }

    private static func minimum(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case (.none, .none): return nil
        case (.some(let value), .none), (.none, .some(let value)): return value
        case (.some(let lhs), .some(let rhs)): return min(lhs, rhs)
        }
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

private struct SyncKeys {
    let anchor: String
    let earliestSample: String

    init(userId: UUID) {
        let suffix = userId.uuidString.lowercased()
        anchor = "ff.healthkit.stepsAnchor.\(suffix)"
        earliestSample = "ff.healthkit.stepsEarliest.\(suffix)"
    }
}

private struct HealthKitStepRPCParameters: Encodable {
    let payload: HealthKitStepPayload

    enum CodingKeys: String, CodingKey {
        case payload = "_payload"
    }
}

private struct HealthKitStepPayload: Encodable {
    var samples: [HealthKitStepSampleUpload] = []
    var deletions: [HealthKitStepDeletionUpload] = []
    var mergedDays: [HealthKitMergedStepDayUpload] = []
    var sourceDays: [HealthKitStepSourceDayUpload] = []
    var sync: HealthKitStepSyncUpload?

    enum CodingKeys: String, CodingKey {
        case samples
        case deletions
        case mergedDays = "merged_days"
        case sourceDays = "source_days"
        case sync
    }
}

private struct HealthKitStepSampleUpload: Encodable {
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
    let sourceOSVersion: String
    let deviceName: String?
    let deviceManufacturer: String?
    let deviceModel: String?
    let deviceHardwareVersion: String?
    let deviceFirmwareVersion: String?
    let deviceSoftwareVersion: String?
    let deviceLocalIdentifier: String?
    let deviceUDIIdentifier: String?
    let metadata: [String: HealthKitMetadataValueUpload]
    let userEntered: Bool?

    enum CodingKeys: String, CodingKey {
        case sampleId = "sample_id"
        case value
        case unit
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
        case metadata
        case userEntered = "user_entered"
    }
}

private struct HealthKitMetadataValueUpload: Encodable {
    let kind: String
    let value: String
    let objcType: String?

    enum CodingKeys: String, CodingKey {
        case kind
        case value
        case objcType = "objc_type"
    }
}

private struct HealthKitStepDeletionUpload: Encodable {
    let sampleId: UUID

    enum CodingKeys: String, CodingKey {
        case sampleId = "sample_id"
    }
}

private struct HealthKitMergedStepDayUpload: Encodable {
    let day: String
    let steps: Int
}

private struct HealthKitStepSourceDayUpload: Encodable {
    let day: String
    let startsAt: String
    let endsAt: String
    let timeZone: String
    let sourceName: String
    let sourceBundleIdentifier: String
    let steps: Double

    enum CodingKeys: String, CodingKey {
        case day
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeZone = "time_zone"
        case sourceName = "source_name"
        case sourceBundleIdentifier = "source_bundle_identifier"
        case steps
    }
}

private struct HealthKitStepSyncUpload: Encodable {
    let timeZone: String
    let accessibleFrom: String
    let completeThrough: String

    enum CodingKeys: String, CodingKey {
        case timeZone = "time_zone"
        case accessibleFrom = "accessible_from"
        case completeThrough = "complete_through"
    }
}

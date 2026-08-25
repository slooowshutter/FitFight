import Combine
import Foundation
import HealthKit
import Supabase

@MainActor
final class HealthKitStepsStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case reading
        case steps(count: Int, sources: [String])
        case empty
    }

    @Published private(set) var status: Status = .idle

    private let store = HKHealthStore()
    private let askedKey = "ff.healthkit.stepsAsked"
    private let connectedKey = "ff.healthkit.appleHealthConnected"
    private let lastUploadDayKey = "ff.healthkit.lastUploadDay"
    private var isUploading = false

    var hasAsked: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    var detailText: String {
        switch status {
        case .idle:
            return "Tap to read Steps"
        case .reading:
            return "Reading…"
        case .steps(let count, _):
            return "\(Self.format(count)) steps today"
        case .empty:
            return "No accessible data"
        }
    }

    var metaText: String {
        switch status {
        case .steps(_, let sources):
            return sources.joined(separator: ", ")
        default:
            return ""
        }
    }

    var isConnected: Bool {
        if case .steps = status { return true }
        return false
    }

    func refresh(requestAccess: Bool) async {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else {
            if requestAccess || hasAsked {
                status = .empty
            }
            return
        }

        if requestAccess {
            do {
                try await store.requestAuthorization(toShare: [], read: [stepsType])
            } catch {
                // HealthKit does not distinguish denial from an empty store.
            }
            UserDefaults.standard.set(true, forKey: askedKey)
        }

        guard requestAccess || hasAsked else { return }

        status = .reading
        do {
            if let result = try await Self.todayAggregate(store: store, type: stepsType) {
                status = .steps(count: result.count, sources: result.sources)
            } else {
                status = .empty
            }
        } catch {
            status = .empty
        }
    }

    /// Upload Apple Health daily aggregates to `step_days`. Skips if Health was never asked.
    func syncToSupabase(client: SupabaseClient, userId: UUID) async {
        guard hasAsked, !isUploading else { return }
        guard
            HKHealthStore.isHealthDataAvailable(),
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return }

        isUploading = true
        defer { isUploading = false }

        do {
            let calendar = Calendar.current
            let today = calendar.startOfDay(for: Date())
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"

            var rows: [StepDayUpload] = []
            rows.reserveCapacity(31)
            for offset in 0...30 {
                guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
                let day = formatter.string(from: start)
                let end = offset == 0 ? Date() : calendar.date(byAdding: .day, value: 1, to: start) ?? start
                let value = try await Self.dayAggregate(store: store, type: stepsType, start: start, end: end)
                rows.append(StepDayUpload(userId: userId, day: day, steps: Int(value.rounded())))
            }
            guard !rows.isEmpty else { return }

            try await client.from("step_days")
                .upsert(rows, onConflict: "user_id,day")
                .execute()
            UserDefaults.standard.set(formatter.string(from: today), forKey: lastUploadDayKey)
            UserDefaults.standard.set(true, forKey: connectedKey)
        } catch {
            // Local read still works if the table is not on this project yet.
        }
    }

    private struct TodayAggregate {
        var count: Int
        var sources: [String]
    }

    /// One civil day's Apple Health aggregate. Do not sum every raw sample/source.
    private static func dayAggregate(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    /// HealthKit aggregate for today. Do not sum every raw sample/source.
    private static func todayAggregate(
        store: HKHealthStore,
        type: HKQuantityType
    ) async throws -> TodayAggregate? {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: .strictStartDate
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum, .separateBySource]
        )
        guard let stats = try await descriptor.result(for: store) else {
            return nil
        }
        let value = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
        var seen = Set<String>()
        let labels = (stats.sources ?? []).compactMap { source -> String? in
            let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
        if value <= 0 && labels.isEmpty {
            return nil
        }
        return TodayAggregate(count: Int(value.rounded()), sources: labels)
    }

    private static func format(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

private struct StepDayUpload: Encodable {
    let userId: UUID
    let day: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case day
        case steps
    }
}

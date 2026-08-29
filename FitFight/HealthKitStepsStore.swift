import Combine
import Foundation
import HealthKit

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
    private let api = FitFightAPI()
    private let askedKey = "ff.healthkit.stepsAsked"
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

    /// Archive raw changes, source statistics, and Apple's merged daily totals.
    func syncToBackend(accessToken: String, userId: UUID) async {
        guard hasAsked, !isUploading, api.isConfigured else { return }
        guard
            HKHealthStore.isHealthDataAvailable(),
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else { return }

        isUploading = true
        defer { isUploading = false }

        do {
            try await HealthKitStepArchive.sync(
                store: store,
                type: stepsType,
                api: api,
                accessToken: accessToken,
                userId: userId
            )
        } catch {
            // Local reading remains useful if a network or archive write fails.
        }
    }

    private struct TodayAggregate {
        var count: Int
        var sources: [String]
    }

    /// Apple's merged total is authoritative. A separate statistics query is
    /// used only to list contributing sources and is never added into the score.
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
        let samplePredicate = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let mergedDescriptor = HKStatisticsQueryDescriptor(
            predicate: samplePredicate,
            options: [.cumulativeSum]
        )
        let sourceDescriptor = HKStatisticsQueryDescriptor(
            predicate: samplePredicate,
            options: [.cumulativeSum, .separateBySource]
        )
        guard let mergedStats = try await mergedDescriptor.result(for: store) else {
            return nil
        }
        let sourceStats = try await sourceDescriptor.result(for: store)
        let value = mergedStats.sumQuantity()?.doubleValue(for: .count()) ?? 0
        var seen = Set<String>()
        let labels = (sourceStats?.sources ?? []).compactMap { source -> String? in
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

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
    private let askedKey = "ff.healthkit.stepsAsked"

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

    private struct TodayAggregate {
        var count: Int
        var sources: [String]
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

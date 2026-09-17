import Foundation

// API_MODELS
struct HKQuantityType {}
final class HKHealthStore {
    var samples: [(Date, Int)] = []
    var reads: [(Date, Date)] = []
}
struct HealthKitSyncTrace {
    enum Stage { case healthKitDaily, healthKitFight }
    func measure<T>(_ stage: Stage, work: () async throws -> T) async rethrows -> T { try await work() }
}

enum HealthKitStepAggregates {
    enum ReadError: Error { case noAccessibleSteps }
    // PRODUCTION_METHODS

    private static func total(store: HKHealthStore, type: HKQuantityType, start: Date, end: Date) async throws -> Int? {
        store.reads.append((start, end))
        return store.samples.filter { $0.0 >= start && $0.0 < end }.reduce(0) { $0 + $1.1 }
    }
    private static func dailyTotals(store: HKHealthStore, type: HKQuantityType, start: Date, end: Date, calendar: Calendar) async throws -> [String: Int] {
        var values: [String: Int] = [:]
        for (date, value) in store.samples where date >= start && date < end {
            values[dayStamp(date, calendar: calendar), default: 0] += value
        }
        return values
    }
}

@main struct HealthKitStepCheckpointTests {
    static func main() async throws {
        let parser = ISO8601DateFormatter()
        let store = HKHealthStore()
        store.samples = [
            (parser.date(from: "2026-03-28T08:00:00Z")!, 8000),
            (parser.date(from: "2026-03-28T15:00:00Z")!, 4000),
            (parser.date(from: "2026-03-29T09:00:00Z")!, 3000),
            (parser.date(from: "2026-03-30T09:00:00Z")!, 2000),
            (parser.date(from: "2026-03-30T13:00:00Z")!, 9000)
        ]
        let start = parser.date(from: "2026-03-28T12:00:00Z")!
        let cutoff = parser.date(from: "2026-03-30T12:00:00Z")!
        var context = FitFightHealthKitContext(serverNow: cutoff, fightWindows: [
            .init(fightId: UUID(), state: "live", startsAt: start, endsAt: cutoff, cutoffAt: cutoff, timeZone: "Europe/Paris")
        ])
        let result = try await HealthKitStepAggregates.read(store: store, type: HKQuantityType(), context: context, trace: HealthKitSyncTrace())
        let fight = result.fightAggregates[0]
        precondition(fight.steps == 9000, "Only the Fight-window query determines the score")
        precondition(fight.stepCheckpoints?.map(\.steps) == [4000, 7000, 9000])
        precondition(fight.stepCheckpoints?.map(\.day) == ["2026-03-28", "2026-03-29", "2026-03-30"])
        precondition(fight.stepCheckpoints?.map(\.cutoffAt) == ["2026-03-28T23:00:00.000Z", "2026-03-29T22:00:00.000Z", "2026-03-30T12:00:00.000Z"])
        precondition(store.reads.allSatisfy { $0.0 == start && $0.1 <= cutoff }, "All cumulative points use the identical Fight start")
        precondition(store.reads.filter { $0.1 == cutoff }.count == 1, "The total must reuse the final checkpoint query")
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(result)) as! [String: Any]
        let aggregates = encoded["fight_aggregates"] as! [[String: Any]]
        precondition((aggregates[0]["step_checkpoints"] as? [[String: Any]])?.count == 3)

        let savedZone = TimeZone(identifier: "America/New_York")!
        NSTimeZone.default = TimeZone(identifier: "Asia/Tokyo")!
        let atHome = try await HealthKitStepAggregates.read(store: store, type: HKQuantityType(), context: context, trace: HealthKitSyncTrace(), timeZone: savedZone)
        precondition(atHome.timeZone == "America/New_York")
        precondition(atHome.mergedDays.first?.startsAt == "2026-03-28T04:00:00.000Z", "Daily Steps start at midnight in the saved zone")
        NSTimeZone.default = TimeZone(identifier: "Pacific/Kiritimati")!
        let traveling = try await HealthKitStepAggregates.read(store: store, type: HKQuantityType(), context: context, trace: HealthKitSyncTrace(), timeZone: savedZone)
        precondition(traveling.mergedDays.map(\.startsAt) == atHome.mergedDays.map(\.startsAt))
        precondition(traveling.mergedDays.map(\.steps) == atHome.mergedDays.map(\.steps), "Device travel cannot shift personal days")
        precondition(traveling.fightAggregates[0].steps == fight.steps)
        precondition(traveling.fightAggregates[0].stepCheckpoints == fight.stepCheckpoints, "Fight days keep their separate time zone")

        context.fightWindows[0].cutoffAt = parser.date(from: "2026-03-29T22:00:00Z")!
        context.serverNow = context.fightWindows[0].cutoffAt
        let midnight = try await HealthKitStepAggregates.read(store: store, type: HKQuantityType(), context: context, trace: HealthKitSyncTrace())
        precondition(midnight.fightAggregates[0].stepCheckpoints?.map(\.day) == ["2026-03-28", "2026-03-29"], "Midnight has no extra zero day")
        context.fightWindows[0].timeZone = nil
        let legacy = try await HealthKitStepAggregates.read(store: store, type: HKQuantityType(), context: context, trace: HealthKitSyncTrace())
        precondition(legacy.fightAggregates[0].stepCheckpoints == nil, "An older backend receives its original upload contract")
        print("HealthKit checkpoints: noon start, cutoff, DST, midnight, encoding, and older backend passed")
    }
}

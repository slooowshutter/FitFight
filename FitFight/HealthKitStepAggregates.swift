import Foundation
import HealthKit

enum HealthKitStepAggregates {
    enum ReadError: Error {
        case noAccessibleSteps
        case invalidStepCount
    }

    /// Same cap as `healthKitAggregateSyncSchema`. `Int(Double)` can wrap out-of-range values.
    static let maxCount = 2_147_483_647

    static func integerCount(from quantity: HKQuantity?) -> Int? {
        guard let quantity else { return nil }
        let steps = quantity.doubleValue(for: .count())
        guard steps.isFinite, steps >= 0, steps <= Double(maxCount) else { return nil }
        return Int(exactly: steps.rounded())
    }

    static func read(
        store: HKHealthStore,
        type: HKQuantityType,
        context: FitFightHealthKitContext,
        trace: HealthKitSyncTrace,
        timeZone: TimeZone = .current
    ) async throws -> FitFightHealthKitStepSync {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let earliestDay = context.fightWindows
            .map { calendar.startOfDay(for: $0.startsAt) }
            .min()
        let totalsByDay: [String: Int]
        if let earliestDay {
            try Task.checkCancellation()
            totalsByDay = try await trace.measure(.healthKitDaily) {
                try await dailyTotals(
                    store: store,
                    type: type,
                    start: earliestDay,
                    end: context.serverNow,
                    calendar: calendar
                )
            }
        } else {
            totalsByDay = [:]
        }

        var mergedDays: [FitFightHealthKitStepSync.MergedDay] = []
        if var cursor = earliestDay {
            while cursor < context.serverNow {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                let day = dayStamp(cursor, calendar: calendar)
                let endsAt = min(nextDay, context.serverNow)
                if context.fightWindows.contains(where: {
                    cursor < $0.cutoffAt && endsAt > $0.startsAt
                }), let steps = totalsByDay[day] {
                    mergedDays.append(FitFightHealthKitStepSync.MergedDay(
                        day: day,
                        startsAt: iso8601(cursor),
                        endsAt: iso8601(endsAt),
                        steps: steps
                    ))
                }
                cursor = nextDay
            }
        }

        var fightAggregates: [FitFightHealthKitStepSync.FightAggregate] = []
        fightAggregates.reserveCapacity(context.fightWindows.count)
        var sawAccessibleSteps = !totalsByDay.isEmpty
        for window in context.fightWindows {
            try Task.checkCancellation()
            var checkpoints: [FightStepCheckpoint]? = nil
            var fightCalendar: Calendar? = nil
            var partialDay: Date? = nil
            if let timeZone = window.timeZone, let zone = TimeZone(identifier: timeZone) {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = zone
                fightCalendar = calendar
                checkpoints = []
                var day = calendar.startOfDay(for: window.startsAt)
                while let nextDay = calendar.date(byAdding: .day, value: 1, to: day),
                      nextDay < window.cutoffAt {
                    try Task.checkCancellation()
                    let count = try await trace.measure(.healthKitFight) {
                        try await total(store: store, type: type, start: window.startsAt, end: nextDay)
                    }
                    checkpoints?.append(FightStepCheckpoint(
                        day: dayStamp(day, calendar: calendar), cutoffAt: iso8601(nextDay), steps: count ?? 0
                    ))
                    day = nextDay
                }
                partialDay = day
            }
            let counted = try await trace.measure(.healthKitFight) {
                try await total(
                    store: store,
                    type: type,
                    start: window.startsAt,
                    end: window.cutoffAt
                )
            }
            if counted != nil {
                sawAccessibleSteps = true
            }
            if let calendar = fightCalendar, let day = partialDay {
                // The score reuses this final query; separately rounded daily totals cannot define it.
                checkpoints?.append(FightStepCheckpoint(
                    day: dayStamp(day, calendar: calendar),
                    cutoffAt: iso8601(window.cutoffAt), steps: counted ?? 0
                ))
            }
            fightAggregates.append(FitFightHealthKitStepSync.FightAggregate(
                fightId: window.fightId.uuidString.lowercased(),
                startsAt: iso8601(window.startsAt),
                endsAt: iso8601(window.endsAt),
                cutoffAt: iso8601(window.cutoffAt),
                steps: counted ?? 0,
                stepCheckpoints: checkpoints
            ))
        }
        if !context.fightWindows.isEmpty && !sawAccessibleSteps {
            throw ReadError.noAccessibleSteps
        }

        return FitFightHealthKitStepSync(
            completeThrough: iso8601(context.serverNow),
            timeZone: calendar.timeZone.identifier,
            mergedDays: mergedDays,
            fightAggregates: fightAggregates
        )
    }

    private static func dailyTotals(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: Int] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: [.cumulativeSum],
                anchorDate: calendar.startOfDay(for: start),
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var totals: [String: Int] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let count = integerCount(from: statistics.sumQuantity()) else { return }
                    totals[dayStamp(statistics.startDate, calendar: calendar)] = count
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    private static func total(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> Int? {
        // NOTE: Do not use strictStartDate/strictEndDate. Apple stores Steps in samples
        // that often begin before the fight or are still open past "now". Strict options
        // drop those samples, a brand-new or late-join window can look empty, and that
        // used to abort every fight in the same upload. Overlapping samples let HealthKit
        // count the portion inside starts_at...cutoff_at.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum]
        )
        guard let quantity = try await descriptor.result(for: store)?.sumQuantity() else {
            return nil
        }
        guard let count = integerCount(from: quantity) else {
            throw ReadError.invalidStepCount
        }
        return count
    }

    /// Gregorian day key in the calendar's zone. A sync stamps hundreds of days and
    /// samples, so no formatter is built per call.
    static func dayStamp(_ date: Date, calendar: Calendar) -> String {
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", day.year ?? 0, day.month ?? 0, day.day ?? 0)
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func iso8601(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }
}

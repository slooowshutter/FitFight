import Foundation
import HealthKit

enum HealthKitStepAggregates {
    static func read(
        store: HKHealthStore,
        type: HKQuantityType,
        context: FitFightHealthKitContext
    ) async throws -> FitFightHealthKitStepSync {
        let calendar = Calendar.current
        let earliestDay = context.fightWindows
            .map { calendar.startOfDay(for: $0.startsAt) }
            .min()
        let totalsByDay: [String: Int]
        if let earliestDay {
            totalsByDay = try await dailyTotals(
                store: store,
                type: type,
                start: earliestDay,
                end: context.serverNow,
                calendar: calendar
            )
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
                }) {
                    mergedDays.append(FitFightHealthKitStepSync.MergedDay(
                        day: day,
                        startsAt: iso8601(cursor),
                        endsAt: iso8601(endsAt),
                        steps: totalsByDay[day] ?? 0
                    ))
                }
                cursor = nextDay
            }
        }

        var fightAggregates: [FitFightHealthKitStepSync.FightAggregate] = []
        fightAggregates.reserveCapacity(context.fightWindows.count)
        for window in context.fightWindows {
            let steps = try await total(
                store: store,
                type: type,
                start: window.startsAt,
                end: window.cutoffAt
            )
            fightAggregates.append(FitFightHealthKitStepSync.FightAggregate(
                fightId: window.fightId.uuidString.lowercased(),
                startsAt: iso8601(window.startsAt),
                endsAt: iso8601(window.endsAt),
                cutoffAt: iso8601(window.cutoffAt),
                steps: steps
            ))
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
                    let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    totals[dayStamp(statistics.startDate, calendar: calendar)] = Int(steps.rounded())
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
    ) async throws -> Int {
        // NOTE: Do not use strictStartDate/strictEndDate. Apple often stores Steps in
        // samples that begin before the fight or are still open past "now". Strict
        // options drop those samples and a late join can show 0. Overlapping samples
        // let HealthKit interpolate the exact fight window.
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum]
        )
        let steps = try await descriptor.result(for: store)?
            .sumQuantity()?.doubleValue(for: .count()) ?? 0
        return Int(steps.rounded())
    }

    private static func dayStamp(_ date: Date, calendar: Calendar) -> String {
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

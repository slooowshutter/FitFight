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
        var totals: [String: Int] = [:]
        var cursor = calendar.startOfDay(for: start)
        while cursor < end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let dayEnd = min(nextDay, end)
            guard dayEnd > cursor else { break }
            let steps = try await total(
                store: store,
                type: type,
                start: cursor,
                end: dayEnd,
                sampleOptions: .strictStartDate
            )
            totals[dayStamp(cursor, calendar: calendar)] = steps
            cursor = nextDay
        }
        return totals
    }

    private static func total(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date,
        sampleOptions: HKQueryOptions = [.strictStartDate, .strictEndDate]
    ) async throws -> Int {
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: sampleOptions
        )
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

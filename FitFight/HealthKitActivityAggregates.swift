import Foundation
import HealthKit

enum HealthKitActivityAggregates {
    struct QuantityKind {
        let metric: String
        let unitName: String
        let type: HKQuantityType
        let unit: HKUnit
    }

    struct TotalKind {
        let metric: String
        let unitName: String
        let type: HKSampleType
        let unit: HKUnit?
    }

    static var totalKinds: [TotalKind] {
        var kinds = quantityKinds.map {
            TotalKind(metric: $0.metric, unitName: $0.unitName, type: $0.type, unit: $0.unit)
        }
        if let steps = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            kinds.insert(TotalKind(metric: "steps", unitName: "steps", type: steps, unit: .count()), at: 0)
        }
        if let stand = HKCategoryType.categoryType(forIdentifier: .appleStandHour) {
            kinds.append(TotalKind(metric: "stand_hours", unitName: "count", type: stand, unit: nil))
        }
        return kinds
    }

    static func mergedDays(
        store: HKHealthStore,
        kind: TotalKind,
        start: Date,
        end: Date,
        calendar: Calendar,
        zeroDays: Set<String>
    ) async throws -> [FitFightHealthKitStepSync.ActivityDay] {
        let totals: [String: Double]
        if let quantityType = kind.type as? HKQuantityType, let unit = kind.unit {
            totals = try await dailyTotals(
                store: store, type: quantityType, unit: unit,
                start: start, end: end, calendar: calendar
            )
        } else {
            totals = try await standHours(store: store, start: start, end: end, calendar: calendar)
        }
        var days: [FitFightHealthKitStepSync.ActivityDay] = []
        var cursor = start
        while cursor < end {
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let day = HealthKitStepAggregates.dayStamp(cursor, calendar: calendar)
            if let measured = totals[day] ?? (zeroDays.contains(day) ? 0 : nil) {
                days.append(FitFightHealthKitStepSync.ActivityDay(
                    day: day,
                    startsAt: HealthKitStepAggregates.iso8601(cursor),
                    endsAt: HealthKitStepAggregates.iso8601(min(nextDay, end)),
                    metric: kind.metric,
                    value: kind.metric == "steps" ? measured.rounded() : measured,
                    unit: kind.unitName
                ))
            }
            cursor = nextDay
        }
        return days
    }

    static var sampleKinds: [TotalKind] {
        var kinds = totalKinds
        if let effort = HKQuantityType.quantityType(forIdentifier: .physicalEffort) {
            let met = HKUnit.kilocalorie().unitDivided(
                by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .hour())
            )
            kinds.append(TotalKind(metric: "physical_effort", unitName: "met", type: effort, unit: met))
        }
        if #available(iOS 18.0, *) {
            if let score = HKQuantityType.quantityType(forIdentifier: .workoutEffortScore) {
                kinds.append(TotalKind(metric: "workout_effort_score", unitName: "score",
                    type: score, unit: .appleEffortScore()))
            }
            if let estimated = HKQuantityType.quantityType(forIdentifier: .estimatedWorkoutEffortScore) {
                kinds.append(TotalKind(metric: "estimated_workout_effort_score", unitName: "score",
                    type: estimated, unit: .appleEffortScore()))
            }
        }
        return kinds
    }

    static var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(sampleKinds.map { $0.type as HKObjectType })
        types.insert(HKObjectType.workoutType())
        return types
    }

    static var quantityKinds: [QuantityKind] {
        var kinds: [QuantityKind] = []
        func add(
            _ metric: String,
            _ unitName: String,
            _ identifier: HKQuantityTypeIdentifier,
            _ unit: HKUnit
        ) {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return }
            kinds.append(QuantityKind(metric: metric, unitName: unitName, type: type, unit: unit))
        }
        add("active_energy", "kcal", .activeEnergyBurned, .kilocalorie())
        add("resting_energy", "kcal", .basalEnergyBurned, .kilocalorie())
        add("walking_running_distance", "m", .distanceWalkingRunning, .meter())
        add("exercise_minutes", "min", .appleExerciseTime, .minute())
        add("stand_minutes", "min", .appleStandTime, .minute())
        add("flights_climbed", "count", .flightsClimbed, .count())
        add("cycling_distance", "m", .distanceCycling, .meter())
        add("swimming_distance", "m", .distanceSwimming, .meter())
        add("move_time_minutes", "min", .appleMoveTime, .minute())
        add("wheelchair_distance", "m", .distanceWheelchair, .meter())
        add("wheelchair_pushes", "count", .pushCount, .count())
        add("swimming_strokes", "count", .swimmingStrokeCount, .count())
        add("downhill_snow_distance", "m", .distanceDownhillSnowSports, .meter())
        if #available(iOS 18.0, *) {
            add("rowing_distance", "m", .distanceRowing, .meter())
            add("paddle_distance", "m", .distancePaddleSports, .meter())
            add("skating_distance", "m", .distanceSkatingSports, .meter())
            add("cross_country_ski_distance", "m", .distanceCrossCountrySkiing, .meter())
        }
        return kinds
    }

    static func dailyTotals(
        store: HKHealthStore,
        type: HKQuantityType,
        unit: HKUnit,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end
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
                var totals: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    guard let value = quantityValue(statistics.sumQuantity(), unit: unit) else { return }
                    totals[HealthKitStepAggregates.dayStamp(statistics.startDate, calendar: calendar)] = value
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    private static func standHours(
        store: HKHealthStore,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: Double] {
        guard let type = HKCategoryType.categoryType(forIdentifier: .appleStandHour) else {
            return [:]
        }
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: (samples as? [HKCategorySample]) ?? [])
            }
            store.execute(query)
        }
        var totals: [String: Double] = [:]
        for sample in samples where sample.value == HKCategoryValueAppleStandHour.stood.rawValue {
            totals[HealthKitStepAggregates.dayStamp(sample.startDate, calendar: calendar), default: 0] += 1
        }
        return totals
    }

    private static func quantityValue(_ quantity: HKQuantity?, unit: HKUnit) -> Double? {
        guard let quantity, quantity.is(compatibleWith: unit) else { return nil }
        let value = quantity.doubleValue(for: unit)
        guard value.isFinite, value >= 0, value <= Double(HealthKitStepAggregates.maxCount) else {
            return nil
        }
        return value
    }

}

import Foundation
import HealthKit

enum HealthKitCollection {
    static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = []
        for spec in quantitySpecs {
            if let type = HKQuantityType.quantityType(forIdentifier: spec.identifier) {
                types.insert(type)
            }
        }
        for extra in [HKQuantityTypeIdentifier.distanceCycling, .distanceSwimming] {
            if let type = HKQuantityType.quantityType(forIdentifier: extra) {
                types.insert(type)
            }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let mindful = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            types.insert(mindful)
        }
        types.insert(HKObjectType.workoutType())
        return types
    }

    static func read(store: HKHealthStore, now: Date) async -> FitFightHealthKitCollection {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -399, to: today) ?? today
        var days: [FitFightHealthKitCollection.Day] = []
        for spec in quantitySpecs {
            guard let type = HKQuantityType.quantityType(forIdentifier: spec.identifier) else {
                continue
            }
            let totals: [String: Double]
            do {
                totals = try await dailyTotals(
                    store: store,
                    type: type,
                    unit: spec.unit,
                    options: spec.options,
                    start: start,
                    end: now,
                    calendar: calendar
                )
            } catch {
                continue
            }
            var cursor = start
            while cursor < now {
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
                let day = dayStamp(cursor, calendar: calendar)
                let value = totals[day] ?? 0
                if value > 0 {
                    days.append(FitFightHealthKitCollection.Day(
                        day: day,
                        metric: spec.metric,
                        value: value,
                        unit: spec.unitName,
                        startsAt: iso8601(cursor),
                        endsAt: iso8601(min(nextDay, now))
                    ))
                }
                cursor = nextDay
            }
        }

        var sessions: [FitFightHealthKitCollection.Session] = []
        sessions.append(contentsOf: await workouts(store: store, start: start, end: now))
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            sessions.append(contentsOf: await categorySessions(
                store: store,
                type: sleepType,
                kind: "sleep",
                start: start,
                end: now,
                activityType: sleepStage
            ))
        }
        if let mindfulType = HKObjectType.categoryType(forIdentifier: .mindfulSession) {
            sessions.append(contentsOf: await categorySessions(
                store: store,
                type: mindfulType,
                kind: "mindful",
                start: start,
                end: now,
                activityType: { _ in "mindful" }
            ))
        }
        sessions.sort { $0.endsAt > $1.endsAt }
        if sessions.count > 2000 {
            sessions = Array(sessions.prefix(2000))
        }

        return FitFightHealthKitCollection(
            completeThrough: iso8601(now),
            timeZone: calendar.timeZone.identifier,
            days: days,
            sessions: sessions
        )
    }

    private struct QuantitySpec {
        let identifier: HKQuantityTypeIdentifier
        let metric: String
        let unit: HKUnit
        let unitName: String
        let options: HKStatisticsOptions
    }

    private static let quantitySpecs: [QuantitySpec] = [
        QuantitySpec(
            identifier: .distanceWalkingRunning,
            metric: "distance_walking_running",
            unit: .meter(),
            unitName: "m",
            options: .cumulativeSum
        ),
        QuantitySpec(
            identifier: .flightsClimbed,
            metric: "flights_climbed",
            unit: .count(),
            unitName: "count",
            options: .cumulativeSum
        ),
        QuantitySpec(
            identifier: .activeEnergyBurned,
            metric: "active_energy",
            unit: .kilocalorie(),
            unitName: "kcal",
            options: .cumulativeSum
        ),
        QuantitySpec(
            identifier: .basalEnergyBurned,
            metric: "basal_energy",
            unit: .kilocalorie(),
            unitName: "kcal",
            options: .cumulativeSum
        ),
        QuantitySpec(
            identifier: .appleExerciseTime,
            metric: "exercise_time",
            unit: .minute(),
            unitName: "min",
            options: .cumulativeSum
        ),
        QuantitySpec(
            identifier: .appleStandTime,
            metric: "stand_time",
            unit: .minute(),
            unitName: "min",
            options: .cumulativeSum
        ),
        QuantitySpec(
            identifier: .restingHeartRate,
            metric: "resting_heart_rate",
            unit: HKUnit.count().unitDivided(by: .minute()),
            unitName: "count/min",
            options: .discreteAverage
        ),
        QuantitySpec(
            identifier: .walkingHeartRateAverage,
            metric: "walking_heart_rate_average",
            unit: HKUnit.count().unitDivided(by: .minute()),
            unitName: "count/min",
            options: .discreteAverage
        ),
        QuantitySpec(
            identifier: .bodyMass,
            metric: "body_mass",
            unit: .gramUnit(with: .kilo),
            unitName: "kg",
            options: .discreteAverage
        ),
    ]

    private static func dailyTotals(
        store: HKHealthStore,
        type: HKQuantityType,
        unit: HKUnit,
        options: HKStatisticsOptions,
        start: Date,
        end: Date,
        calendar: Calendar
    ) async throws -> [String: Double] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
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
                var totals: [String: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = options.contains(.cumulativeSum)
                        ? statistics.sumQuantity()
                        : statistics.averageQuantity()
                    let value = quantity?.doubleValue(for: unit) ?? 0
                    if value > 0 {
                        totals[dayStamp(statistics.startDate, calendar: calendar)] = value
                    }
                }
                continuation.resume(returning: totals)
            }
            store.execute(query)
        }
    }

    private static func workouts(
        store: HKHealthStore,
        start: Date,
        end: Date
    ) async -> [FitFightHealthKitCollection.Session] {
        let samples: [HKSample]
        do {
            samples = try await samples(
                store: store,
                type: HKObjectType.workoutType(),
                start: start,
                end: end
            )
        } catch {
            return []
        }
        return samples.compactMap { sample in
            guard let workout = sample as? HKWorkout, workout.endDate > workout.startDate else {
                return nil
            }
            return FitFightHealthKitCollection.Session(
                sourceUuid: workout.uuid.uuidString.lowercased(),
                kind: "workout",
                activityType: String(workout.workoutActivityType.rawValue),
                startsAt: iso8601(workout.startDate),
                endsAt: iso8601(min(workout.endDate, end)),
                durationSeconds: workout.duration,
                energyKcal: statistic(workout, .activeEnergyBurned, unit: .kilocalorie()),
                distanceM: workoutDistance(workout)
            )
        }
    }

    private static func categorySessions(
        store: HKHealthStore,
        type: HKCategoryType,
        kind: String,
        start: Date,
        end: Date,
        activityType: (Int) -> String
    ) async -> [FitFightHealthKitCollection.Session] {
        let samples: [HKSample]
        do {
            samples = try await samples(store: store, type: type, start: start, end: end)
        } catch {
            return []
        }
        return samples.compactMap { sample in
            guard let category = sample as? HKCategorySample, category.endDate > category.startDate else {
                return nil
            }
            return FitFightHealthKitCollection.Session(
                sourceUuid: category.uuid.uuidString.lowercased(),
                kind: kind,
                activityType: activityType(category.value),
                startsAt: iso8601(category.startDate),
                endsAt: iso8601(min(category.endDate, end)),
                durationSeconds: category.endDate.timeIntervalSince(category.startDate),
                energyKcal: nil,
                distanceM: nil
            )
        }
    }

    private static func samples(
        store: HKHealthStore,
        type: HKSampleType,
        start: Date,
        end: Date
    ) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: 2000,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    private static func workoutDistance(_ workout: HKWorkout) -> Double? {
        for identifier in [
            HKQuantityTypeIdentifier.distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ] {
            if let meters = statistic(workout, identifier, unit: .meter()), meters > 0 {
                return meters
            }
        }
        return nil
    }

    private static func statistic(
        _ workout: HKWorkout,
        _ identifier: HKQuantityTypeIdentifier,
        unit: HKUnit
    ) -> Double? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        let value = workout.statistics(for: type)?.sumQuantity()?.doubleValue(for: unit)
        guard let value, value > 0 else { return nil }
        return value
    }

    private static func sleepStage(_ value: Int) -> String {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return "in_bed"
        case .asleepUnspecified: return "asleep"
        case .awake: return "awake"
        case .asleepCore: return "asleep_core"
        case .asleepDeep: return "asleep_deep"
        case .asleepREM: return "asleep_rem"
        default: return "sleep_\(value)"
        }
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

import HealthKit
import SwiftUI

/// Your last 31 days straight from Apple Health: daily Steps plus workout minutes per sport.
/// No targets: every number and bar is relative to your own days.
@MainActor
final class YouActivityStore: ObservableObject {
    struct Sport: Identifiable {
        let id: String
        let name: String
        let systemImage: String
        let isSteps: Bool
        /// 31 values, oldest first; the last one is today.
        let values: [Double]
    }

    @Published private(set) var sports: [Sport] = []
    @Published private(set) var days: [Date] = []
    /// Daily Steps for the past 8 weeks (56 days, today last), for the daily average and best day.
    @Published private(set) var eightWeekSteps: [Double] = []

    func load() async {
        let calendar = Calendar.current
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            let today = calendar.startOfDay(for: Date())
            days = (0..<31).compactMap { calendar.date(byAdding: .day, value: $0 - 30, to: today) }
            sports = [Sport(id: "steps", name: String(appLocalized: "Steps"), systemImage: "shoeprints.fill", isSteps: true, values: CompanionPreview.sampleSteps)]
                + CompanionPreview.sampleWorkouts.map { Sport(id: $0.0, name: $0.0, systemImage: $0.1, isSteps: false, values: $0.2) }
            eightWeekSteps = Array(CompanionPreview.sampleSteps.prefix(25).reversed()) + CompanionPreview.sampleSteps
            return
        }
        #endif
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -30, to: today),
              let eightWeeksAgo = calendar.date(byAdding: .day, value: -55, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        let dayList = (0..<31).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let index = { (date: Date) in calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? -1 }

        var longSteps = Array(repeating: 0.0, count: 56)
        if let collection = try? await Self.dailySteps(store: store, start: eightWeeksAgo, end: end) {
            collection.enumerateStatistics(from: eightWeeksAgo, to: end) { statistics, _ in
                let i = (calendar.dateComponents([.day], from: eightWeeksAgo, to: statistics.startDate).day ?? -1)
                if longSteps.indices.contains(i) { longSteps[i] = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0 }
            }
        }
        let steps = Array(longSteps.suffix(31))
        var minutes: [HKWorkoutActivityType: [Double]] = [:]
        for workout in (try? await Self.workouts(store: store, start: start, end: end)) ?? [] {
            let i = index(workout.startDate)
            guard (0..<31).contains(i) else { continue }
            minutes[workout.workoutActivityType, default: Array(repeating: 0, count: 31)][i] += workout.duration / 60
        }

        let workoutSports = minutes
            .sorted { $0.value.reduce(0, +) > $1.value.reduce(0, +) }
            .map { type, values in
                let (name, image) = Self.label(type)
                return Sport(id: "workout-\(type.rawValue)", name: name, systemImage: image, isSteps: false, values: values)
            }
        days = dayList
        eightWeekSteps = longSteps
        sports = [Sport(id: "steps", name: String(appLocalized: "Steps"), systemImage: "shoeprints.fill", isSteps: true, values: steps)] + workoutSports
    }

    private static func dailySteps(store: HKHealthStore, start: Date, end: Date) async throws -> HKStatisticsCollection {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: HKQuantityType(.stepCount),
                quantitySamplePredicate: HKQuery.predicateForSamples(withStart: start, end: end),
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, error in
                if let collection { continuation.resume(returning: collection) } else { continuation.resume(throwing: error ?? CancellationError()) }
            }
            store.execute(query)
        }
    }

    private static func workouts(store: HKHealthStore, start: Date, end: Date) async throws -> [HKWorkout] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: .workoutType(),
                predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: nil
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (samples as? [HKWorkout]) ?? []) }
            }
            store.execute(query)
        }
    }

    private static func label(_ type: HKWorkoutActivityType) -> (String, String) {
        switch type {
        case .walking: return (String(appLocalized: "Walk"), "figure.walk")
        case .running: return (String(appLocalized: "Run"), "figure.run")
        case .cycling: return (String(appLocalized: "Bike"), "bicycle")
        case .swimming: return (String(appLocalized: "Swim"), "figure.pool.swim")
        case .hiking: return (String(appLocalized: "Hike"), "figure.hiking")
        case .functionalStrengthTraining, .traditionalStrengthTraining: return (String(appLocalized: "Strength"), "dumbbell.fill")
        case .yoga: return (String(appLocalized: "Yoga"), "figure.yoga")
        default: return (String(appLocalized: "Workout"), "figure.mixed.cardio")
        }
    }
}

private func formatted(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale))
}

/// Today in big numbers, then four numbers from your profile statistics.
struct YouStatsCard: View {
    let todaySteps: Int?
    let statistics: ProfileStepStatistics?
    let record: ProfileRecord?
    /// Won, lost and drew from your fight history; nil until it loads.
    let results: (won: Int, lost: Int, drew: Int)?
    /// Other sports you did today, from Apple Health.
    let todayWorkouts: [YouActivityStore.Sport]
    /// Past 8 weeks of daily Steps from Apple Health; days without Steps are left out of the average.
    let eightWeekSteps: [Double]
    @Environment(\.ffTheme) private var theme

    // Today is still in progress, so the average and best day use the 55 finished days before it.
    private var recordedDays: [Double] { eightWeekSteps.dropLast().filter { $0 > 0 } }
    private var average: Double? { recordedDays.isEmpty ? statistics?.averageSteps : recordedDays.reduce(0, +) / Double(recordedDays.count) }
    private var best: Double? { recordedDays.max() ?? statistics?.bestDay?.steps }

    var body: some View {
        FFCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(appLocalized: "Today")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                    // The gap shares the big number's baseline, so both read as one line.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(todaySteps.map { formatted(Double($0)) } ?? "-")
                            .font(.ff(50, 800)).monospacedDigit().foregroundStyle(theme.text)
                            .minimumScaleFactor(0.6).lineLimit(1)
                        Text(String(appLocalized: "steps")).ffType(.caption).foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 8)
                        if let todaySteps, let average {
                            let gap = Double(todaySteps) - average
                            VStack(alignment: .trailing, spacing: 2) {
                                Text((gap >= 0 ? "+" : "-") + formatted(abs(gap))).font(.ff(22, 800)).monospacedDigit()
                                    .foregroundStyle(gap >= 0 ? theme.mossText : theme.emberText)
                                Text(String(appLocalized: "vs daily average")).ffType(.micro).foregroundStyle(theme.textSecondary)
                            }
                        }
                    }
                    if !todayWorkouts.isEmpty {
                        HStack(spacing: 12) {
                            ForEach(todayWorkouts) { sport in
                                HStack(spacing: 5) {
                                    Image(systemName: sport.systemImage).font(.system(size: 13, weight: .semibold)).foregroundStyle(theme.textSecondary)
                                    Text("\(formatted(sport.values[30])) \(String(appLocalized: "min"))").font(.ff(15, 800)).foregroundStyle(theme.text)
                                }
                            }
                        }
                    }
                }
                .padding(theme.space.cardPadding)
                Rectangle().fill(theme.hairline).frame(height: 1)
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        cell(Text(statistics.map { formatted($0.week.totalSteps) } ?? "-"), String(appLocalized: "this week"))
                        Rectangle().fill(theme.hairline).frame(width: 1)
                        if let results {
                            cell(Text("\(results.won)").foregroundStyle(theme.mossText) + Text("-") + Text("\(results.lost)").foregroundStyle(theme.emberText)
                                + Text("-") + Text("\(results.drew)").foregroundStyle(theme.textSecondary), String(appLocalized: "won · lost · drew"))
                        } else {
                            cell(Text(record.map { "\($0.wins)/\($0.played)" } ?? "-"), String(appLocalized: "fights won"))
                        }
                    }
                    Rectangle().fill(theme.hairline).frame(height: 1).gridCellColumns(3)
                    GridRow {
                        cell(Text(average.map(formatted) ?? "-"), String(appLocalized: "daily average"), note: String(appLocalized: "past 8 weeks"))
                        Rectangle().fill(theme.hairline).frame(width: 1)
                        cell(Text(best.map(formatted) ?? "-"), String(appLocalized: "best day"), note: String(appLocalized: "past 8 weeks"))
                    }
                }
            }
        }
    }

    private func cell(_ value: Text, _ label: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            value.font(.ff(22, 800)).monospacedDigit().foregroundStyle(theme.text)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(label).ffType(.caption).foregroundStyle(theme.textSecondary)
                if let note {
                    Text("(\(note))").ffType(.micro).foregroundStyle(theme.textFaint)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, theme.space.cardPadding)
        .padding(.vertical, 14)
        .accessibilityElement(children: .combine)
    }
}

/// One row per sport with Day, Week or Month totals; Steps always first.
struct YouSportList: View {
    let sports: [YouActivityStore.Sport]
    @State private var period = Period.month
    @Environment(\.ffTheme) private var theme

    enum Period: CaseIterable { case day, week, month }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            HStack {
                Text(String(appLocalized: "By sport")).ffType(.heading).foregroundStyle(theme.text)
                Spacer()
                FFSegmented(items: Period.allCases, selection: $period) { item in
                    switch item {
                    case .day: String(appLocalized: "Day")
                    case .week: String(appLocalized: "Week")
                    case .month: String(appLocalized: "Month")
                    }
                }
            }
            FFGroupedRows {
                ForEach(sports) { sport in row(sport) }
            }
        }
    }

    private func row(_ sport: YouActivityStore.Sport) -> some View {
        let window = period == .day ? 30...30 : period == .week ? 24...30 : 0...30
        let total = window.reduce(0) { $0 + sport.values[$1] }
        let peak = max(sport.values.max() ?? 0, 1)
        let perDay = sport.isSteps ? formatted(total / Double(window.count)) : "\(formatted(total / Double(window.count))) \(String(appLocalized: "min"))"
        return HStack(spacing: 12) {
            Image(systemName: sport.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(width: 40, height: 40)
                .background(theme.control, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(sport.name).ffType(.rowTitle).foregroundStyle(theme.text)
                Text(window.count == 1 ? String(appLocalized: "Today") : String(format: String(appLocalized: "you.per-day"), perDay))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                // A ruler of 31 equal ticks: brighter gold for bigger days, relative to your own best.
                HStack(spacing: 2) {
                    ForEach(sport.values.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(sport.values[i] > 0 ? theme.gold.opacity(0.35 + 0.65 * sport.values[i] / peak) : theme.control)
                            .frame(width: 3, height: 8)
                            .opacity(window.contains(i) ? 1 : 0.3)
                    }
                }
                .accessibilityHidden(true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 0) {
                Text(formatted(total)).font(.ff(28, 800)).monospacedDigit().foregroundStyle(theme.text)
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(sport.isSteps ? String(appLocalized: "steps") : String(appLocalized: "min")).ffType(.micro).foregroundStyle(theme.textSecondary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, theme.space.cardPadding)
        .accessibilityElement(children: .combine)
    }
}

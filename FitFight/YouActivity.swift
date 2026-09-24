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

    func load() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = HKHealthStore()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -30, to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return }
        let dayList = (0..<31).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let index = { (date: Date) in calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: date)).day ?? -1 }

        var steps = Array(repeating: 0.0, count: 31)
        if let collection = try? await Self.dailySteps(store: store, start: start, end: end) {
            collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                let i = index(statistics.startDate)
                if steps.indices.contains(i) { steps[i] = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0 }
            }
        }
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

/// A sideways strip of stat cards: today, this week, your average and best day, then fights.
struct YouStatStrip: View {
    let todaySteps: Int?
    let statistics: ProfileStepStatistics?
    let record: ProfileRecord?
    @Environment(\.ffTheme) private var theme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                card(String(appLocalized: "Today"), todaySteps.map { formatted(Double($0)) }, detail: todayDetail)
                card(String(appLocalized: "This week"), statistics.map { formatted($0.week.totalSteps) }, detail: String(appLocalized: "steps"))
                card(String(appLocalized: "Daily average"), statistics?.averageSteps.map(formatted), detail: String(appLocalized: "steps"))
                card(String(appLocalized: "Best day"), statistics?.bestDay.map { formatted($0.steps) }, detail: String(appLocalized: "steps"))
                card(String(appLocalized: "Wins"), record.map { "\($0.wins)" }, detail: record.map { String(format: String(appLocalized: "you.of-fights"), $0.played) }, tone: theme.mossText)
                card(String(appLocalized: "Win rate"), record?.winRate.map { $0.formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.locale)) }, detail: nil)
            }
            .padding(.horizontal, theme.space.screenPadding)
        }
        .padding(.horizontal, -theme.space.screenPadding)
    }

    private var todayDetail: String {
        guard let todaySteps, let average = statistics?.averageSteps else { return String(appLocalized: "steps") }
        let gap = Double(todaySteps) - average
        return String(format: String(appLocalized: "you.vs-average"), (gap >= 0 ? "+" : "-") + formatted(abs(gap)))
    }

    private func card(_ title: String, _ value: String?, detail: String?, tone: Color? = nil) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                Text(value ?? "-").font(.ff(30, 800)).monospacedDigit().foregroundStyle(tone ?? theme.text)
                    .minimumScaleFactor(0.6).lineLimit(1)
                if let detail {
                    Text(detail).ffType(.caption).foregroundStyle(theme.textSecondary).lineLimit(1)
                }
            }
        }
        .frame(width: 150)
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

/// Small week cards, newest first: total Steps and a bar per day, Monday to Sunday.
struct YouWeekCards: View {
    let days: [Date]
    let steps: [Double]
    @Environment(\.ffTheme) private var theme

    private var weeks: [[Int]] {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        var groups: [Date: [Int]] = [:]
        for (i, day) in days.enumerated() {
            let start = calendar.dateInterval(of: .weekOfYear, for: day)?.start ?? day
            groups[start, default: []].append(i)
        }
        return groups.sorted { $0.key > $1.key }.map(\.value)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            Text(String(appLocalized: "Weeks")).ffType(.heading).foregroundStyle(theme.text)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { offset, week in card(offset, week) }
                }
                .padding(.horizontal, theme.space.screenPadding)
            }
            .padding(.horizontal, -theme.space.screenPadding)
        }
    }

    private func card(_ offset: Int, _ week: [Int]) -> some View {
        let total = week.reduce(0) { $0 + steps[$1] }
        let peak = max(steps.max() ?? 0, 1)
        let label = offset == 0 ? String(appLocalized: "This week") : offset == 1 ? String(appLocalized: "Last week")
            : days[week[0]].formatted(.dateTime.day().month(.abbreviated).locale(AppLocalization.locale))
        return FFCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                Text(formatted(total)).font(.ff(26, 800)).monospacedDigit().foregroundStyle(theme.text)
                    .minimumScaleFactor(0.6).lineLimit(1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(week, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(i == days.count - 1 ? theme.mossFill : theme.gold)
                            .frame(width: 12, height: steps[i] > 0 ? max(3, 28 * steps[i] / peak) : 2)
                    }
                }
                .frame(height: 28, alignment: .bottom)
                .accessibilityHidden(true)
            }
        }
        .frame(width: 150)
        .accessibilityElement(children: .combine)
    }
}

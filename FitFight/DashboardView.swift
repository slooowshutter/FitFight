import Charts
import SwiftUI

/// Your numbers in more depth: Steps, Fights with full history, and every sport. No targets anywhere.
struct DashboardView: View {
    let sports: [YouActivityStore.Sport]
    let days: [Date]
    let statistics: ProfileStepStatistics?
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @StateObject private var history = ProfileScreenStore()
    @State private var tab = Tab.steps
    @State private var filter = Filter.all
    @State private var selectedDay: Int?

    enum Tab: CaseIterable { case steps, fights, sports }
    enum Filter: CaseIterable { case all, won, lost, drew }

    var body: some View {
        FFScreen {
            FFSegmented(items: Tab.allCases, selection: $tab) { item in
                switch item {
                case .steps: String(appLocalized: "Steps")
                case .fights: String(appLocalized: "Fights")
                case .sports: String(appLocalized: "Sports")
                }
            }
            switch tab {
            case .steps: stepsTab
            case .fights: fightsTab
            case .sports: sportsTab
            }
        }
        .navigationTitle(String(appLocalized: "Dashboard"))
        .task {
            guard let userID = session.authSession?.user.id ?? CompanionPreview.youID else { return }
            await history.load(userID: userID, session: session)
        }
    }

    private var steps: [Double] { sports.first?.values ?? [] }

    // MARK: Steps

    @ViewBuilder
    private var stepsTab: some View {
        if steps.count == 31 {
            let recent = steps.suffix(15).reduce(0, +) / 15
            let before = steps.dropLast(15).suffix(15).reduce(0, +) / 15
            FFCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(appLocalized: "Last 15 days vs the 15 before")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(formatted(recent)).font(.ff(34, 800)).monospacedDigit().foregroundStyle(theme.text)
                        if before > 0 {
                            let change = (recent - before) / before
                            Text(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(AppLocalization.locale)))
                                .font(.ff(17, 800)).foregroundStyle(change >= 0 ? theme.mossText : theme.emberText)
                        }
                    }
                    Text(String(format: String(appLocalized: "dashboard.before-average"), formatted(before)))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 10) {
                    let shown = selectedDay ?? 30
                    HStack {
                        Text(days[shown].formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLocalization.locale)))
                            .ffType(.label).foregroundStyle(theme.textSecondary)
                        Spacer()
                        Text(formatted(steps[shown])).font(.ff(22, 800)).monospacedDigit().foregroundStyle(theme.text)
                    }
                    Chart {
                        ForEach(steps.indices, id: \.self) { i in
                            BarMark(x: .value("Day", i), y: .value("Steps", steps[i]))
                                .foregroundStyle(i == shown ? theme.mossFill : theme.gold)
                                .cornerRadius(3)
                        }
                        RuleMark(y: .value("Average", steps.reduce(0, +) / 31))
                            .foregroundStyle(theme.textSecondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartXSelection(value: $selectedDay)
                    .frame(height: 140)
                    Text(String(appLocalized: "Drag across the bars. The dashed line is your average."))
                        .ffType(.micro).foregroundStyle(theme.textSecondary)
                }
            }
            weekdayCard
            FFSection(title: String(appLocalized: "Best days")) {
                FFGroupedRows {
                    ForEach(Array(steps.indices.sorted { steps[$0] > steps[$1] }.prefix(5).enumerated()), id: \.offset) { rank, i in
                        HStack {
                            Text("\(rank + 1)").ffType(.label).foregroundStyle(theme.textSecondary).frame(width: 24, alignment: .leading)
                            Text(days[i].formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLocalization.locale)))
                                .ffType(.rowTitle).foregroundStyle(theme.text)
                            Spacer()
                            Text(formatted(steps[i])).font(.ff(17, 800)).monospacedDigit().foregroundStyle(theme.text)
                        }
                        .padding(.horizontal, theme.space.cardPadding)
                        .padding(.vertical, 12)
                    }
                }
            }
        } else {
            Text(String(appLocalized: "Connect Apple Health to see your Steps here."))
                .ffType(.body).foregroundStyle(theme.textSecondary)
        }
    }

    private var weekdayCard: some View {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = AppLocalization.locale
        let averages = (0..<7).map { weekday in
            let values = days.indices.filter { (calendar.component(.weekday, from: days[$0]) + 5) % 7 == weekday }.map { steps[$0] }
            return values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        let best = averages.indices.max { averages[$0] < averages[$1] } ?? 0
        let names = calendar.veryShortStandaloneWeekdaySymbols
        return FFCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(appLocalized: "Average by weekday")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                Chart {
                    ForEach(0..<7, id: \.self) { weekday in
                        BarMark(x: .value("Weekday", names[(weekday + 1) % 7] + "\(weekday)"), y: .value("Steps", averages[weekday]))
                            .foregroundStyle(weekday == best ? theme.gold : theme.gold.opacity(0.45))
                            .cornerRadius(4)
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel { Text(String((value.as(String.self) ?? "").prefix(1))) }
                    }
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
                Text(String(format: String(appLocalized: "dashboard.best-weekday"), calendar.standaloneWeekdaySymbols[(best + 1) % 7], formatted(averages[best])))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
            }
        }
    }

    // MARK: Fights

    @ViewBuilder
    private var fightsTab: some View {
        let rows = history.history.filter(\.counted)
        let won = rows.filter { $0.result == "win" }.count
        let drew = rows.filter { $0.result == "draw" }.count
        FFCard {
            HStack {
                count(won, String(appLocalized: "Won"), theme.mossText)
                count(drew, String(appLocalized: "Drew"), theme.textSecondary)
                count(rows.count - won - drew, String(appLocalized: "Lost"), theme.emberText)
            }
        }
        Text(String(appLocalized: "Fight history")).ffType(.heading).foregroundStyle(theme.text).padding(.top, 8)
        FFSegmented(items: Filter.allCases, selection: $filter) { item in
            switch item {
            case .all: String(appLocalized: "All")
            case .won: String(appLocalized: "Won")
            case .lost: String(appLocalized: "Lost")
            case .drew: String(appLocalized: "Drew")
            }
        }
        let shown = history.history.filter { row in
            switch filter {
            case .all: true
            case .won: row.result == "win"
            case .drew: row.result == "draw"
            case .lost: row.counted && row.result != "win" && row.result != "draw"
            }
        }
        if history.loading && history.history.isEmpty { ProgressView().frame(maxWidth: .infinity) }
        if !history.loading && shown.isEmpty {
            Text(String(appLocalized: "No results yet")).ffType(.body).foregroundStyle(theme.textSecondary)
        }
        ForEach(shown) { row in
            if let fightID = row.fightId, model.fight(id: fightID.uuidString) != nil {
                Button { model.openFight(id: fightID.uuidString, preserveRound: true) } label: { FFCard { ProfileHistoryContent(row: row) } }
                    .buttonStyle(FFHapticPlainStyle())
            } else {
                FFCard { ProfileHistoryContent(row: row) }
            }
        }
        if history.nextCursor != nil, let userID = session.authSession?.user.id {
            FFButton(title: String(appLocalized: "Load more"), kind: .ghost, busy: history.loading) {
                Task { await history.loadMore(userID: userID, session: session) }
            }
        }
    }

    private func count(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.ff(44, 800)).monospacedDigit().foregroundStyle(color)
            Text(label).ffType(.caption).foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Sports

    @ViewBuilder
    private var sportsTab: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(appLocalized: "Last 31 days")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                ForEach(sports) { sport in
                    let peak = max(sport.values.max() ?? 0, 1)
                    HStack(spacing: 10) {
                        Image(systemName: sport.systemImage).frame(width: 20).foregroundStyle(theme.textSecondary)
                        Text(sport.name).ffType(.label).foregroundStyle(theme.text).frame(width: 56, alignment: .leading).lineLimit(1)
                        HStack(spacing: 2) {
                            ForEach(sport.values.indices, id: \.self) { i in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(sport.values[i] > 0 ? theme.gold.opacity(0.35 + 0.65 * sport.values[i] / peak) : theme.control)
                                    .frame(height: 24)
                            }
                        }
                        Text(sport.isSteps ? formatted(sport.values.reduce(0, +) / 1000) + "k" : formatted(sport.values.reduce(0, +)) + "m")
                            .font(.ff(15, 800)).monospacedDigit().foregroundStyle(theme.text).frame(width: 48, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        FFSection(title: String(appLocalized: "Active days")) {
            FFGroupedRows {
                ForEach(sports) { sport in
                    HStack {
                        Image(systemName: sport.systemImage).frame(width: 24).foregroundStyle(theme.textSecondary)
                        Text(sport.name).ffType(.rowTitle).foregroundStyle(theme.text)
                        Spacer()
                        Text(String(format: String(appLocalized: "dashboard.days-of"), sport.values.filter { $0 > 0 }.count, sport.values.count))
                            .font(.ff(17, 800)).monospacedDigit().foregroundStyle(theme.text)
                    }
                    .padding(.horizontal, theme.space.cardPadding)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale))
    }
}

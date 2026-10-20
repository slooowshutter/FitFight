import Charts
import SwiftUI

/// Your numbers in more depth: Steps, Fights with full history, and every sport. No targets anywhere.
struct DashboardView: View {
    let sports: [YouActivityStore.Sport]
    let days: [Date]
    /// Daily Steps for the past 8 weeks (56 days, today last), for the weekday averages.
    let eightWeekSteps: [Double]
    /// Won, lost and drew over every page of history, from You; this screen's list only loads one page.
    let results: (won: Int, lost: Int, drew: Int)?
    /// Wins and played from You's record, for a server from before draws and losses.
    let record: ProfileRecord?
    let rivals: [ProfileRivalrySummary]
    /// Reads Apple Health again, asking for access first if it was never asked, like the Health row on You.
    let connectHealth: () async -> Void
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @StateObject private var history = ProfileScreenStore()
    @State private var tab = Tab.fights
    @State private var filter = Filter.all
    @State private var selectedDay: Int?
    @State private var selectedWeekday: String?
    @State private var openSportID: String?
    @State private var connecting = false
    @State private var placeFight: Fight?
    @State private var friendSort = FriendSort.name
    @State private var showingFriendSort = false

    // Fights first: the record against people is what only FitFight knows.
    enum Tab: CaseIterable { case fights, steps, sports, admin }
    enum Filter: CaseIterable { case all, won, lost, drew }
    enum FriendSort: CaseIterable {
        case name, mostFights, oldestFriends, newestFriends

        var title: String {
            switch self {
            case .name: String(appLocalized: "A to Z")
            case .mostFights: String(appLocalized: "Most fights")
            case .oldestFriends: String(appLocalized: "Oldest friends")
            case .newestFriends: String(appLocalized: "Newest friends")
            }
        }
    }

    var body: some View {
        FFScreen {
            FFSegmented(items: Tab.allCases.filter { $0 != .admin || session.isFitFightAdmin }, selection: $tab) { item in
                switch item {
                case .fights: String(appLocalized: "Fights")
                case .steps: String(appLocalized: "Steps")
                case .sports: String(appLocalized: "Sports")
                case .admin: "Admin"
                }
            }
            switch tab {
            case .fights: fightsTab
            case .steps: stepsTab
            case .sports: sportsTab
            case .admin: AdminDashboardView()
            }
        }
        .navigationTitle(String(appLocalized: "Dashboard"))
        .navigationDestination(item: $openSportID) { id in
            if let sport = sports.first(where: { $0.id == id }) {
                DashboardChartPage(sport: sport)
            }
        }
        .task {
            guard let userID = session.authSession?.user.id ?? CompanionPreview.youID else { return }
            await history.load(userID: userID, session: session)
        }
    }

    private var steps: [Double] { sports.first?.values ?? [] }

    /// The 31 days that overlap a fight you took part in, from the first page of history.
    private var fightDays: Set<Int> {
        let windows = history.history
            .filter { !["cancelled", "not_entered", "unavailable", "removed", "withdrawn"].contains($0.result) }
            .compactMap { row in parseServerDate(row.startsAt).flatMap { start in parseServerDate(row.endsAt).map { (start, $0) } } }
        return Set(days.indices.filter { i in
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: days[i]) else { return false }
            return windows.contains { $0.0 < end && $0.1 > days[i] }
        })
    }

    // MARK: Steps

    @ViewBuilder
    private var stepsTab: some View {
        if steps.count == 31, steps.contains(where: { $0 > 0 }) {
            // Today is still going, so the halves, the dashed line and fight days use the 30 finished days.
            let recent = average(steps[15..<30])
            let before = average(steps[0..<15])
            let fightDays = self.fightDays
            let fought = fightDays.filter { $0 < 30 }
            FFCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(String(appLocalized: "Last 15 full days vs the 15 before")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(recent.map(formatted) ?? "-").font(.ff(34, 800)).monospacedDigit().foregroundStyle(theme.text)
                        if let recent, let before { change(recent, vs: before) }
                    }
                    if let before {
                        Text(String(format: String(appLocalized: "dashboard.before-average"), formatted(before)))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
            }
            FFCard {
                VStack(alignment: .leading, spacing: 10) {
                    let shown = min(max(selectedDay ?? 30, 0), 30)
                    HStack(spacing: 8) {
                        Text(shown == 30 ? String(appLocalized: "Today so far") : dayLabel(days[shown]))
                            .ffType(.label).foregroundStyle(theme.textSecondary)
                        if fightDays.contains(shown) {
                            FFPill(String(appLocalized: "Fight day"), style: .neutral)
                        }
                        Spacer()
                        Text(formatted(steps[shown])).font(.ff(22, 800)).monospacedDigit().foregroundStyle(theme.text)
                    }
                    Chart {
                        ForEach(steps.indices, id: \.self) { i in
                            BarMark(x: .value("Day", i), y: .value("Steps", steps[i]))
                                .foregroundStyle(i == shown ? theme.mossFill : fightDays.isEmpty || fightDays.contains(i) ? theme.gold : theme.gold.opacity(0.45))
                                .cornerRadius(3)
                                .accessibilityLabel(dayLabel(days[i]))
                                .accessibilityValue(formatted(steps[i]))
                        }
                        if let line = average(steps.dropLast()) {
                            dashboardAverageRule(line, label: formatted(line), theme: theme)
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartXSelection(value: $selectedDay)
                    .frame(height: 140)
                    HStack {
                        Text(days[0].formatted(.dateTime.day().month(.abbreviated).locale(AppLocalization.locale)))
                        Spacer()
                        Text(String(appLocalized: "Today"))
                    }
                    .ffType(.micro).foregroundStyle(theme.textFaint)
                    Text(fightDays.isEmpty
                         ? String(appLocalized: "Drag across the bars.")
                         : String(appLocalized: "Drag across the bars. Bright bars are fight days."))
                        .ffType(.micro).foregroundStyle(theme.textSecondary)
                    FFDivider(inset: 0)
                    Button { openSportID = sports.first?.id } label: {
                        HStack {
                            Text(String(appLocalized: "Weeks and months")).ffType(.label).foregroundStyle(theme.text)
                            Spacer()
                            FFChevron()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
            }
            if let onFights = average(fought.map { steps[$0] }),
               let otherwise = average((0..<30).filter { !fought.contains($0) }.map { steps[$0] }) {
                FFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(appLocalized: "Fight days vs other days")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(formatted(onFights)).font(.ff(34, 800)).monospacedDigit().foregroundStyle(theme.text)
                            change(onFights, vs: otherwise)
                        }
                        Text(String(format: String(appLocalized: "dashboard.fight-days-average"), formatted(otherwise)))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
            }
            weekdayCard
            FFSection(title: String(appLocalized: "Best days")) {
                FFGroupedRows {
                    ForEach(Array(steps.indices.sorted { steps[$0] > steps[$1] }.prefix(5).enumerated()), id: \.offset) { rank, i in
                        HStack {
                            Text("\(rank + 1)").ffType(.label).foregroundStyle(theme.textSecondary).frame(width: 24, alignment: .leading)
                            Text(dayLabel(days[i]))
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
            FFButton(title: String(appLocalized: "Connect Apple Health"), busy: connecting) {
                Task {
                    connecting = true
                    await connectHealth()
                    connecting = false
                }
            }
        }
    }

    private var weekdayCard: some View {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = AppLocalization.locale
        // The 55 finished days of the last 8 weeks, Monday first.
        let finished = Array(eightWeekSteps.dropLast())
        let today = days.last ?? Calendar.current.startOfDay(for: Date())
        var byWeekday = Array(repeating: [Double](), count: 7)
        for (i, value) in finished.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: i - finished.count, to: today) else { continue }
            byWeekday[(calendar.component(.weekday, from: date) + 5) % 7].append(value)
        }
        let averages = byWeekday.map { average($0) }
        let best = averages.indices.max { (averages[$0] ?? 0) < (averages[$1] ?? 0) } ?? 0
        // Two weekdays share a letter, so each bar's key adds its position.
        let keys = (0..<7).map { calendar.veryShortStandaloneWeekdaySymbols[($0 + 1) % 7] + "\($0)" }
        let shown = selectedWeekday.flatMap { keys.firstIndex(of: $0) } ?? best
        let name = { (weekday: Int) in calendar.standaloneWeekdaySymbols[(weekday + 1) % 7] }
        return Group {
            if averages.contains(where: { $0 != nil }) {
                FFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(appLocalized: "Average by weekday")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                        HStack {
                            Text(shown == best ? String(format: String(appLocalized: "dashboard.best-weekday-label"), name(shown)) : name(shown))
                                .ffType(.label).foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text(averages[shown].map(formatted) ?? "-").font(.ff(22, 800)).monospacedDigit().foregroundStyle(theme.text)
                        }
                        Chart {
                            ForEach(0..<7, id: \.self) { weekday in
                                BarMark(x: .value("Weekday", keys[weekday]), y: .value("Steps", averages[weekday] ?? 0))
                                    .foregroundStyle(weekday == shown ? theme.gold : theme.gold.opacity(0.45))
                                    .cornerRadius(4)
                                    .accessibilityLabel(name(weekday))
                                    .accessibilityValue(averages[weekday].map(formatted) ?? "-")
                            }
                        }
                        .chartXAxis {
                            AxisMarks { value in
                                AxisValueLabel { Text(String((value.as(String.self) ?? "").prefix(1))) }
                            }
                        }
                        .chartYAxis(.hidden)
                        .chartXSelection(value: $selectedWeekday)
                        .frame(height: 110)
                        Text(String(appLocalized: "Last 8 weeks, without today. Drag across the bars."))
                            .ffType(.micro).foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: Fights

    @ViewBuilder
    private var fightsTab: some View {
        // Without You's totals, count this screen's own history once every page is here.
        let totals = results ?? {
            guard history.profile != nil, history.nextCursor == nil else { return nil }
            let rows = history.history.filter(\.counted)
            let won = rows.filter { $0.result == "win" }.count
            let drew = rows.filter { $0.result == "draw" }.count
            return (won: won, lost: rows.count - won - drew, drew: drew)
        }()
        // A server from before draws sends only wins and played, so, as on You, every fight not won
        // counts as lost and draws stay unknown.
        ringCard(won: totals?.won ?? record?.wins, drew: totals?.drew, lost: totals?.lost ?? record.map { $0.played - $0.wins })
        yourPlaces
        if !rivals.isEmpty {
            VStack(alignment: .leading, spacing: theme.space.cardGap) {
                HStack(spacing: 8) {
                    FFSectionHeader(title: String(appLocalized: "Friends head to head"))
                    FFSortButton(title: friendSort.title) { showingFriendSort = true }
                }
                // By handle, then each order breaks ties by handle. People who are not friends go last on friendship age.
                ForEach(rivals.sorted { a, b in
                    let fights = { (r: ProfileRivalrySummary) in r.rivalry.wins + r.rivalry.losses + r.rivalry.draws }
                    let byHandle = a.identity.handle.localizedStandardCompare(b.identity.handle) == .orderedAscending
                    switch friendSort {
                    case .name: return byHandle
                    case .mostFights: return fights(a) != fights(b) ? fights(a) > fights(b) : byHandle
                    case .oldestFriends, .newestFriends:
                        switch (a.friendsSince, b.friendsSince) {
                        case let (x?, y?) where x != y: return friendSort == .oldestFriends ? x < y : x > y
                        case (nil, _?): return false
                        case (_?, nil): return true
                        default: return byHandle
                        }
                    }
                }) { rival in
                    rivalCard(rival)
                }
            }
            .padding(.top, theme.space.lg)
            .ffSortSheet(isPresented: $showingFriendSort, options: FriendSort.allCases, selection: $friendSort, title: \.title)
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

    /// Won, drew and lost as one ring around the win rate, with the three counts beside it.
    private func ringCard(won: Int?, drew: Int?, lost: Int?) -> some View {
        let parts = [(won ?? 0, theme.mossFill), (drew ?? 0, theme.textTertiary), (lost ?? 0, theme.emberFill)].filter { $0.0 > 0 }
        let played = parts.reduce(0) { $0 + $1.0 }
        // A 2pt gap between parts, as a share of the ring (radius 58).
        let gap = parts.count > 1 ? 2 / (2 * Double.pi * 58) : 0
        let ends = parts.indices.map { i in Double(parts[...i].reduce(0) { $0 + $1.0 }) / Double(max(played, 1)) }
        let row = { (label: String, value: Int?, dot: Color, ink: Color) in
            HStack(spacing: 10) {
                Circle().fill(dot).frame(width: 10, height: 10)
                Text(label).ffType(.label).foregroundStyle(theme.text)
                Spacer(minLength: 8)
                Text(value.map { "\($0)" } ?? "-").font(.ff(20, 800)).monospacedDigit().foregroundStyle(ink)
            }
            .accessibilityElement(children: .combine)
        }
        return FFCard {
            HStack(spacing: 22) {
                ZStack {
                    Circle().stroke(theme.track, lineWidth: 12)
                    ForEach(parts.indices, id: \.self) { i in
                        Circle()
                            .trim(from: (i == 0 ? 0 : ends[i - 1]) + gap / 2, to: ends[i] - gap / 2)
                            .stroke(parts[i].1, lineWidth: 12)
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 0) {
                        Text(played > 0 ? (Double(won ?? 0) / Double(played)).formatted(.percent.precision(.fractionLength(0)).locale(AppLocalization.locale)) : "-")
                            .font(.ff(32, 800)).monospacedDigit().foregroundStyle(theme.text)
                        Text(String(appLocalized: "dashboard.ring-won")).ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                .frame(width: 116, height: 116)
                .padding(6)
                VStack(alignment: .leading, spacing: 10) {
                    row(String(appLocalized: "Won"), won, theme.mossFill, theme.mossText)
                    row(String(appLocalized: "Drew"), drew, theme.textTertiary, theme.textSecondary)
                    row(String(appLocalized: "Lost"), lost, theme.emberFill, theme.emberText)
                    if played > 0 {
                        Text(String(format: String(appLocalized: "dashboard.out-of-fights"), played))
                            .ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                }
            }
        }
    }

    /// Your place in your last ten counted fights, newest first, the same squares and summary as a fight's History.
    @ViewBuilder
    private var yourPlaces: some View {
        // History arrives newest first. Like the Lost filter, a counted fight not won or drawn is lost.
        let counted = history.history.filter(\.counted)
        let outcomes = counted.map { $0.result == "win" ? Filter.won : $0.result == "draw" ? .drew : .lost }
        let places = counted.compactMap { row in row.placement.map { (row: row, rank: $0) } }
        if places.count >= 2 {
            let current = outcomes.prefix { $0 == outcomes[0] }.count
            let bestRun = outcomes.split { $0 != .won }.map(\.count).max() ?? 0
            // Ten squares need the screen's width, so they sit on the background as in History, not in a card.
            VStack(alignment: .leading, spacing: 8) {
                Text(places.count > 10 ? String(appLocalized: "Your place, last 10 fights") : String(appLocalized: "Your place each fight"))
                    .ffType(.eyebrow).foregroundStyle(theme.textTertiary)
                HStack(spacing: 6) {
                    ForEach(Array(places.prefix(10).enumerated()), id: \.offset) { _, place in
                        if let id = place.row.fightId, let fight = model.fight(id: id.uuidString) {
                            Button { placeFight = fight } label: { FFPlaceSquare(place.rank) }
                                .buttonStyle(FFHapticPlainStyle())
                                .accessibilityLabel(place.row.name ?? String(appLocalized: "Fight result"))
                                .accessibilityValue("\(place.rank)")
                        } else {
                            FFPlaceSquare(place.rank)
                                .accessibilityLabel(place.row.name ?? String(appLocalized: "Fight result"))
                                .accessibilityValue("\(place.rank)")
                        }
                    }
                }
                if current >= 2 {
                    let streak = outcomes[0] == .won ? String(appLocalized: "dashboard.streak-won")
                        : outcomes[0] == .lost ? String(appLocalized: "dashboard.streak-lost") : String(appLocalized: "dashboard.streak-drew")
                    Text(String(format: streak, current))
                        .ffType(.label).foregroundStyle(theme.text)
                }
                // Only every page of history knows the best run.
                if history.nextCursor == nil, bestRun >= 2, outcomes[0] != .won || bestRun > current {
                    Text(String(format: String(appLocalized: "dashboard.best-run"), bestRun))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
            }
            .sheet(item: $placeFight) { fight in
                RoundSummarySheet(round: fight) { placeFight = nil }
                    .fitFightTheme(theme)
                    .presentationBackground(theme.bg)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    /// A rival's companion, the score and who leads, then won, drew and lost as one bar. Opens their profile.
    private func rivalCard(_ rival: ProfileRivalrySummary) -> some View {
        let r = rival.rivalry
        let name = rival.identity.displayName
        let parts = [(r.wins, theme.mossFill), (r.draws, theme.textTertiary), (r.losses, theme.emberFill)].filter { $0.0 > 0 }
        let total = max(parts.reduce(0) { $0 + $1.0 }, 1)
        return ProfileIdentityLink(userID: rival.id, source: "friends") {
            FFCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        CompanionAvatar(personID: rival.id.uuidString, companionID: rival.identity.companionId,
                                        monogram: rival.identity.initials, photoURL: rival.identity.avatarUrl, size: 52)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: name).ffType(.rowTitle).foregroundStyle(theme.text).lineLimit(1)
                            HStack(spacing: 0) {
                                Text(r.wins > r.losses ? String(appLocalized: "You lead")
                                     : r.losses > r.wins ? String(format: String(appLocalized: "dashboard.rival-leads"), name) : String(appLocalized: "All square"))
                                    .foregroundStyle(r.wins > r.losses ? theme.mossText : r.losses > r.wins ? theme.emberText : theme.textSecondary)
                                if r.draws > 0 {
                                    Text(verbatim: " · " + (r.draws == 1 ? String(appLocalized: "dashboard.one-draw") : String(format: String(appLocalized: "dashboard.draws"), r.draws)))
                                        .foregroundStyle(theme.textSecondary)
                                }
                            }
                            .ffType(.caption).lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        HStack(spacing: 0) {
                            Text("\(r.wins)").foregroundStyle(theme.mossText)
                            Text(verbatim: " - ").foregroundStyle(theme.textTertiary)
                            Text("\(r.losses)").foregroundStyle(theme.emberText)
                        }
                        .font(.ff(24, 800)).monospacedDigit()
                    }
                    GeometryReader { geo in
                        let room = geo.size.width - CGFloat(parts.count - 1) * 3
                        HStack(spacing: 3) {
                            ForEach(parts.indices, id: \.self) { i in
                                Capsule().fill(parts[i].1).frame(width: max(6, room * CGFloat(parts[i].0) / CGFloat(total)))
                            }
                        }
                    }
                    .frame(height: 6)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityValue(String(format: String(appLocalized: "profile.rivalry-score"), r.wins, r.losses, r.draws))
            }
        }
    }

    // MARK: Sports

    @ViewBuilder
    private var sportsTab: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(String(appLocalized: "Last 31 days")).ffType(.eyebrow).foregroundStyle(theme.textSecondary)
                ForEach(sports) { sport in
                    let peak = max(sport.values.max() ?? 0, 1)
                    Button { openSportID = sport.id } label: {
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
                            Text(sport.isSteps ? formatted(sport.values.reduce(0, +) / 1000) + "k" : formatted(sport.values.reduce(0, +)) + " " + String(appLocalized: "min"))
                                .font(.ff(15, 800)).monospacedDigit().foregroundStyle(theme.text)
                                .lineLimit(1).minimumScaleFactor(0.7).frame(width: 64, alignment: .trailing)
                            FFChevron()
                        }
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                Text(String(appLocalized: "Tap a sport for its days, weeks and months."))
                    .ffType(.micro).foregroundStyle(theme.textSecondary)
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

    private func change(_ value: Double, vs base: Double) -> some View {
        let change = (value - base) / base
        return Text(change.formatted(.percent.precision(.fractionLength(0)).sign(strategy: .always()).locale(AppLocalization.locale)))
            .font(.ff(17, 800)).foregroundStyle(change >= 0 ? theme.mossText : theme.emberText)
    }

    private func dayLabel(_ day: Date) -> String {
        day.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLocalization.locale))
    }
}

/// One sport on its own page: a bar a day, week or month over a longer stretch, read with a finger.
private struct DashboardChartPage: View {
    let sport: YouActivityStore.Sport
    @Environment(\.ffTheme) private var theme
    @State private var bucket = Bucket.day
    /// A year of daily values, today last; nil until read, empty when Apple Health can't be read.
    @State private var daily: [Double]?
    @State private var bars: [Bar] = []
    /// The selected bar's position as text: category bars keep every bucket the same width.
    @State private var selected: String?

    enum Bucket: CaseIterable { case day, week, month }

    private struct Bar {
        let start: Date
        /// Steps a day for a week or month of Steps; minutes for a sport.
        let value: Double
        /// Every value the bar covers added up, for the total.
        let sum: Double
        let current: Bool
    }

    var body: some View {
        FFScreen {
            FFSegmented(items: Bucket.allCases, selection: $bucket, fill: true) { item in
                switch item {
                case .day: String(appLocalized: "Day")
                case .week: String(appLocalized: "Week")
                case .month: String(appLocalized: "Month")
                }
            }
            if !bars.isEmpty {
                let shown = min(max(selected.flatMap { Int($0) } ?? bars.count - 1, 0), bars.count - 1)
                let line = average(bars.filter { !$0.current }.map(\.value))
                let best = bars.indices.filter { !bars[$0].current }.max { bars[$0].value < bars[$1].value }
                FFCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(label(bars[shown])).ffType(.label).foregroundStyle(theme.textSecondary)
                            Spacer()
                            Text(value(bars[shown].value)).font(.ff(22, 800)).monospacedDigit().foregroundStyle(theme.text)
                        }
                        Chart {
                            ForEach(bars.indices, id: \.self) { i in
                                BarMark(x: .value("Period", "\(i)"), y: .value("Value", bars[i].value))
                                    .foregroundStyle(i == shown ? theme.mossFill : theme.gold)
                                    .cornerRadius(3)
                                    .accessibilityLabel(label(bars[i]))
                                    .accessibilityValue(value(bars[i].value))
                            }
                            if let line {
                                dashboardAverageRule(line, label: value(line), theme: theme)
                            }
                        }
                        .chartXAxis(.hidden)
                        .chartYAxis(.hidden)
                        .chartXSelection(value: $selected)
                        .frame(height: 220)
                        HStack {
                            Text(edge(bars[0], first: true))
                            Spacer()
                            Text(edge(bars[bars.count - 1], first: false))
                        }
                        .ffType(.micro).foregroundStyle(theme.textFaint)
                        Text(explanation).ffType(.micro).foregroundStyle(theme.textSecondary)
                    }
                }
                FFSection(title: String(appLocalized: "In numbers")) {
                    FFGroupedRows {
                        row(String(appLocalized: "dashboard.average", defaultValue: "Average"), line.map(value) ?? "-")
                        FFDivider()
                        row(String(appLocalized: "dashboard.best", defaultValue: "Best"), best.flatMap { bars[$0].value > 0 ? "\(label(bars[$0])) · \(value(bars[$0].value))" : nil } ?? "-")
                        FFDivider()
                        let total = bars.map(\.sum).reduce(0, +)
                        row(String(appLocalized: "dashboard.total", defaultValue: "Total"), sport.isSteps ? formatted(total) : minutes(total))
                    }
                }
            } else if daily?.isEmpty == true {
                Text(String(appLocalized: "Apple Health can't be read right now. Open FitFight again with your iPhone unlocked."))
                    .ffType(.body).foregroundStyle(theme.textSecondary)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 40)
            }
        }
        .navigationTitle(sport.name)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: bucket) {
            if daily == nil { daily = await YouActivityStore.history(for: sport, days: 366) ?? [] }
            bars = buckets(daily ?? [])
            selected = nil
        }
    }

    /// Day: the last 31 days. Week: the last 26 weeks. Month: the last 12 months. The oldest bucket a
    /// year of days only partly covers is dropped by the suffix.
    private func buckets(_ daily: [Double]) -> [Bar] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var groups: [(start: Date, values: [Double])] = []
        for (i, value) in daily.enumerated() {
            guard let date = calendar.date(byAdding: .day, value: i - daily.count + 1, to: today) else { continue }
            let start = bucket == .day ? date
                : calendar.dateInterval(of: bucket == .week ? .weekOfYear : .month, for: date)?.start ?? date
            if groups.last?.start == start {
                groups[groups.count - 1].values.append(value)
            } else {
                groups.append((start, [value]))
            }
        }
        let current = groups.last?.start
        return groups.suffix(bucket == .day ? 31 : bucket == .week ? 26 : 12).map { group in
            let sum = group.values.reduce(0, +)
            return Bar(start: group.start, value: sport.isSteps && bucket != .day ? average(group.values) ?? 0 : sum, sum: sum, current: group.start == current)
        }
    }

    private func label(_ bar: Bar) -> String {
        switch bucket {
        case .day:
            bar.current ? String(appLocalized: "Today so far")
                : bar.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(AppLocalization.locale))
        case .week:
            bar.current ? String(appLocalized: "This week so far")
                : String(format: String(appLocalized: "dashboard.week-of"), bar.start.formatted(.dateTime.day().month(.abbreviated).locale(AppLocalization.locale)))
        case .month:
            bar.current ? String(appLocalized: "This month so far")
                : bar.start.formatted(.dateTime.month(.wide).year().locale(AppLocalization.locale))
        }
    }

    /// The axis ends: the oldest bar's date, and now.
    private func edge(_ bar: Bar, first: Bool) -> String {
        switch bucket {
        case .day: first ? bar.start.formatted(.dateTime.day().month(.abbreviated).locale(AppLocalization.locale)) : String(appLocalized: "Today")
        case .week: first ? bar.start.formatted(.dateTime.day().month(.abbreviated).locale(AppLocalization.locale)) : String(appLocalized: "This week")
        case .month: first ? bar.start.formatted(.dateTime.month(.abbreviated).year().locale(AppLocalization.locale)) : String(appLocalized: "This month")
        }
    }

    private func value(_ value: Double) -> String {
        if !sport.isSteps { return minutes(value) }
        return bucket == .day ? formatted(value) : String(format: String(appLocalized: "dashboard.per-day"), formatted(value))
    }

    private func minutes(_ value: Double) -> String {
        formatted(value) + " " + String(appLocalized: "min")
    }

    private var explanation: String {
        switch (sport.isSteps, bucket) {
        case (true, .day): String(appLocalized: "One bar a day for the last 31 days. Drag across the bars.")
        case (true, .week): String(appLocalized: "One bar a week for the last 26 weeks: your Steps a day that week. Drag across the bars.")
        case (true, .month): String(appLocalized: "One bar a month for the last 12 months: your Steps a day that month. Drag across the bars.")
        case (false, .day): String(appLocalized: "Workout minutes a day for the last 31 days. Drag across the bars.")
        case (false, .week): String(appLocalized: "Workout minutes a week for the last 26 weeks. Drag across the bars.")
        case (false, .month): String(appLocalized: "Workout minutes a month for the last 12 months. Drag across the bars.")
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).ffType(.rowTitle).foregroundStyle(theme.text)
            Spacer()
            Text(value).font(.ff(17, 800)).monospacedDigit().foregroundStyle(theme.text).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, theme.space.cardPadding)
        .padding(.vertical, 12)
    }
}

/// The dashed average line, with its number in a small solid badge on the line's left end, readable over any bar.
private func dashboardAverageRule(_ value: Double, label: String, theme: Theme) -> some ChartContent {
    RuleMark(y: .value("Average", value))
        .foregroundStyle(theme.textSecondary)
        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
        .annotation(position: .overlay, alignment: .leading) {
            Text(String(format: String(appLocalized: "dashboard.average-line"), label))
                .ffType(.micro)
                .foregroundStyle(theme.text)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.control, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(theme.hairline, lineWidth: 1) }
        }
}

/// Days without Steps are missing data rather than rest, so averages skip zeros, as on You. A sport's
/// average likewise covers only the days, weeks or months with a workout.
private func average(_ values: some Sequence<Double>) -> Double? {
    let recorded = values.filter { $0 > 0 }
    return recorded.isEmpty ? nil : recorded.reduce(0, +) / Double(recorded.count)
}

private func formatted(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)).locale(AppLocalization.locale))
}

import SwiftUI

enum FightsListFilter: CaseIterable {
    case current, invited, past

    var title: String {
        switch self {
        case .current: String(appLocalized: "Current")
        case .invited: String(appLocalized: "fights.filter-invited", defaultValue: "Invited")
        case .past: String(appLocalized: "Past")
        }
    }
}

enum FightsSort: CaseIterable, Hashable {
    case recentlyStarted, endingSoonest, winningMost, winningLeast

    var title: String {
        switch self {
        case .recentlyStarted: String(appLocalized: "Recently started")
        case .endingSoonest: String(appLocalized: "Ending soonest")
        case .winningMost: String(appLocalized: "Winning most")
        case .winningLeast: String(appLocalized: "Winning least")
        }
    }
}

struct FightsListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @State private var filter: FightsListFilter
    @State private var sort: FightsSort = .endingSoonest
    @State private var showingSort = false

    init(filter: FightsListFilter = .current) {
        _filter = State(initialValue: filter)
    }

    var body: some View {
        FFScreen(refresh: fightsRefresh) {
            CompanionIntroduction(surface: .fights)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Challenges")
                        .font(.custom("Nunito-ExtraBold", size: 14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Spacer(minLength: 8)
                    Button { showingSort = true } label: {
                        Label(sort.title, systemImage: "arrow.up.arrow.down")
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityLabel(String(appLocalized: "Sort by"))
                    .accessibilityValue(sort.title)
                }
                FFSegmented(
                    items: FightsListFilter.allCases,
                    selection: $filter,
                    count: { item in
                        item == .invited ? model.invitations.count : nil
                    },
                    fill: true
                ) { item in
                    item.title
                }
            }

            if isEmpty, model.isRefreshingFights {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: theme.radius.card)
                        .fill(theme.skeleton)
                        .frame(height: 76)
                        .accessibilityLabel(String(appLocalized: "Loading"))
                }
            }

            if isEmpty, !model.isRefreshingFights {
                FFEmptyState(
                    systemImage: "trophy",
                    title: String(appLocalized: "No fights yet"),
                    message: String(appLocalized: "Start one under New. Add people with their username. They must have signed in once."),
                    actionTitle: String(appLocalized: "Start one"),
                    action: { model.tab = .newFight }
                )
            }

            if !isEmpty, selectedFights.isEmpty {
                Text(filter == .current ? String(appLocalized: "No current fights")
                     : filter == .invited ? String(appLocalized: "No invitations")
                     : String(appLocalized: "No past fights"))
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }

            if filter == .invited {
                ForEach(sorted(model.invitations)) { fight in
                    JoinOfferRow(
                        title: fight.listTitle,
                        subtitle: fight.listSubtitle,
                        avatar: AnyView(CompanionAvatar(fight.inviter ?? fight.standings.first?.person))
                    ) { model.openFightID = fight.id }
                }
                ForEach(model.suggestedFights.filter { !$0.alreadyMember }) { fight in
                    JoinOfferRow(suggested: fight) { Task { await model.openJoinable(fight, session: session) } }
                }
            }

            if filter == .current {
                ForEach(sorted(model.live)) { fight in
                    let standing = difference(in: fight)
                    LiveFightCard(
                        fight: fight,
                        metric: fight.isUpcoming ? String(appLocalized: "Scheduled") : standing.text,
                        metricColor: fight.isUpcoming || !standing.isGap ? theme.text
                            : standing.ahead ? theme.mossText : theme.emberText
                    ) { model.openFightID = fight.id }
                }
            }

            if filter == .past {
                ForEach(sorted(model.finished)) { fight in
                    FinishedRow(fight: fight)
                }
            }
        }
        .task(id: filter) {
            if filter == .invited { await model.loadFightDiscovery(session: session) }
        }
        .sheet(isPresented: $showingSort) {
            FightsSortSheet(sort: $sort)
                .fitFightTheme(theme)
                .presentationBackground(theme.overlay)
                .presentationCornerRadius(theme.radius.shell)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium])
        }
    }

    private var fightsRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: model.isRefreshingFights,
            message: model.refreshStatusText,
            action: {
                await model.refreshFights(session: session, steps: steps, trigger: .manual)
            }
        )
    }

    private var isEmpty: Bool {
        model.live.isEmpty && model.invitations.isEmpty && model.finished.isEmpty
    }

    private var selectedFights: [Fight] {
        switch filter {
        case .current: model.live
        case .invited: model.invitations
        case .past: model.finished
        }
    }

    // ponytail: Fight has no created_at on the client, so "Recently started" uses windowStart.
    private func sorted(_ fights: [Fight]) -> [Fight] {
        let now = Date()
        // Your steps minus the best rival's. Fights without a score yet sink to the bottom.
        func lead(_ fight: Fight) -> Double {
            guard !fight.isUpcoming,
                  let me = model.youStanding(in: fight), !me.deferred,
                  let best = fight.standings.filter({ !$0.person.isYou && !$0.invited && !$0.deferred }).map(\.score).max()
            else { return .nan }
            return me.score - best
        }
        return fights.sorted { lhs, rhs in
            switch sort {
            case .recentlyStarted:
                if lhs.windowStart != rhs.windowStart { return lhs.windowStart > rhs.windowStart }
            case .endingSoonest:
                // Closest end to now: the next deadline for live fights, the latest finish for past ones.
                let l = abs(lhs.windowEnd.timeIntervalSince(now)), r = abs(rhs.windowEnd.timeIntervalSince(now))
                if l != r { return l < r }
            case .winningMost, .winningLeast:
                let l = lead(lhs), r = lead(rhs)
                if l.isNaN != r.isNaN { return r.isNaN }
                if !l.isNaN, l != r { return sort == .winningMost ? l > r : l < r }
            }
            return lhs.id < rhs.id
        }
    }

    /// The number on the right is your distance from whoever you are actually
    /// racing: the leader when you are behind, the runner-up when you are ahead.
    /// Nobody else has a score yet in a fresh fight, so that row shows your total.
    private func difference(in fight: Fight) -> (text: String, ahead: Bool, isGap: Bool) {
        if model.youStanding(in: fight)?.deferred == true {
            return (String(appLocalized: "Next round"), true, false)
        }
        let rivals = fight.standings.filter { !$0.person.isYou && !$0.invited && !$0.deferred }.map(\.score)
        guard let mine = model.youStanding(in: fight)?.score else {
            guard let leader = rivals.max() else { return ("-", true, false) }
            return (stepCount(leader), true, false)
        }
        guard let best = rivals.max() else { return (stepCount(mine), true, false) }
        let gap = mine - best
        guard gap != 0 else { return (String(appLocalized: "Tied"), true, false) }
        return ("\(gap < 0 ? "−" : "+")\(stepCount(abs(gap)))", gap > 0, true)
    }

    /// Whole steps with the locale's grouping. A gap of 840 must not read "0.8k".
    private func stepCount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

/// A current fight: title and gap, avatars and place, a gold bar for how far through it is, then the day and time left.
struct LiveFightCard: View {
    let fight: Fight
    let metric: String
    let metricColor: Color
    let onOpen: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        let total = max(fight.windowEnd.timeIntervalSince(fight.windowStart), 1)
        let elapsed = min(max(Date().timeIntervalSince(fight.windowStart), 0), total)
        let day = min(Int(elapsed / 86_400) + 1, max(fight.lengthDays, 1))
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: fight.listTitle)
                        .ffType(.heading)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(metric)
                        .font(.ff(22, 800))
                        .tracking(22 * -0.02)
                        .foregroundStyle(metricColor)
                }
                HStack(spacing: 8) {
                    CompanionAvatarStack(
                        people: fight.standings.filter { !$0.invited }.map(\.person),
                        visible: 4,
                        size: 22,
                        ring: theme.card
                    )
                    if !fight.isUpcoming {
                        Text(String(appLocalized: "fight.rank-of", defaultValue: "\(AppModel.ordinal(fight.rank)) of \(fight.of)"))
                    }
                }
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                FFProgressBar(value: fight.isUpcoming ? 0 : elapsed / total, height: 5, fill: theme.gold)
                    .padding(.top, 2)
                HStack {
                    Text(fight.isUpcoming ? fight.durationLabel
                         : String(appLocalized: "fight.day-of", defaultValue: "Day \(day) of \(fight.lengthDays)"))
                    Spacer(minLength: 8)
                    Text(fight.timeLeftLabel)
                        .lineLimit(1)
                        .foregroundStyle(!fight.isUpcoming && fight.windowEnd.timeIntervalSinceNow < 2 * 86_400
                                         ? theme.emberText : theme.textSecondary)
                }
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 16)
            // The big gap number's line height pushes the title down; a shorter top keeps its visible inset at 16.
            .padding(.top, 6)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.hairline, radius: theme.radius.card)
        }
        .buttonStyle(FFPressStyle())
    }
}

/// An invitation or a suggested fight: moss wash, two lines, and a pill. The whole row opens it.
struct JoinOfferRow: View {
    let title: String
    let subtitle: String
    var pill = String(appLocalized: "Join")
    let avatar: AnyView
    let onOpen: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 13) {
                avatar
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .ffType(.heading)
                        .foregroundStyle(theme.text)
                    Text(verbatim: subtitle)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                FFPill(pill, style: .solidMoss)
                    .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(theme.mossWash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.mossText.opacity(0.18), radius: theme.radius.card)
            .contentShape(Rectangle())
        }
        .buttonStyle(FFPressStyle())
    }
}

extension JoinOfferRow {
    init(suggested fight: FitFightJoinableFight, onOpen: @escaping () -> Void) {
        self.init(
            title: Fight.displayTitle(name: fight.name, actionText: fight.actionText),
            subtitle: String(format: String(appLocalized: "suggested.participants"), fight.memberCount),
            pill: fight.hasJoined ? String(appLocalized: "Open fight") : String(appLocalized: "Join"),
            avatar: AnyView(FFAvatar(monogram: String(fight.ownerHandle.prefix(2)).uppercased())),
            onOpen: onOpen
        )
    }
}

struct FinishedRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button {
            model.openFightID = fight.id
        } label: {
            HStack(spacing: 13) {
                FFResultGlyph(result)
                VStack(alignment: .leading, spacing: 2) {
                    Text(fight.listTitle)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.text)
                    Text(result == .pending ? fight.listSubtitle : (fight.endedLabel ?? fight.listSubtitle))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 8)
                CompanionAvatarStack(
                    people: fight.standings.map(\.person),
                    visible: 2,
                    size: 26,
                    ring: theme.card
                )
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.hairline, radius: theme.radius.card)
        }
        .buttonStyle(FFPressStyle())
    }

    private var result: FFResult {
        model.fightResult(for: fight)
    }
}

private struct FightsSortSheet: View {
    @Binding var sort: FightsSort
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSheetHeader(title: String(appLocalized: "Sort by")) { dismiss() }
            FFGroupedRows {
                ForEach(FightsSort.allCases, id: \.self) { option in
                    if option != FightsSort.allCases.first { FFDivider() }
                    FFGroupedRow(title: option.title, trailing: AnyView(
                        Image(systemName: "checkmark")
                            .foregroundStyle(theme.mossText)
                            .opacity(sort == option ? 1 : 0)
                    )) {
                        sort = option
                        dismiss()
                    }
                    .accessibilityAddTraits(sort == option ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 16)
    }
}

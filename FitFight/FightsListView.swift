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

enum CurrentFightsSort: CaseIterable, Hashable {
    case endingSoonest, endingLatest, recentlyStarted

    var title: String {
        switch self {
        case .endingSoonest: String(appLocalized: "Ending soonest")
        case .endingLatest: String(appLocalized: "Ending latest")
        case .recentlyStarted: String(appLocalized: "Recently started")
        }
    }
}

struct FightsListView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var filter: FightsListFilter
    @State private var currentSort: CurrentFightsSort = .endingSoonest

    init(filter: FightsListFilter = .current) {
        _filter = State(initialValue: filter)
    }

    var body: some View {
        FFScreen(refresh: fightsRefresh) {
            CompanionIntroduction(surface: .fights)

            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 4))
            layout {
                Text("Challenges")
                    .font(.custom("Nunito-ExtraBold", size: 14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                FFSegmented(
                    items: FightsListFilter.allCases,
                    selection: $filter,
                    count: { item in
                        item == .invited ? model.invitations.count : nil
                    }
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
                ForEach(model.invitations) { fight in
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
                if !model.live.isEmpty {
                    HStack {
                        Text(String(appLocalized: "Sort by"))
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 8)
                        Menu {
                            Picker(String(appLocalized: "Sort by"), selection: $currentSort) {
                                ForEach(CurrentFightsSort.allCases, id: \.self) { option in
                                    Text(option.title).tag(option)
                                }
                            }
                        } label: {
                            Label(currentSort.title, systemImage: "arrow.up.arrow.down")
                                .ffType(.label)
                                .foregroundStyle(theme.mossText)
                                .frame(minHeight: 44)
                        }
                        .accessibilityLabel(String(appLocalized: "Sort by"))
                        .accessibilityValue(currentSort.title)
                    }
                }
                ForEach(sortedCurrentFights) { fight in
                    let standing = difference(in: fight)
                    let opponent = opponent(in: fight)
                    FFListRow(
                        monogram: opponent?.initials ?? "?",
                        title: fight.listTitle,
                        subtitle: fight.timeAndDeadlineLabel,
                        metric: fight.isUpcoming ? String(appLocalized: "Scheduled") : standing.text,
                        ahead: standing.ahead,
                        metricIsGap: !fight.isUpcoming && standing.isGap,
                        avatar: AnyView(CompanionAvatar(opponent)),
                        action: { model.openFightID = fight.id }
                    )
                }
            }

            if filter == .past {
                ForEach(model.finished) { fight in
                    FinishedRow(fight: fight)
                }
            }
        }
        .task(id: filter) {
            if filter == .invited { await model.loadFightDiscovery(session: session) }
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

    private var sortedCurrentFights: [Fight] {
        model.live.sorted { lhs, rhs in
            switch currentSort {
            case .endingSoonest:
                if lhs.windowEnd != rhs.windowEnd { return lhs.windowEnd < rhs.windowEnd }
            case .endingLatest:
                if lhs.windowEnd != rhs.windowEnd { return lhs.windowEnd > rhs.windowEnd }
            case .recentlyStarted:
                if lhs.windowStart != rhs.windowStart { return lhs.windowStart > rhs.windowStart }
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

    /// The other side of a head-to-head, so the avatar is who you are up against.
    private func opponent(in fight: Fight) -> Person? {
        fight.standings.first { !$0.person.isYou && !$0.invited && !$0.deferred }?.person
            ?? fight.standings.first?.person
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

import SwiftUI

enum FightsListFilter: CaseIterable {
    case current, invited, past

    var title: String {
        switch self {
        case .current: String(localized: "Current")
        case .invited: String(localized: "fights.filter-invited", defaultValue: "Invited")
        case .past: String(localized: "Past")
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
                        .accessibilityLabel(String(localized: "Loading"))
                }
            }

            if isEmpty, !model.isRefreshingFights {
                FFEmptyState(
                    systemImage: "trophy",
                    title: String(localized: "No fights yet"),
                    message: String(localized: "Start one under New. Add people with their username. They must have signed in once."),
                    actionTitle: String(localized: "Start one"),
                    action: { model.tab = .newFight }
                )
            }

            if !isEmpty, selectedFights.isEmpty {
                Text(filter == .current ? String(localized: "No current fights")
                     : filter == .invited ? String(localized: "No invitations")
                     : String(localized: "No past fights"))
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            }

            if filter == .invited {
                ForEach(model.invitations) { fight in
                    InvitationRow(fight: fight)
                }
                ForEach(model.suggestedFights.filter { !$0.alreadyMember }) { fight in
                    SuggestedFightOffer(fight: fight) { Task { await model.openJoinable(fight, session: session) } }
                }
            }

            if filter == .current {
                ForEach(model.live) { fight in
                    let standing = difference(in: fight)
                    let opponent = opponent(in: fight)
                    FFListRow(
                        monogram: opponent?.initials ?? "?",
                        title: fight.listTitle,
                        subtitle: fight.timeLeftLabel,
                        metric: fight.isUpcoming ? String(localized: "Scheduled") : standing.text,
                        ahead: standing.ahead,
                        metricIsGap: !fight.isUpcoming && standing.isGap,
                        photoURL: opponent?.photoURL,
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

    /// The number on the right is your distance from whoever you are actually
    /// racing: the leader when you are behind, the runner-up when you are ahead.
    /// Nobody else has a score yet in a fresh fight, so that row shows your total.
    private func difference(in fight: Fight) -> (text: String, ahead: Bool, isGap: Bool) {
        if model.youStanding(in: fight)?.deferred == true {
            return (String(localized: "Next round"), true, false)
        }
        let rivals = fight.standings.filter { !$0.person.isYou && !$0.invited && !$0.deferred }.map(\.score)
        guard let mine = model.youStanding(in: fight)?.score else {
            guard let leader = rivals.max() else { return ("-", true, false) }
            return (stepCount(leader), true, false)
        }
        guard let best = rivals.max() else { return (stepCount(mine), true, false) }
        let gap = mine - best
        guard gap != 0 else { return (String(localized: "Tied"), true, false) }
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

struct InvitationRow: View {
    let fight: Fight
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(spacing: 13) {
            let inviter = fight.inviter ?? fight.standings.first?.person
            CompanionAvatar(inviter)
            VStack(alignment: .leading, spacing: 2) {
                Text(fight.listTitle)
                    .ffType(.heading)
                    .foregroundStyle(theme.text)
                Text(fight.listSubtitle)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 8)
            Button {
                model.openFightID = fight.id
            } label: {
                FFPill(String(localized: "Join"), style: .solidMoss)
            }
            .buttonStyle(FFPressStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(theme.mossWash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.mossText.opacity(0.18), radius: theme.radius.card)
        .contentShape(Rectangle())
        .onTapGesture { model.openFightID = fight.id }
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

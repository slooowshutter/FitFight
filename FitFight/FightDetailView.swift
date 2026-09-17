import Combine
import SwiftUI
import UIKit

enum FightDetailPane: Hashable {
    case stats
    case history
    case feed
    case share

    var title: String {
        switch self {
        case .stats:
            return String(localized: "Stats")
        case .history:
            return String(localized: "History")
        case .feed:
            return String(localized: "Feed")
        case .share:
            return String(localized: "Share")
        }
    }
}

struct FightDetailView: View {
    private let initialFight: Fight
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme

    @State private var copiedCode = false
    @State private var copiedLink = false
    @State private var fightsRevision = 0
    @State private var pane: FightDetailPane = .stats
    @State private var showingEdit = false
    @StateObject private var fightFeed = FeedStore()
    @State private var isRefreshingFeed = false

    init(fight: Fight, pane: FightDetailPane = .stats) {
        initialFight = fight
        _pane = State(initialValue: pane)
    }

    private var fight: Fight {
        model.canonicalFight(for: initialFight.id) ?? initialFight
    }

    private var panes: [FightDetailPane] {
        var items: [FightDetailPane] = [.stats]
        if showsHistory {
            items.append(.history)
        }
        items.append(.feed)
        if fight.joinCode != nil { items.append(.share) }
        return items
    }

    private var showsHistory: Bool {
        fight.recurring && fight.seriesId != nil && !model.seriesHistory(for: fight).isEmpty
    }

    private var pendingJoin: Bool {
        (fight.status == .invited || fight.pendingJoin) && !model.joined.contains(fight.id)
    }

    private var canLeave: Bool {
        !pendingJoin
            && (fight.status == .live || fight.status == .pending)
            && fight.inviter?.isYou != true
            && (fight.recurring || fight.joinCode != nil)
    }

    private var youDeferred: Bool {
        you?.deferred == true
    }

    var body: some View {
        FFScreen(top: AnyView(nav), refresh: pendingJoin ? nil : fightsRefresh, pinSectionHeaders: true) {
            if pendingJoin {
                JoinFightPreview(
                    fight: fight,
                    joining: model.isJoiningFight,
                    onJoinNow: { Task { await join(start: "now") } },
                    onJoinNext: { Task { await join(start: "next") } },
                    onDismiss: {
                        Task {
                            await model.declineFight(id: fight.id)
                            if (model.createError ?? "").isEmpty {
                                model.openFightID = nil
                            }
                        }
                    }
                )
                .id(fightsRevision)
            } else {
                FFSegmented(items: panes, selection: $pane) { item in
                    item.title
                }
                .padding(.bottom, 4)

                switch pane {
                case .stats:
                    statsPane
                case .history:
                    historyPane
                case .feed:
                    if let fightID = UUID(uuidString: fight.id) {
                        FightPostsSection(fightID: fightID, fightFeed: fightFeed)
                    }
                case .share:
                    shareCard
                }
            }
        }
        .onReceive(model.$fights) { _ in
            fightsRevision += 1
        }
        .onChange(of: fight.id) { _, _ in
            pane = .stats
        }
        .onChange(of: showsHistory) { _, hasHistory in
            if pane == .history && !hasHistory {
                pane = .stats
            }
        }
        .sheet(isPresented: $showingEdit) {
            EditFightView(fight: fight)
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(steps)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var fightsRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: pane == .feed ? isRefreshingFeed : model.isRefreshingFights,
            message: pane == .feed ? String(localized: "Loading") : model.refreshStatusText,
            action: {
                if pane == .feed, let fightID = UUID(uuidString: fight.id) {
                    isRefreshingFeed = true
                    defer { isRefreshingFeed = false }
                    await fightFeed.load(session: session, fightID: fightID)
                } else {
                    await model.refreshFights(session: session, steps: steps, trigger: .manual)
                }
            }
        )
    }

    private var you: Standing? { model.youStanding(in: fight) }

    private var isPendingSettlement: Bool {
        fight.status == .pending && !youDeferred
    }

    @ViewBuilder
    private var statsPane: some View {
        Group {
            if youDeferred {
                deferredHero
            } else if fight.status == .pending {
                settlementHero
            } else {
                CompanionFightSummary(fight: fight)
            }
        }
        .id(fightsRevision)

        standingsSection
        daysSection

        if canLeave {
            FFButton(
                title: String(localized: "Leave fight"),
                kind: .ghost,
                fullWidth: true
            ) {
                Task {
                    await model.leaveFight(id: fight.id)
                }
            }
            .padding(.top, theme.space.lg)
            if let error = model.createError, !error.isEmpty {
                Text(error)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
                    .padding(.top, 10)
            }
        }
    }

    private var standingsSection: some View {
        FFSection(title: String(localized: "Standings")) {
            VStack(alignment: .leading, spacing: theme.space.cardGap) {
                if let meta = fight.standingsMeta {
                    Text(meta)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                standingsBands(for: fight, contextFight: fight)
                ForEach(fight.standings.filter { $0.invited || $0.deferred }) { row in
                    standingRow(index: 0, row: row, contextFight: fight)
                }
            }
            .id(fightsRevision)
        }
    }

    private var historyPane: some View {
        ForEach(model.seriesHistory(for: fight)) { window in
            historyWindowCard(window)
        }
    }

    @ViewBuilder
    private func standingsBands(for fight: Fight, contextFight: Fight) -> some View {
        let racing = fight.standings.filter { !$0.invited && !$0.deferred }
        let winners = winnerStandings(in: racing, fight: fight)
        let losers = racing.filter { row in !winners.contains(where: { $0.id == row.id }) }

        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            VStack(alignment: .leading, spacing: theme.space.cardGap) {
                ForEach(Array(winners.enumerated()), id: \.element.id) { index, row in
                    standingRow(index: index, row: row, contextFight: contextFight, inWinnerBand: true)
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
            .background(theme.mossWash, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
            .ffBorder(theme.mossEdge, radius: theme.radius.card)

            if !losers.isEmpty {
                standingsSeparator(for: fight)
                ForEach(Array(losers.enumerated()), id: \.element.id) { index, row in
                    standingRow(index: index + winners.count, row: row, contextFight: contextFight, inWinnerBand: false)
                }
            }
        }
    }

    private func standingsSeparator(for fight: Fight) -> some View {
        HStack(spacing: 10) {
            Text(standingsSeparatorLabel(for: fight))
                .ffType(.eyebrow)
                .foregroundStyle(theme.textTertiary)
            Rectangle()
                .fill(theme.track)
                .frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private func standingsSeparatorLabel(for fight: Fight) -> String {
        if fight.status == .live {
            return String(localized: "fight.standings-chasing", defaultValue: "Chasing the lead")
        }
        return String(localized: "fight.standings-everyone-else", defaultValue: "Everyone else")
    }

    private func winnerStandings(in racing: [Standing], fight: Fight) -> [Standing] {
        guard !racing.isEmpty else { return [] }
        if fight.status == .finished || fight.status == .pending {
            let leaders = racing.filter { $0.rank == 1 }
            if !leaders.isEmpty { return leaders }
        }
        let topScore = racing.map(\.score).max() ?? 0
        return racing.filter { $0.score == topScore }
    }

    @ViewBuilder
    private func historyWindowCard(_ window: Fight) -> some View {
        FFSection(title: historyWindowTitle(window)) {
            FFCard {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    HStack(alignment: .top, spacing: 12) {
                        FFResultGlyph(model.fightResult(for: window))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(historyWindowSubtitle(window))
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                            Text(historyWindowResult(window))
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                        }
                        Spacer(minLength: 0)
                    }
                    standingsBands(for: window, contextFight: window)
                }
            }
        }
    }

    private func historyWindowTitle(_ window: Fight) -> String {
        String(
            localized: "fight.history-window",
            defaultValue: "\(Fight.deadlineStamp(window.windowStart)) – \(Fight.deadlineStamp(window.windowEnd))"
        )
    }

    private func historyWindowSubtitle(_ window: Fight) -> String {
        window.endedLabel ?? window.deadlineLabel
    }

    private func historyWindowResult(_ window: Fight) -> String {
        let leaders = winnerStandings(
            in: window.standings.filter { !$0.invited && !$0.deferred },
            fight: window
        )
        if leaders.count > 1 {
            return String(localized: "Tied")
        }
        if let winner = leaders.first {
            return winner.person.isYou
                ? String(localized: "You won")
                : String(
                    localized: "fight.history-winner",
                    defaultValue: "\(winner.person.name) won"
                )
        }
        return String(localized: "No result yet")
    }

    @ViewBuilder
    private var daysSection: some View {
        FFSection(title: String(localized: "Every day so far")) {
            daysCard(initialKind: isPendingSettlement ? .pace : nil)
        }
    }

    private var nav: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 8) {
                Button { model.openFightID = nil } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FFHapticPlainStyle())
                .accessibilityLabel(String(localized: "Back"))
                VStack(alignment: .leading, spacing: 3) {
                    Text(fight.listTitle)
                        .font(.custom("Nunito-ExtraBold", size: 18, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if !pendingJoin, fight.hasAction, fight.actionText != fight.listTitle {
                        Text(fight.actionText)
                            .font(.custom("Nunito-Bold", size: 12, relativeTo: .caption))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                if session.isFitFightAdmin, !pendingJoin {
                    Button {
                        Task { await model.setFightSuggested(id: fight.id, suggested: !fight.suggested) }
                    } label: {
                        Text(fight.suggested ? String(localized: "Suggested") : String(localized: "Suggest"))
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                            .frame(height: 44)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                if fight.canOwnerEdit, !pendingJoin {
                    Button {
                        model.createError = nil
                        showingEdit = true
                    } label: {
                        Text(String(localized: "Edit"))
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                            .frame(height: 44)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 4)
        .background(theme.bg)
    }

    private var joinRoundNext: String {
        Fight.deadlineStamp(fight.windowEnd)
    }

    private func join(start: String) async {
        await model.acceptFight(id: fight.id, start: start)
        if (model.createError ?? "").isEmpty {
            model.joined.insert(fight.id)
        }
    }

    private var settlementHero: some View {
        FFCard(padding: 24) {
            VStack(alignment: .leading, spacing: 10) {
                FFResultGlyph(.pending)
                Text(fight.kickerEmphasis)
                    .ffType(.title)
                    .foregroundStyle(settlementTitleColor)
                Text(fight.endedLabel ?? fight.deadlineLabel)
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                if let grace = fight.graceEndsAt {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if grace > context.date {
                            Text(
                                String(
                                    localized: "fight.sync-time-left",
                                    defaultValue: "\(RemainingTime.phrase(from: context.date, until: grace)) left to sync"
                                )
                            )
                            .ffType(.caption)
                            .foregroundStyle(theme.goldInk)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var settlementTitleColor: Color {
        guard you?.finalStepsComplete == true else { return theme.emberText }
        let submitted = fight.standings.filter { !$0.invited && !$0.deferred && $0.finalStepsComplete == true }
        return submitted.first?.person.isYou == true ? theme.mossText : theme.emberText
    }

    private var deferredHero: some View {
        FFCard(padding: 24) {
            VStack(alignment: .leading, spacing: 8) {
                FFTag(String(localized: "Next round"))
                Text(String(localized: "You start next round"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Text(
                    String(
                        localized: "fight.deferred-copy",
                        defaultValue: "Your steps count from \(joinRoundNext). This round’s standings are still visible."
                    )
                )
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var shareCard: some View {
        FFCard(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if let code = fight.joinCode {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Fight code")
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Text("Anyone with the code or invite link can join.")
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = code
                            copiedCode = true
                        } label: {
                            Text(copiedCode ? String(localized: "Copied") : code)
                                .ffType(.heading)
                                .foregroundStyle(theme.mossText)
                                .frame(minHeight: 44)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .accessibilityLabel(String(localized: "Copy code"))
                        .accessibilityValue(code)
                    }
                }
                if let code = fight.joinCode {
                    let url = APIConfig.joinShareURL(code: code, referralCode: session.profile?.referralCode)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Link")
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                            Text(url.absoluteString)
                                .ffType(.caption)
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            UIPasteboard.general.string = url.absoluteString
                            copiedLink = true
                        } label: {
                            Text(copiedLink ? String(localized: "Copied") : String(localized: "Copy link"))
                                .ffType(.caption)
                                .foregroundStyle(theme.mossText)
                        }
                        .buttonStyle(FFHapticPlainStyle())
                    }
                    ShareLink(item: url) {
                        Label(String(localized: "Share fight"), systemImage: "square.and.arrow.up")
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                    }
                }
            }
        }
    }

    private func standingRow(
        index: Int,
        row: Standing,
        contextFight: Fight,
        inWinnerBand: Bool = false
    ) -> some View {
        Group {
            if row.invited || row.deferred {
                HStack(spacing: 13) {
                    Text("-")
                        .ffType(.button)
                        .foregroundStyle(theme.textFaint)
                        .frame(width: 22)
                    CompanionAvatar(row.person, size: 38, pending: true)
                    Text(row.person.name)
                        .ffType(.rowTitle)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    FFPill(
                        row.deferred ? String(localized: "Next round") : String(localized: "Invited"),
                        style: .gold
                    )
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .ffBorder(theme.hairline, radius: theme.radius.card)
            } else if contextFight.status == .pending {
                pendingStandingRow(
                    row,
                    contextFight: contextFight,
                    radius: inWinnerBand ? theme.radius.card - 4 : theme.radius.card
                )
            } else {
                FFLeaderboardRow(
                    rank: contextFight.status == .finished ? (row.rank ?? (index + 1)) : index + 1,
                    monogram: row.person.initials,
                    name: row.person.name,
                    value: model.formatScore(row.score, metric: contextFight.metric),
                    move: .same,
                    isYou: row.person.isYou,
                    photoURL: row.person.photoURL,
                    avatar: AnyView(CompanionAvatar(row.person, size: 38)),
                    captionUrgent: !inWinnerBand && row.person.isYou && contextFight.status == .live,
                    captionAt: { now in
                        model.formatStandingFreshness(row, fight: contextFight, now: now)
                    },
                    radius: inWinnerBand ? theme.radius.card - 4 : theme.radius.card
                )
            }
        }
    }

    private func pendingStandingRow(_ row: Standing, contextFight: Fight, radius: CGFloat) -> some View {
        let needsSync = row.finalStepsComplete != true
        let submitted = contextFight.standings.filter { !$0.invited && !$0.deferred && $0.finalStepsComplete == true }
        let rank = submitted.firstIndex { $0.id == row.id }.map { $0 + 1 }
        return HStack(spacing: 13) {
            Text(needsSync ? "-" : "\(rank ?? 0)")
                .ffType(.button)
                .foregroundStyle(needsSync ? theme.textFaint : (rank == 1 ? theme.gold : theme.textTertiary))
                .frame(width: 22)
            CompanionAvatar(row.person, size: 38, pending: needsSync)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.person.name)
                    .ffType(.rowTitle)
                    .foregroundStyle(needsSync ? theme.textSecondary : theme.text)
                    .lineLimit(1)
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(model.formatStandingFreshness(row, fight: contextFight, now: context.date))
                        .ffType(.micro)
                        .foregroundStyle(needsSync && row.person.isYou ? theme.emberText : theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FFPill(
                needsSync
                    ? String(localized: "fight.pending-sync", defaultValue: "Pending")
                    : String(localized: "Synced"),
                style: needsSync ? .gold : .neutral
            )
            Text(model.formatScore(row.score, metric: contextFight.metric))
                .font(.ff(17, 800))
                .tracking(17 * -0.02)
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
        .background(
            row.person.isYou ? theme.mossWash : theme.card,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
        .ffBorder(row.person.isYou ? theme.mossEdge : theme.hairline, radius: radius)
    }

    private func daysCard(initialKind: FightDayChartKind? = nil) -> some View {
        FFCard {
            VStack(alignment: .leading, spacing: 0) {
                FightDayChartsView(days: fight.days, standings: fight.standings, initialKind: initialKind) { value in
                    model.formatScore(value, metric: fight.metric)
                }
                if let note = fight.paceNote {
                    FFDivider(inset: 0)
                        .padding(.vertical, 18)
                    Text(note)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineSpacing(3)
                }
            }
        }
    }
}

/// Title, rules, and Join — used before someone is in the fight. Not the live Stats view.
struct JoinFightPreview: View {
    let fight: Fight
    var joining: Bool
    let onJoinNow: () -> Void
    let onJoinNext: () -> Void
    let onDismiss: () -> Void

    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard(padding: 20) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 8) {
                    Text(fight.listTitle)
                        .ffType(.title)
                        .foregroundStyle(theme.text)
                    if let pitch = fight.invitePitch {
                        Text(pitch)
                            .ffType(.body)
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 8) {
                    Text(
                        String(
                            localized: "fight.duration-rule",
                            defaultValue: "\(fight.durationLabel) · Most steps wins"
                        )
                    )
                    .ffType(.label)
                    .foregroundStyle(theme.text)
                    Text(fight.deadlineLabel)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                    if fight.hasAction, fight.actionText != fight.listTitle {
                        Text(fight.actionText)
                            .ffType(.body)
                            .foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Rectangle().fill(theme.line).frame(height: 1)

                VStack(alignment: .leading, spacing: 16) {
                    if fight.offersJoinNext {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                String(
                                    localized: "fight.join-now-copy",
                                    defaultValue: "This round started \(joinRoundStarted). Join now and your steps count from that date."
                                )
                            )
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                            FFScreenCTA(
                                title: joining ? String(localized: "Joining…") : String(localized: "Join this round"),
                                busy: joining,
                                action: onJoinNow
                            )
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            Text(
                                String(
                                    localized: "fight.join-next-copy",
                                    defaultValue: "Or start next round, from \(joinRoundNext)."
                                )
                            )
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                            FFButton(
                                title: String(localized: "Start next round"),
                                kind: .secondary,
                                enabled: !joining,
                                fullWidth: true,
                                action: onJoinNext
                            )
                        }
                    } else {
                        FFScreenCTA(
                            title: joining
                                ? String(localized: "Joining…")
                                : (fight.pendingJoin ? String(localized: "Join fight") : String(localized: "Accept challenge")),
                            busy: joining,
                            action: onJoinNow
                        )
                    }
                }
                FFButton(
                    title: fight.pendingJoin ? String(localized: "Not now") : String(localized: "Decline"),
                    kind: .ghost,
                    enabled: !joining,
                    fullWidth: true,
                    action: onDismiss
                )
                if let error = model.createError, !error.isEmpty {
                    Text(error)
                        .ffType(.caption)
                        .foregroundStyle(theme.emberText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var joinRoundStarted: String {
        Fight.deadlineStamp(fight.windowStart)
    }

    private var joinRoundNext: String {
        Fight.deadlineStamp(fight.windowEnd)
    }
}

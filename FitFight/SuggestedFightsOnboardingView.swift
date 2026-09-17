import SwiftUI

struct SuggestedFightsOnboardingView: View {
    var onFinished: (() -> Void)? = nil
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @State private var fights: [FitFightJoinableFight] = []
    @State private var loading = true
    @State private var joining: UUID?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: theme.space.cardGap) {
                Text(String(localized: "Suggested Fights")).ffType(.title)
                Text(String(localized: "Join a public Fight if you like. Nothing is joined automatically, and your profile settings stay yours."))
                    .ffType(.body).foregroundStyle(theme.textSecondary)
                if loading { ProgressView().frame(maxWidth: .infinity) }
                if let error {
                    FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    FFButton(title: String(localized: "Retry"), kind: .secondary) { Task { await load() } }
                }
                ForEach(fights) { fight in
                    SuggestedFightOffer(fight: fight, joining: joining == fight.id) { Task { await join(fight) } }
                        .disabled(joining != nil)
                }
                FFButton(title: String(localized: "Continue"), fullWidth: true) { finish() }
                FFButton(title: String(localized: "Skip"), kind: .ghost, fullWidth: true) { finish() }
            }.padding(theme.space.screenPadding)
        }.foregroundStyle(theme.text).background(theme.bg.ignoresSafeArea())
        .task { await load() }
        .onChange(of: session.authSession?.user.id) { _, _ in fights = []; finish() }
    }

    private func finish() {
        if let onFinished { onFinished() } else { session.finishSuggestedOnboarding() }
    }

    private func load() async {
        let accountID = session.authSession?.user.id
        loading = true
        defer { loading = false }
        do {
            let token = try await session.freshAccessToken()
            let loaded = try await FitFightAPI().listSuggestedFights(accessToken: token)
            try Task.checkCancellation()
            guard accountID == session.authSession?.user.id else { return }
            fights = loaded
            error = nil
            if fights.isEmpty { finish() }
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func join(_ fight: FitFightJoinableFight) async {
        guard joining == nil, !fight.hasJoined else { return }
        let accountID = session.authSession?.user.id
        joining = fight.id
        defer { joining = nil }
        do {
            let token = try await session.freshAccessToken()
            _ = try await FitFightAPI().joinFight(fightID: fight.fightId, accessToken: token)
            try Task.checkCancellation()
            guard accountID == session.authSession?.user.id else { return }
            await load()
        } catch is CancellationError {
        } catch {
            let message = error.localizedDescription
            await load()
            self.error = message
        }
    }
}

struct SuggestedFightOffer: View {
    let fight: FitFightJoinableFight
    var joining = false
    let onJoin: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: Fight.displayTitle(name: fight.name, actionText: fight.actionText)).ffType(.heading)
                Text(String(format: String(localized: "suggested.participants"), fight.memberCount))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                Text(String(localized: "Steps. Highest total wins." )).ffType(.body)
                if let start = FightRow.parse(fight.startsAt), let end = FightRow.parse(fight.endsAt) {
                    (Text(start, format: .dateTime.day().month().hour().minute()) + Text(verbatim: " → ") + Text(end, format: .dateTime.day().month().hour().minute()))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                if fight.recurring {
                    Text(String(localized: "Repeats until you leave. Each round has its own result."))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                if let action = fight.actionText, !action.isEmpty { Text(verbatim: action).ffType(.body) }
                Text(String(localized: "Participants see your identity, Fight Steps, standings, and posts you share in this Fight. Joining does not enable profile or daily-history sharing."))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                FFButton(
                    title: fight.hasJoined ? String(localized: "Joined") : String(localized: "Join"),
                    kind: fight.hasJoined ? .secondary : .primary,
                    enabled: !fight.hasJoined, busy: joining, fullWidth: true, action: onJoin
                )
            }
        }
    }
}

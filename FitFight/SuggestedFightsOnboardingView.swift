import SwiftUI

struct SuggestedFightsOnboardingView: View {
    var onFinished: (() -> Void)? = nil
    var onJoined: ((UUID, String) -> Void)? = nil
    var joinedFightID: UUID? = nil
    var joinedFightName: String? = nil
    @Binding var busy: Bool
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @State private var fights: [FitFightJoinableFight] = []
    @State private var loading = true
    @State private var joining: UUID?
    @State private var error: String?

    private var invitation: Fight? { model.pendingJoinable ?? model.invitations.first }
    private var offer: FitFightJoinableFight? { fights.first { !$0.hasJoined } }

    var body: some View {
        OnboardingPage {
            OnboardingHeading(title: invitation == nil
                ? String(appLocalized: "onboarding.fight.title", defaultValue: "Everything is better\nwith a little rivalry.")
                : String(appLocalized: "onboarding.invitation.title", defaultValue: "Your people.\nYour first rivalry."))
            HStack(spacing: 10) {
                CompanionAvatar(personID: session.profile?.userId.uuidString, isYou: true, size: 32)
                Text(verbatim: "@" + (session.profile?.handle ?? ""))
                    .font(.ff(14, 800)).foregroundStyle(theme.textSecondary)
            }
            if joinedFightID != nil {
                FFCard {
                    VStack(alignment: .leading, spacing: 12) {
                        if let joinedFightName { Text(verbatim: joinedFightName).ffType(.heading) }
                        Label(String(appLocalized: "Joined"), systemImage: "checkmark.circle")
                            .ffType(.body).foregroundStyle(theme.mossText)
                    }
                }
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 100)
            } else if let invitation {
                FFCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(verbatim: invitation.listTitle).ffType(.heading)
                        Text(String(appLocalized: "Steps. Highest total wins.")).ffType(.body)
                        Text(invitation.windowStart, format: .dateTime.day().month().hour().minute())
                            .ffType(.caption).foregroundStyle(theme.emberText)
                        if invitation.recurring {
                            Text(String(appLocalized: "Repeats until you leave. Each round has its own result."))
                                .ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                        if invitation.hasAction { Text(verbatim: invitation.actionText).ffType(.body) }
                    }
                }
                .modifier(OnboardingEntrance(order: 2))
            } else if let offer {
                SuggestedFightOffer(fight: offer).modifier(OnboardingEntrance(order: 2))
            } else if error == nil {
                Text(String(appLocalized: "No Fights to join right now. Find one later in Fights."))
                    .ffType(.body).foregroundStyle(theme.textSecondary)
            }
            if let error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                FFButton(title: String(appLocalized: "Retry"), kind: .secondary) { Task { await load() } }
                    .disabled(busy)
            }
            Text(String(appLocalized: "Participants see your identity, Fight Steps, standings, and posts you share in this Fight. Joining does not enable profile or daily-history sharing."))
                .ffType(.caption).foregroundStyle(theme.textSecondary)
        } actions: {
            if joinedFightID != nil {
                FFScreenCTA(title: String(appLocalized: "Continue"), enabled: !busy) { finish() }
            } else if invitation != nil || offer != nil || busy {
                // Keep the action mounted while an accepted membership refreshes the offers.
                FFScreenCTA(title: String(appLocalized: "Join this Fight"), enabled: !busy && !loading, busy: busy) {
                    Task {
                        if let invitation { await accept(invitation) }
                        else if let offer { await join(offer) }
                    }
                }
            }
            OnboardingSkip(title: String(appLocalized: "Explore first")) { finish() }
                .disabled(busy)
        }
        .foregroundStyle(theme.text)
        .task {
            await model.consumePendingLinks(session: session)
            await load()
        }
    }

    private func accept(_ fight: Fight) async {
        guard !busy, !model.isJoiningFight, let id = UUID(uuidString: fight.id) else { return }
        let accountID = session.authSession?.user.id
        busy = true
        error = nil
        defer { busy = false }
        await model.acceptFight(id: fight.id)
        guard !Task.isCancelled, accountID == session.authSession?.user.id else { return }
        if let failure = model.createError { error = failure; return }
        onJoined?(id, fight.listTitle)
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
        } catch is CancellationError {
        } catch { self.error = error.localizedDescription }
    }

    private func join(_ fight: FitFightJoinableFight) async {
        guard joining == nil, !fight.hasJoined else { return }
        let accountID = session.authSession?.user.id
        joining = fight.id
        busy = true
        error = nil
        defer { joining = nil; busy = false }
        do {
            let token = try await session.freshAccessToken()
            _ = try await FitFightAPI().joinFight(fightID: fight.fightId, accessToken: token)
            try Task.checkCancellation()
            guard accountID == session.authSession?.user.id else { return }
            await model.syncStepsAfterMembershipChange(session: session)
            try Task.checkCancellation()
            guard accountID == session.authSession?.user.id else { return }
            await load()
            guard !Task.isCancelled, accountID == session.authSession?.user.id else { return }
            onJoined?(fight.fightId, Fight.displayTitle(name: fight.name, actionText: fight.actionText))
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
    @Environment(\.ffTheme) private var theme

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(verbatim: Fight.displayTitle(name: fight.name, actionText: fight.actionText)).ffType(.heading)
                Text(String(format: String(appLocalized: "suggested.participants"), fight.memberCount))
                    .ffType(.caption).foregroundStyle(theme.textSecondary)
                Text(String(appLocalized: "Steps. Highest total wins.")).ffType(.body)
                if let start = FightRow.parse(fight.startsAt), let end = FightRow.parse(fight.endsAt) {
                    (Text(start, format: .dateTime.day().month().hour().minute()) + Text(verbatim: " → ") + Text(end, format: .dateTime.day().month().hour().minute()))
                        .ffType(.caption).foregroundStyle(theme.emberText)
                }
                if fight.recurring {
                    Text(String(appLocalized: "Repeats until you leave. Each round has its own result."))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
                if let action = fight.actionText, !action.isEmpty { Text(verbatim: action).ffType(.body) }
            }
        }
    }
}

import SwiftUI

/// Everyone's Friends group: incoming requests, this month's 1v1 with each friend, last month's
/// results, then ways to add friends. Its rounds come from their own snapshot, never the Fights list.
struct FriendsGroupView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var requests: [SharedProfileIdentity] = []
    @State private var suggestions: [SharedProfileIdentity] = []
    /// People asked from this screen, by the friendship the server returned, so their button stops saying Add.
    @State private var asked: [UUID: String] = [:]
    @State private var busy: Set<UUID> = []
    @State private var handle = ""
    @State private var found: SharedProfileIdentity?
    @State private var generation = 0
    @State private var lookupGeneration = 0
    @State private var loading = false
    @State private var failure: String?
    @State private var actionError: String?

    var body: some View {
        let now = Date()
        let thisMonth = onePerFriend(model.friendRounds.filter { $0.windowEnd > now })
        let lastMonth = onePerFriend(model.friendRounds.filter { $0.windowEnd <= now })
        FFScreen(top: AnyView(nav), refresh: FFRefreshConfig(
            isRefreshing: model.isRefreshingFights || loading,
            message: model.isRefreshingFights ? model.refreshStatusText : String(appLocalized: "Loading"),
            error: failure,
            action: {
                // Your Apple Health sync scores your side of every round, and the refresh reloads
                // friend rounds while this screen is open.
                await model.refreshFights(session: session, steps: steps, trigger: .manual)
                await load(rounds: false)
            }
        )) {
            if let actionError {
                FFNotice(text: actionError, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if !requests.isEmpty {
                FFSection(title: String(appLocalized: "Requests"), extraTop: false) {
                    ForEach(requests) { person in
                        personRow(person, source: "friends") {
                            FFButton(title: String(appLocalized: "Accept"), size: .small, busy: busy.contains(person.userId)) {
                                Task { await act("accept", on: person) }
                            }
                            .accessibilityLabel(String(appLocalized: "friends.accept", defaultValue: "Accept \(person.displayName)"))
                            FFButton(title: String(appLocalized: "Decline"), kind: .secondary, size: .small,
                                     enabled: !busy.contains(person.userId)) {
                                Task { await act("decline", on: person) }
                            }
                            .accessibilityLabel(String(appLocalized: "friends.decline", defaultValue: "Decline \(person.displayName)"))
                        }
                    }
                }
            }
            if !thisMonth.isEmpty {
                FFSection(title: String(appLocalized: "This month"), extraTop: !requests.isEmpty) {
                    ForEach(thisMonth) { fight in
                        LiveFightCard(fight: fight) { model.openFightID = fight.id }
                    }
                }
            }
            // Where the monthly results push lands: each result, or Pending while final steps come in.
            if !lastMonth.isEmpty {
                FFSection(title: String(appLocalized: "Last month"), extraTop: !requests.isEmpty || !thisMonth.isEmpty) {
                    ForEach(lastMonth) { fight in
                        FinishedRow(fight: fight)
                    }
                }
            }
            FFSection(
                title: String(appLocalized: "Add friends"),
                extraTop: !requests.isEmpty || !thisMonth.isEmpty || !lastMonth.isEmpty
            ) {
                FriendLookupField(handle: $handle) { Task { await lookup() } }
                if let found { addRow(found, source: "lookup") }
                if !suggestions.isEmpty {
                    Text(String(appLocalized: "People you’ve fought with"))
                        .ffType(.label)
                        .foregroundStyle(theme.textSecondary)
                        .padding(.top, theme.space.sm)
                    ForEach(suggestions) { addRow($0, source: "friends") }
                }
            }
        }
        .task { await load() }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var nav: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { model.showingFriends = false } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(FFHapticPlainStyle())
            .accessibilityLabel(String(appLocalized: "Back"))
            VStack(alignment: .leading, spacing: 3) {
                Text(String(appLocalized: "Friends"))
                    .font(.custom("Nunito-ExtraBold", size: 18, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                if let friends = model.friends {
                    Text(friends.summary)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 4)
        .background(theme.bg)
    }

    /// The latest round with each friend, ordered by the friend's name, which is the round's title.
    private func onePerFriend(_ rounds: [Fight]) -> [Fight] {
        var latest: [String: Fight] = [:]
        for fight in rounds {
            let friend = fight.standings.first { !$0.person.isYou }?.person.id ?? fight.id
            if let kept = latest[friend], kept.windowStart >= fight.windowStart { continue }
            latest[friend] = fight
        }
        return latest.values.sorted { ($0.listTitle, $0.id) < ($1.listTitle, $1.id) }
    }

    private func addRow(_ person: SharedProfileIdentity, source: String) -> some View {
        personRow(person, source: source) {
            switch asked[person.userId] {
            case "friends"?:
                FFButton(title: String(appLocalized: "Friends"), kind: .secondary, size: .small, enabled: false) {}
            case "outgoing"?:
                FFButton(title: String(appLocalized: "Requested"), kind: .secondary, size: .small, enabled: false) {}
            default:
                FFButton(title: String(appLocalized: "Add"), size: .small, busy: busy.contains(person.userId)) {
                    Task { await act("request", on: person) }
                }
            }
        }
    }

    /// At accessibility text sizes the buttons move under the name, so neither gets squeezed.
    private func personRow<Actions: View>(
        _ person: SharedProfileIdentity, source: String, @ViewBuilder actions: () -> Actions
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 10))
        return FFCard {
            layout {
                // The profile can change the friendship too, so closing it reloads.
                ProfileIdentityLink(userID: person.userId, source: source, onClosed: { Task { await load() } }) {
                    HStack(spacing: 12) {
                        CompanionAvatar(
                            personID: person.userId.uuidString, companionID: person.companionId, isYou: false,
                            monogram: person.initials, photoURL: person.avatarUrl, size: 44
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: person.displayName).ffType(.label).foregroundStyle(theme.text)
                            Text(verbatim: "@\(person.handle)").ffType(.caption).foregroundStyle(theme.textSecondary)
                        }
                        .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                }
                HStack(spacing: 8) { actions() }
            }
        }
    }

    /// `rounds: false` when a refresh that already reloaded friend rounds just ran.
    private func load(rounds: Bool = true) async {
        generation += 1
        let requestGeneration = generation
        let accountID = session.authSession?.user.id
        loading = true
        defer { if requestGeneration == generation { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            if rounds { try await model.refreshFriendRounds() }
            let incoming = try await FitFightAPI().profileFriends(kind: "incoming", accessToken: token)
            // Suggestions are optional: the rest of the screen works without them.
            let suggested = try? await FitFightAPI().friendSuggestions(accessToken: token)
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            requests = incoming.people
            suggestions = suggested?.people ?? []
            failure = nil
        } catch {
            guard requestGeneration == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            failure = error.localizedDescription
        }
    }

    /// `accept` and `decline` answer a request, `request` asks someone. Accepting starts this month's fight.
    private func act(_ action: String, on person: SharedProfileIdentity) async {
        guard !busy.contains(person.userId) else { return }
        busy.insert(person.userId)
        defer { busy.remove(person.userId) }
        actionError = nil
        do {
            let token = try await session.freshAccessToken()
            let result = try await FitFightAPI().changeFriendship(userID: person.userId, action: action, accessToken: token)
            if action == "request", result.friendship != "incoming" {
                asked[person.userId] = result.friendship
            } else {
                await load()
            }
        } catch is CancellationError {
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func lookup() async {
        lookupGeneration += 1
        let requestGeneration = lookupGeneration
        let accountID = session.authSession?.user.id
        found = nil
        actionError = nil
        do {
            let token = try await session.freshAccessToken()
            let person = try await FitFightAPI().lookupProfile(handle: handle, accessToken: token)
            guard requestGeneration == lookupGeneration, accountID == session.authSession?.user.id else { return }
            found = person
        } catch is CancellationError {
        } catch {
            guard requestGeneration == lookupGeneration, accountID == session.authSession?.user.id else { return }
            actionError = error.localizedDescription
        }
    }
}

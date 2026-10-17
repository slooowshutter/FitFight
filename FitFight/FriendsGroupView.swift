import SwiftUI

/// Everyone's Friends group: incoming requests, then the current 1v1 with each friend. Add friends
/// opens a sheet, and ended rounds live in each fight's History. Its rounds come from their own
/// snapshot, never the Fights list.
struct FriendsGroupView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @Environment(\.ffTheme) private var theme
    @State private var requests: [SharedProfileIdentity] = []
    @State private var busy: Set<UUID> = []
    @State private var generation = 0
    /// Starts true so the empty state never flashes before the first load.
    @State private var loading = true
    @State private var failure: String?
    @State private var actionError: String?
    @State private var adding = false

    var body: some View {
        let current = onePerFriend(model.friendRounds.filter { $0.windowEnd > Date() })
        // With nobody yet, one big button replaces the one in the header.
        let empty = current.isEmpty && requests.isEmpty && !loading
        FFScreen(top: AnyView(nav(showsAdd: !empty)), refresh: FFRefreshConfig(
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
                        FriendPersonRow(person: person, source: "friends", onClosed: { Task { await load() } }) {
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
                if !current.isEmpty {
                    FFSectionHeader(title: String(appLocalized: "Current"))
                        .padding(.top, theme.space.lg)
                }
            }
            ForEach(current) { fight in
                LiveFightCard(fight: fight) { model.openFightID = fight.id }
            }
            if empty {
                FFButton(title: String(appLocalized: "Add friends"), size: .large, fullWidth: true) { adding = true }
            }
        }
        .sheet(isPresented: $adding, onDismiss: { Task { await load() } }) {
            AddFriendsSheet()
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
        .task { await load() }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func nav(showsAdd: Bool) -> some View {
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
            if showsAdd {
                Button { adding = true } label: {
                    Label(String(appLocalized: "Add friends"), systemImage: "person.badge.plus")
                        .ffType(.buttonSmall)
                        .foregroundStyle(theme.mossOn)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 8)
                        .background(theme.mossFill, in: Capsule())
                }
                .buttonStyle(FFPressStyle())
                .frame(minHeight: 44)
            }
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
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            requests = incoming.people
            failure = nil
        } catch {
            guard requestGeneration == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            failure = error.localizedDescription
        }
    }

    /// `accept` or `decline` a request. Accepting starts a fight with that friend.
    private func act(_ action: String, on person: SharedProfileIdentity) async {
        guard !busy.contains(person.userId) else { return }
        busy.insert(person.userId)
        defer { busy.remove(person.userId) }
        actionError = nil
        do {
            let token = try await session.freshAccessToken()
            _ = try await FitFightAPI().changeFriendship(userID: person.userId, action: action, accessToken: token)
            await load()
        } catch is CancellationError {
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// Username search, then the people you fought with, each with Add. Closing it reloads the Friends group.
private struct AddFriendsSheet: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var suggestions: [SharedProfileIdentity] = []
    /// People asked from this sheet, by the friendship the server returned, so their button stops saying Add.
    @State private var asked: [UUID: String] = [:]
    @State private var busy: Set<UUID> = []
    @State private var handle = ""
    @State private var found: SharedProfileIdentity?
    @State private var lookupGeneration = 0
    @State private var actionError: String?

    var body: some View {
        VStack(spacing: 0) {
            FFSheetHeader(title: String(appLocalized: "Add friends")) { dismiss() }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    if let actionError {
                        FFNotice(text: actionError, tone: .ember, systemImage: "exclamationmark.triangle")
                    }
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
                .padding(theme.space.screenPadding)
                .ffKeyboardDismissOnBackgroundTap()
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(theme.text)
        .background(theme.bg.ignoresSafeArea())
        .task { await loadSuggestions() }
    }

    private func addRow(_ person: SharedProfileIdentity, source: String) -> some View {
        FriendPersonRow(person: person, source: source, onClosed: { Task { await loadSuggestions() } }) {
            switch asked[person.userId] {
            case "friends"?:
                FFButton(title: String(appLocalized: "Friends"), kind: .secondary, size: .small, enabled: false) {}
            case "outgoing"?:
                FFButton(title: String(appLocalized: "Requested"), kind: .secondary, size: .small, enabled: false) {}
            default:
                FFButton(title: String(appLocalized: "Add"), size: .small, busy: busy.contains(person.userId)) {
                    Task { await request(person) }
                }
            }
        }
    }

    /// Suggestions are optional: the search works without them.
    private func loadSuggestions() async {
        let accountID = session.authSession?.user.id
        guard let token = try? await session.freshAccessToken(),
              let suggested = try? await FitFightAPI().friendSuggestions(accessToken: token),
              accountID == session.authSession?.user.id
        else { return }
        suggestions = suggested.people
    }

    private func request(_ person: SharedProfileIdentity) async {
        guard !busy.contains(person.userId) else { return }
        busy.insert(person.userId)
        defer { busy.remove(person.userId) }
        actionError = nil
        do {
            let token = try await session.freshAccessToken()
            let result = try await FitFightAPI().changeFriendship(userID: person.userId, action: "request", accessToken: token)
            if result.friendship == "incoming" {
                // They had already asked you: closing shows them under Requests, ready to accept.
                dismiss()
            } else {
                asked[person.userId] = result.friendship
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

/// A person with their buttons. At accessibility text sizes the buttons move under the name, so
/// neither gets squeezed.
private struct FriendPersonRow<Actions: View>: View {
    let person: SharedProfileIdentity
    let source: String
    /// The profile can change the friendship too, so closing it reloads.
    let onClosed: () -> Void
    @ViewBuilder var actions: Actions
    @Environment(\.ffTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 10))
        FFCard {
            layout {
                ProfileIdentityLink(userID: person.userId, source: source, onClosed: onClosed) {
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
                HStack(spacing: 8) { actions }
            }
        }
    }
}

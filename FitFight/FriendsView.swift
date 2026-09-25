import SwiftUI

struct FriendsView: View {
    /// Embedded on You: no sheet header and no inner scroll, the page scrolls instead.
    var embedded = false
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var kind = "accepted"
    @State private var people: [SharedProfileIdentity] = []
    @State private var nextCursor: UUID?
    @State private var incomingCount = 0
    @State private var handle = ""
    @State private var found: SharedProfileIdentity?
    @State private var loading = false
    @State private var error: String?
    @State private var generation = 0
    @State private var lookupGeneration = 0
    @FocusState private var handleFocused: Bool

    var body: some View {
        Group {
            if embedded {
                list
            } else {
                VStack(spacing: 0) {
                    FFSheetHeader(title: String(appLocalized: "Friends"), role: .heading) { dismiss() }
                        .padding(.horizontal, theme.space.screenPadding).padding(.top, 12)
                    ScrollView {
                        list
                            .padding(theme.space.screenPadding)
                            .ffKeyboardDismissOnBackgroundTap()
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
                .foregroundStyle(theme.text)
                .ffKeyboardDismissOnBackgroundTap()
                .background(theme.bg.ignoresSafeArea())
            }
        }
        .task(id: kind) { await load() }
        .onChange(of: scenePhase) { _, phase in
            generation += 1; lookupGeneration += 1; people = []; found = nil; nextCursor = nil
            if phase == .active { Task { await load() } }
        }
        .onChange(of: session.authSession?.user.id) { _, _ in generation += 1; lookupGeneration += 1; people = []; found = nil; dismiss() }
        .onDisappear { generation += 1; lookupGeneration += 1; people = []; found = nil; nextCursor = nil }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            // Title on the left and the tabs on the right, like By sport.
            HStack {
                if embedded {
                    Text(String(appLocalized: "Friends")).ffType(.heading).foregroundStyle(theme.text)
                }
                Spacer(minLength: 8)
                FFSegmented(items: ["accepted", "incoming", "outgoing"], selection: $kind, count: { $0 == "incoming" ? incomingCount : nil }) { item in
                    switch item {
                    case "incoming": String(appLocalized: "Requests")
                    case "outgoing": String(appLocalized: "Sent")
                    default: String(appLocalized: "Friends")
                    }
                }
            }
            // Search sits in one filled field; the Find action appears once there is something to look up.
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.textSecondary)
                TextField(String(appLocalized: "Add a friend by username"), text: $handle)
                    .focused($handleFocused)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().ffType(.body)
                    .submitLabel(.search)
                    .onSubmit { Task { await lookup() } }
                if !handle.isEmpty {
                    Button(String(appLocalized: "Find")) { Task { await lookup() } }
                        .ffType(.label).foregroundStyle(theme.mossText)
                        .frame(minHeight: 44)
                        .buttonStyle(FFHapticPlainStyle())
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 50)
            .background(theme.control, in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            if let found { personRow(found, source: "lookup") }
            if let error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                FFButton(title: String(appLocalized: "Retry"), kind: .secondary) { Task { await load() } }
            }
            if loading { ProgressView().frame(maxWidth: .infinity) }
            if !loading && people.isEmpty && error == nil {
                Text(String(appLocalized: "No friends or requests here yet. Search an exact username to connect."))
                    .ffType(.body).foregroundStyle(theme.textSecondary)
            }
            ForEach(people) { personRow($0, source: "friends") }
            if nextCursor != nil {
                FFButton(title: String(appLocalized: "Load more"), kind: .ghost, busy: loading) { Task { await load(more: true) } }
            }
        }
    }

    private func personRow(_ person: SharedProfileIdentity, source: String) -> some View {
        ProfileIdentityLink(userID: person.userId, source: source, onClosed: { found = nil; Task { await load() } }) {
            FFCard {
                HStack(spacing: 12) {
                    CompanionAvatar(personID: person.userId.uuidString, companionID: person.companionId, isYou: false, monogram: person.initials, photoURL: person.avatarUrl, size: 44)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: person.displayName).ffType(.label)
                        Text(verbatim: "@\(person.handle)").ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(theme.textFaint)
                }
            }
        }
    }

    private func load(more: Bool = false) async {
        generation += 1
        let requestGeneration = generation
        let accountID = session.authSession?.user.id
        let cursor = more ? nextCursor : nil
        if !more { people = []; nextCursor = nil }
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            people = kind == "accepted" ? CompanionPreview.friendIdentities : []
            incomingCount = 0
            return
        }
        #endif
        loading = true
        defer { if generation == requestGeneration { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            let page = try await FitFightAPI().profileFriends(kind: kind, cursor: cursor, accessToken: token)
            try Task.checkCancellation()
            guard requestGeneration == generation, accountID == session.authSession?.user.id else { return }
            people.append(contentsOf: page.people)
            incomingCount = page.incomingCount
            nextCursor = page.nextCursor
            error = nil
        } catch is CancellationError {
        } catch {
            guard requestGeneration == generation else { return }
            people = []; nextCursor = nil
            self.error = error.localizedDescription
        }
    }

    private func lookup() async {
        lookupGeneration += 1
        let requestGeneration = lookupGeneration
        let accountID = session.authSession?.user.id
        found = nil
        loading = true
        defer { if requestGeneration == lookupGeneration { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            let person = try await FitFightAPI().lookupProfile(handle: handle, accessToken: token)
            try Task.checkCancellation()
            guard requestGeneration == lookupGeneration, accountID == session.authSession?.user.id else { return }
            found = person
            error = nil
        } catch is CancellationError {
        } catch {
            guard requestGeneration == lookupGeneration, accountID == session.authSession?.user.id else { return }
            self.error = error.localizedDescription
        }
    }
}

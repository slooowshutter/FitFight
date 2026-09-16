import SwiftUI

struct FriendsView: View {
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(localized: "Friends")).ffType(.heading)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }.frame(minHeight: 44)
            }.padding(.horizontal, theme.space.screenPadding).padding(.top, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: theme.space.cardGap) {
                    HStack {
                        TextField(String(localized: "Exact username"), text: $handle)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().ffType(.body)
                            .onSubmit { Task { await lookup() } }
                        FFButton(title: String(localized: "Find"), kind: .secondary, busy: loading) { Task { await lookup() } }
                    }
                    if let found { personRow(found, source: "lookup") }
                    Picker(String(localized: "Friends"), selection: $kind) {
                        Text(String(localized: "Friends")).tag("accepted")
                        Text(String(format: String(localized: "profile.requests-count"), incomingCount)).tag("incoming")
                        Text(String(localized: "Sent")).tag("outgoing")
                    }.pickerStyle(.segmented)
                    if let error {
                        FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                        FFButton(title: String(localized: "Retry"), kind: .secondary) { Task { await load() } }
                    }
                    if loading { ProgressView().frame(maxWidth: .infinity) }
                    if !loading && people.isEmpty && error == nil {
                        Text(String(localized: "No friends or requests here yet. Search an exact username to connect."))
                            .ffType(.body).foregroundStyle(theme.textSecondary)
                    }
                    ForEach(people) { personRow($0, source: "friends") }
                    if nextCursor != nil {
                        FFButton(title: String(localized: "Load more"), kind: .ghost, busy: loading) { Task { await load(more: true) } }
                    }
                }.padding(theme.space.screenPadding)
            }
        }.foregroundStyle(theme.text).background(theme.bg.ignoresSafeArea())
        .task(id: kind) { await load() }
        .onChange(of: scenePhase) { _, phase in
            generation += 1; lookupGeneration += 1; people = []; found = nil; nextCursor = nil
            if phase == .active { Task { await load() } }
        }
        .onChange(of: session.authSession?.user.id) { _, _ in generation += 1; lookupGeneration += 1; people = []; found = nil; dismiss() }
        .onDisappear { generation += 1; lookupGeneration += 1; people = []; found = nil; nextCursor = nil }
    }

    private func personRow(_ person: SharedProfileIdentity, source: String) -> some View {
        ProfileIdentityLink(userID: person.userId, source: source, onClosed: { Task { await load() } }) {
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

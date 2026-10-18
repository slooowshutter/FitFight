import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class FeedStore: ObservableObject {
    @Published var posts: [FitFightFightPost] = []
    @Published var nextCursor: String?
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var isSaving = false
    @Published var error: String?
    @Published var moreError: String?
    @Published var revision = 0
    @Published private(set) var reactingPostIDs: Set<UUID> = []

    private let api = FitFightAPI()
    private var listLoad = 0
    private var lastFightID: UUID?
    private var cachedUserID: UUID?
    var visiblePostIDs: Set<UUID> = []
    private(set) var stalePostIDs: Set<UUID> = []
    private var liveLoad = 0
    private var needsLiveRefresh = false

    func activate(userID: UUID?) {
        guard cachedUserID != userID else { return }
        cachedUserID = userID
        listLoad += 1
        posts = []
        nextCursor = nil
        lastFightID = nil
        error = nil
        isLoading = false
        isLoadingMore = false
        moreError = nil
        visiblePostIDs = []
        stalePostIDs = []
        needsLiveRefresh = false
        liveLoad += 1
        isSaving = false
        reactingPostIDs = []
    }

    func load(session: SessionStore, fightID: UUID? = nil, postID: UUID? = nil, more: Bool = false) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            posts = CompanionPreview.posts(fightID: fightID)
            nextCursor = nil
            return
        }
        #endif
        let userID = session.authSession?.user.id
        activate(userID: userID)
        guard let userID else { return }
        guard !more || (!isLoading && nextCursor != nil) else { return }
        lastFightID = fightID
        if more && !stalePostIDs.isDisjoint(with: visiblePostIDs) {
            needsLiveRefresh = true
        }
        listLoad += 1
        let load = listLoad
        isLoading = true
        isLoadingMore = more
        moreError = nil
        defer {
            if load == listLoad {
                isLoading = false
                isLoadingMore = false
            }
        }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            let result: FitFightFightPostList
            if let postID {
                let detail = try await api.fightPost(postID: postID, accessToken: token)
                result = FitFightFightPostList(posts: [detail.post], nextCursor: nil)
            } else if let fightID {
                result = try await api.fightPosts(fightID: fightID, cursor: more ? nextCursor : nil, accessToken: token)
            } else {
                result = try await api.feed(cursor: more ? nextCursor : nil, accessToken: token)
            }
            guard !Task.isCancelled, load == listLoad, session.authSession?.user.id == userID, cachedUserID == userID else { return }
            let pendingReactions = Dictionary(
                posts.filter { reactingPostIDs.contains($0.id) }.map { ($0.id, $0.reactions) },
                uniquingKeysWith: { _, last in last }
            )
            let refreshed = result.posts.map { post in
                post.updating(reactions: pendingReactions[post.id])
            }
            posts = more ? posts + refreshed.filter { post in !posts.contains(where: { $0.id == post.id }) } : refreshed
            stalePostIDs.formIntersection(posts.map(\.id))
            if needsLiveRefresh {
                stalePostIDs.formUnion(refreshed.map(\.id))
            } else {
                stalePostIDs.subtract(refreshed.map(\.id))
            }
            nextCursor = result.nextCursor
            if !more {
                revision += 1
                error = nil
            }
            RemoteImageLoader.shared.prefetch(
                refreshed.compactMap { $0.author.photoURL },
                kind: .avatar
            )
            RemoteImageLoader.shared.prefetch(
                refreshed.flatMap { $0.media }.compactMap { $0.kind == "video" ? nil : $0.url },
                kind: .photo
            )
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard load == listLoad, session.authSession?.user.id == userID, cachedUserID == userID else { return }
            if case FitFightAPIError.http(let status, _, _) = error, status == 403 || status == 404 {
                posts = []
                nextCursor = nil
            }
            if more {
                moreError = error.localizedDescription
            } else {
                self.error = error.localizedDescription
            }
        }
        if load == listLoad, needsLiveRefresh {
            isLoading = false
            isLoadingMore = false
            needsLiveRefresh = false
            await refreshVisible(session: session, fightID: fightID, invalidate: false)
        }
    }

    func refreshVisible(session: SessionStore, fightID: UUID? = nil, invalidate: Bool = true) async {
        if invalidate { stalePostIDs.formUnion(posts.map(\.id)) }
        if isLoading {
            needsLiveRefresh = true
            return
        }
        if posts.isEmpty {
            await load(session: session, fightID: fightID)
            return
        }
        guard let userID = session.authSession?.user.id, cachedUserID == userID else { return }
        let ids = posts.map(\.id).filter { visiblePostIDs.contains($0) && stalePostIDs.contains($0) }
        guard !ids.isEmpty else { return }
        liveLoad += 1
        let request = liveLoad
        let generation = listLoad
        do {
            let token = try await session.freshAccessToken()
            for id in ids {
                guard !Task.isCancelled, request == liveLoad, generation == listLoad,
                      session.authSession?.user.id == userID, cachedUserID == userID else { return }
                do {
                    let result = try await api.fightPost(postID: id, accessToken: token)
                    guard !Task.isCancelled, request == liveLoad, generation == listLoad,
                          session.authSession?.user.id == userID, cachedUserID == userID else { return }
                    // Updating the existing slot keeps pagination and the reading position intact.
                    replace(result.post)
                    stalePostIDs.remove(id)
                } catch FitFightAPIError.http(let status, _, _) where status == 403 || status == 404 {
                    guard !Task.isCancelled, request == liveLoad, generation == listLoad,
                          session.authSession?.user.id == userID, cachedUserID == userID else { return }
                    posts.removeAll { $0.id == id }
                    stalePostIDs.remove(id)
                }
            }
            revision += 1
            error = nil
        } catch {
            guard !Task.isCancelled, request == liveLoad, generation == listLoad,
                  session.authSession?.user.id == userID, cachedUserID == userID else { return }
            self.error = error.localizedDescription
        }
    }

    func create(
        session: SessionStore,
        destinations: [FeedPostDestination],
        body: String,
        images: [UIImage],
        videoURL: URL? = nil,
        taggedUserIDs: [UUID] = []
    ) async -> Bool {
        guard let userID = session.authSession?.user.id, cachedUserID == userID else { return false }
        isSaving = true
        defer { if cachedUserID == userID { isSaving = false } }
        do {
            var mediaIDs: [UUID] = []
            if let videoURL {
                mediaIDs.append(try await MediaUploader.uploadVideo(videoURL, purpose: "fight_post", session: session, api: api).id)
                guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            }
            for image in images {
                mediaIDs.append(try await MediaUploader.upload(image, purpose: "fight_post", session: session, api: api).id)
                guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            }
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            _ = try await api.createFeedPosts(
                body: body,
                mediaIDs: mediaIDs,
                destinations: destinations,
                taggedUserIDs: taggedUserIDs,
                accessToken: token
            )
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            error = nil
            let reloadFightID = destinations.contains(where: { $0.type == "broadcast" }) ? nil : lastFightID
            await load(session: session, fightID: reloadFightID)
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { return false }
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    func replace(_ post: FitFightFightPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = reactingPostIDs.contains(post.id)
                ? post.updating(reactions: posts[index].reactions)
                : post
        }
    }

    func delete(session: SessionStore, post: FitFightFightPost) async {
        guard let userID = session.authSession?.user.id, cachedUserID == userID else { return }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            try await api.deleteFightPost(postID: post.id, accessToken: token)
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            posts.removeAll { $0.id == post.id }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            self.error = error.localizedDescription
        }
    }

    func update(session: SessionStore, post: FitFightFightPost, body: String) async -> Bool {
        guard let userID = session.authSession?.user.id, cachedUserID == userID else { return false }
        isSaving = true
        defer { if cachedUserID == userID { isSaving = false } }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            let result = try await api.updateFightPost(postID: post.id, body: body, accessToken: token)
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            replace(result.post)
            error = nil
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { return false }
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    func report(session: SessionStore, post: FitFightFightPost) async {
        guard let userID = session.authSession?.user.id, cachedUserID == userID else { return }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            try await api.reportFightPost(postID: post.id, reason: "other", accessToken: token)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            self.error = error.localizedDescription
        }
    }

    func hide(session: SessionStore, authorID: UUID) async {
        guard let userID = session.authSession?.user.id, cachedUserID == userID else { return }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            try await api.blockFeedAuthor(userID: authorID, accessToken: token)
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            posts.removeAll { $0.author.userId == authorID }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            self.error = error.localizedDescription
        }
    }

    func react(session: SessionStore, post: FitFightFightPost, emoji: String) async {
        guard let userID = session.authSession?.user.id, cachedUserID == userID,
              let index = posts.firstIndex(where: { $0.id == post.id }),
              reactingPostIDs.insert(post.id).inserted else { return }
        defer {
            if cachedUserID == userID { reactingPostIDs.remove(post.id) }
        }
        let previous = posts[index].reactions
        let removing = previous.contains { $0.mine && $0.emoji == emoji }
        var optimistic = previous.compactMap { reaction -> FitFightFightPost.Reaction? in
            let count = reaction.count - (reaction.mine ? 1 : 0)
            return count > 0 ? .init(emoji: reaction.emoji, count: count, mine: false) : nil
        }
        if !removing {
            if let selected = optimistic.firstIndex(where: { $0.emoji == emoji }) {
                optimistic[selected] = .init(emoji: emoji, count: optimistic[selected].count + 1, mine: true)
            } else {
                optimistic.append(.init(emoji: emoji, count: 1, mine: true))
            }
        }
        posts[index] = posts[index].updating(reactions: optimistic)
        error = nil
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            let result = try await api.reactToFightPost(postID: post.id, emoji: emoji, accessToken: token)
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = posts[index].updating(reactions: result.reactions)
            }
            error = nil
        } catch {
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return }
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = posts[index].updating(reactions: previous)
            }
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }
}

private func postableFights(_ fights: [Fight]) -> [Fight] {
    var seen = Set<String>()
    return fights
        .filter { fight in
            UUID(uuidString: fight.id) != nil
                && fight.status != .invited
                && !fight.pendingJoin
        }
        .sorted { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .live && rhs.status != .live
            }
            return lhs.listTitle.localizedCaseInsensitiveCompare(rhs.listTitle) == .orderedAscending
        }
        .filter { fight in
            seen.insert(fight.seriesId ?? fight.id).inserted
        }
}

struct FeedView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var composing = false
    @State private var openedPhoto: FeedOpenedPhoto?
    @State private var isRefreshingFeed = false

    var body: some View {
        FFScreen(refresh: feedRefresh) {
            FFScreenTitle(
                title: String(appLocalized: "Feed"),
                subtitle: String(appLocalized: "Posts from fights you’re in."),
                trailing: AnyView(composeButton)
            )
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if feed.posts.isEmpty && feed.isLoading {
                if !isRefreshingFeed {
                    FFLoadingBlock()
                }
            } else if feed.posts.isEmpty && !feed.isLoading {
                FFCard {
                    Text(String(appLocalized: "Nothing here yet. Tap + to post."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            FeedPostList(store: feed, onOpenPhoto: { openedPhoto = FeedOpenedPhoto(url: $0) })
        }
        .task {
            guard !staticRender, !CompanionPreview.isEnabled else { return }
            await feed.load(session: session)
        }
        .onChange(of: model.feedRevision) { _, _ in
            guard !staticRender, !CompanionPreview.isEnabled else { return }
            Task { await feed.refreshVisible(session: session) }
        }
        .sheet(isPresented: $composing) {
            FeedComposeSheet()
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
        .fullScreenCover(item: $openedPhoto) { photo in
            FightPostPhotoViewer(url: photo.url)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    private var feedRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: isRefreshingFeed,
            message: String(appLocalized: "Loading"),
            action: {
                isRefreshingFeed = true
                defer { isRefreshingFeed = false }
                await feed.load(session: session)
            }
        )
    }

    private var composeButton: some View {
        FFComposeButton(label: String(appLocalized: "New post")) { composing = true }
    }
}

struct FeedComposeSheet: View {
    var defaultFightID: UUID? = nil
    var broadcastOnly: Bool = false
    var onPosted: (() -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffStaticRender) private var staticRender
    @State private var everyone: Bool
    @State private var friends: Bool
    @State private var fightIDs: Set<UUID>
    @State private var friendPeople: [SharedProfileIdentity]?

    init(defaultFightID: UUID? = nil, broadcastOnly: Bool = false, onPosted: (() -> Void)? = nil) {
        self.defaultFightID = defaultFightID
        self.broadcastOnly = broadcastOnly
        self.onPosted = onPosted
        // Same composer from Feed and from a fight; only what starts ticked differs.
        _everyone = State(initialValue: defaultFightID == nil)
        _friends = State(initialValue: false)
        _fightIDs = State(initialValue: defaultFightID.map { [$0] } ?? [])
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled { _friendPeople = State(initialValue: CompanionPreview.friendIdentities) }
        #endif
    }

    private var fights: [Fight] {
        postableFights(model.fights)
    }

    private var allFightIDs: [UUID] {
        fights.compactMap { UUID(uuidString: $0.id) }
    }

    /// Everyone always means my friends and every fight I can post in right now.
    private var sendsToFriends: Bool { everyone || friends }

    private var chosenFightIDs: [UUID] {
        everyone ? allFightIDs : allFightIDs.filter(fightIDs.contains) + fightIDs.subtracting(allFightIDs)
    }

    private var destinations: [FeedPostDestination] {
        if broadcastOnly { return [.broadcast] }
        return (sendsToFriends ? [.friends] : []) + chosenFightIDs.map { .fight($0) }
    }

    var body: some View {
        FFScreen(clearance: false) {
            FFSheetHeader(title: broadcastOnly ? String(appLocalized: "Broadcast") : String(appLocalized: "New post")) { dismiss() }
            if broadcastOnly {
                Text(String(appLocalized: "This post appears on Feed for everyone signed in."))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                FightPostComposer(destinations: destinations) {
                    onPosted?()
                    dismiss()
                }
            } else if fights.isEmpty && defaultFightID == nil && friendPeople?.isEmpty == true {
                FFCard {
                    Text(String(appLocalized: "Add a friend or join a fight first, then post from here."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                FightPostComposer(destinations: destinations, destination: AnyView(audience)) {
                    onPosted?()
                    dismiss()
                }
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
        .task {
            guard !broadcastOnly, !staticRender, friendPeople == nil else { return }
            await loadFriends()
        }
    }

    private var audience: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(appLocalized: "Who sees this"))
                .ffType(.label)
                .foregroundStyle(theme.text)
            FFSegmented(
                items: [true, false],
                selection: Binding(
                    get: { everyone },
                    set: { picked in
                        // Choose starts from everything Everyone had, so you untick what to leave out.
                        if everyone && !picked {
                            friends = true
                            fightIDs = Set(allFightIDs)
                        }
                        everyone = picked
                    }
                ),
                fill: true
            ) { $0 ? String(appLocalized: "Everyone") : String(appLocalized: "Choose") }
            if everyone {
                FFCard {
                    HStack(spacing: 12) {
                        if !audiencePeople.isEmpty {
                            CompanionAvatarStack(people: audiencePeople, visible: 4, size: 30, ring: theme.card, halfBody: true)
                        }
                        Text(String(appLocalized: "My friends and everyone in my fights"))
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                FFGroupedRows {
                    audienceRow(String(appLocalized: "My friends"), systemImage: "person.2", count: friendPeople?.count, selected: friends) {
                        friends.toggle()
                    }
                    ForEach(fights) { fight in
                        if let id = UUID(uuidString: fight.id) {
                            FFDivider()
                            audienceRow(fight.listTitle, systemImage: "trophy", count: members(of: fight).count, selected: fightIDs.contains(id)) {
                                if fightIDs.contains(id) { fightIDs.remove(id) } else { fightIDs.insert(id) }
                            }
                        }
                    }
                }
            }
            if destinations.isEmpty {
                Text(String(appLocalized: "Pick who sees this"))
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            } else if !sendsToFriends || friendPeople != nil {
                Text(String(appLocalized: "feed.seen-by", defaultValue: "Seen by \(audiencePeople.count) people"))
                    .ffType(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func audienceRow(_ title: String, systemImage: String, count: Int?, selected: Bool, action: @escaping () -> Void) -> some View {
        FFGroupedRow(
            title: title,
            subtitle: count.map { String(appLocalized: "feed.audience-people", defaultValue: "\($0) people") },
            systemImage: systemImage,
            subtitleTone: .neutral,
            trailing: AnyView(
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? theme.mossText : theme.textFaint)
            ),
            action: action
        )
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    /// Who can see a post in this fight: everyone on the roster but you and pending invites.
    private func members(of fight: Fight) -> [Person] {
        fight.standings.filter { !$0.invited && !$0.person.isYou }.map(\.person)
    }

    /// Everyone the chosen audience reaches, once each.
    private var audiencePeople: [Person] {
        let friendList = sendsToFriends ? (friendPeople ?? []).map {
            Person(id: $0.userId.uuidString, name: $0.displayName, handle: $0.handle, initials: $0.initials, photoURL: $0.avatarUrl, companionId: $0.companionId)
        } : []
        let fightMembers = fights.filter { UUID(uuidString: $0.id).map(chosenFightIDs.contains) ?? false }.flatMap(members(of:))
        var seen = Set<String>()
        return (friendList + fightMembers).filter { seen.insert($0.id.lowercased()).inserted }
    }

    private func loadFriends() async {
        do {
            let token = try await session.freshAccessToken()
            var people: [SharedProfileIdentity] = []
            var cursor: UUID?
            repeat {
                let page = try await FitFightAPI().profileFriends(kind: "accepted", cursor: cursor, accessToken: token)
                people += page.people
                cursor = page.nextCursor
            } while cursor != nil
            friendPeople = people
        } catch {
            // No count when friends fail to load; posting still works.
        }
    }
}

struct FightPostsSection: View {
    let fightID: UUID
    @ObservedObject var fightFeed: FeedStore

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @State private var composing = false
    @State private var openedPhoto: FeedOpenedPhoto?

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            HStack(alignment: .center, spacing: 12) {
                if fightFeed.posts.isEmpty && !fightFeed.isLoading {
                    Text(String(appLocalized: "Tap + to post to this fight."))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                FFComposeButton(label: String(appLocalized: "New post")) { composing = true }
            }
            if let error = fightFeed.error, !error.isEmpty {
                Text(error)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }
            FeedPostList(store: fightFeed, fightID: fightID, onOpenPhoto: { openedPhoto = FeedOpenedPhoto(url: $0) })
        }
        .environmentObject(fightFeed)
        .task(id: fightID) {
            await fightFeed.load(session: session, fightID: fightID)
        }
        .onChange(of: model.feedRevision) { _, _ in
            Task { await fightFeed.refreshVisible(session: session, fightID: fightID) }
        }
        .sheet(isPresented: $composing) {
            FeedComposeSheet(defaultFightID: fightID) {
                Task { await fightFeed.load(session: session, fightID: fightID) }
            }
            .environmentObject(model)
            .environmentObject(session)
            .environmentObject(feed)
            .fitFightTheme(theme)
            .presentationBackground(theme.bg)
        }
        .fullScreenCover(item: $openedPhoto) { photo in
            FightPostPhotoViewer(url: photo.url)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }
}

private struct FeedPostList: View {
    @ObservedObject var store: FeedStore
    var fightID: UUID? = nil
    let onOpenPhoto: (URL) -> Void

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        LazyVStack(alignment: .leading, spacing: theme.space.cardGap) {
            ForEach(store.posts) { post in
                FightPostCard(
                    post: post,
                    onOpen: fightID == nil ? post.fightId.map { id in { model.openFight(id: id.uuidString) } } : nil,
                    onOpenPhoto: onOpenPhoto
                )
                .onAppear {
                    store.visiblePostIDs.insert(post.id)
                    if store.stalePostIDs.contains(post.id) {
                        Task { await store.refreshVisible(session: session, fightID: fightID, invalidate: false) }
                    }
                }
                .onDisappear { store.visiblePostIDs.remove(post.id) }
            }
            if store.nextCursor != nil {
                HStack(spacing: 12) {
                    if let error = store.moreError {
                        Text(error)
                            .ffType(.caption)
                            .foregroundStyle(theme.emberText)
                            .lineLimit(2)
                        Button(String(appLocalized: "Try again")) {
                            Task { await store.load(session: session, fightID: fightID, more: true) }
                        }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                        .buttonStyle(FFHapticPlainStyle())
                    } else if store.isLoadingMore {
                        ProgressView()
                            .tint(theme.textSecondary)
                            .accessibilityLabel(String(appLocalized: "Loading"))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .task {
                    guard store.moreError == nil else { return }
                    await store.load(session: session, fightID: fightID, more: true)
                }
            }
        }
        .animation(nil, value: store.posts.map(\.id))
    }
}

struct FightPostComposer: View {
    let destinations: [FeedPostDestination]
    var destination: AnyView? = nil
    var onPosted: (() -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    @State private var bodyText = ""
    @State private var mentionPeople: [FitFightFightPost.Author] = []
    @State private var mediaItems: [PhotosPickerItem] = []
    @State private var isLoadingMedia = false
    @State private var images: [UIImage] = []
    @State private var videoURL: URL?
    @State private var showLibrary = false
    @State private var showCamera = false
    @FocusState private var bodyFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            FFCard {
                HStack(alignment: .top, spacing: 12) {
                    CompanionAvatar(model.you, size: 36)
                    VStack(alignment: .leading, spacing: 12) {
                        if staticRender {
                            Text(String(appLocalized: "Add a note or some proof…"))
                                .ffType(.body)
                                .foregroundStyle(theme.textTertiary)
                                .frame(maxWidth: .infinity, minHeight: 63, alignment: .topLeading)
                        } else {
                            FeedMentionField(
                                text: $bodyText,
                                people: $mentionPeople,
                                main: destinations.contains { $0.type == "main" || $0.type == "broadcast" },
                                fightIDs: destinations.compactMap(\.fightId)
                            ) {
                                TextField(String(appLocalized: "Add a note or some proof…"), text: $bodyText, axis: .vertical)
                                    .focused($bodyFocused)
                                    .ffType(.body)
                                    .foregroundStyle(theme.text)
                                    .lineLimit(3...6)
                                    .onChange(of: bodyText) { _, value in
                                        if value.count > 500 {
                                            bodyText = String(value.prefix(500))
                                        }
                                    }
                            }
                        }
                        if !images.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                                            .contentShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                                            .onTapGesture {
                                                images.remove(at: index)
                                            }
                                    }
                                }
                            }
                        }
                        if videoURL != nil {
                            HStack(spacing: 8) {
                                Image(systemName: "video.fill")
                                    .foregroundStyle(theme.mossText)
                                Text(String(appLocalized: "Video"))
                                    .ffType(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            .onTapGesture {
                                clearVideo()
                            }
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                // NOTE: a Menu, not a dialog: its actions run once it has closed, so the library always appears.
                Group {
                    if CameraPhotoPicker.isAvailable {
                        Menu {
                            Button {
                                showCamera = true
                            } label: {
                                Label(String(appLocalized: "Take Photo"), systemImage: "camera")
                            }
                            Button {
                                showLibrary = true
                            } label: {
                                Label(String(appLocalized: "Photo Library"), systemImage: "photo")
                            }
                        } label: {
                            mediaButtonLabel
                        }
                    } else {
                        Button {
                            showLibrary = true
                        } label: {
                            mediaButtonLabel
                        }
                    }
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(images.count >= 4 || videoURL != nil || isLoadingMedia || feed.isSaving)
                if isLoadingMedia { ProgressView().tint(theme.mossText) }
            }
            if let destination {
                destination
            }
            FFButton(
                title: feed.isSaving ? String(appLocalized: "Posting…") : String(appLocalized: "Post"),
                kind: .primary,
                size: .large,
                enabled: canPost,
                fullWidth: true
            ) {
                Task { await submit() }
            }
        }
        .ffKeyboardDismissOnBackgroundTap()
        .photosPicker(
            isPresented: $showLibrary,
            selection: $mediaItems,
            maxSelectionCount: max(1, 4 - images.count),
            matching: .any(of: [.images, .videos])
        )
        .fullScreenCover(isPresented: $showCamera) {
            CameraPhotoPicker(
                onCapture: { image in
                    showCamera = false
                    if images.count < 4, videoURL == nil {
                        images.append(image)
                        feed.error = nil
                    }
                },
                onCancel: {
                    showCamera = false
                }
            )
            .ignoresSafeArea()
        }
        .onChange(of: mediaItems) { _, items in
            Task { await loadMedia(items) }
        }
    }

    private var canPost: Bool {
        let note = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !feed.isSaving && !isLoadingMedia && !destinations.isEmpty && (!note.isEmpty || !images.isEmpty || videoURL != nil)
    }

    private var mediaButtonLabel: some View {
        Label(String(appLocalized: "Photo or video"), systemImage: "photo.on.rectangle.angled")
            .ffType(.label)
            .foregroundStyle(theme.mossText)
            .padding(.horizontal, 16)
            .frame(minHeight: 42)
            .background(theme.chip, in: Capsule())
            .overlay { Capsule().strokeBorder(theme.chipEdge, lineWidth: 1) }
    }

    private func loadMedia(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false; mediaItems = [] }
        let videos = items.filter { item in
            item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        }
        guard videos.isEmpty || (items.count == 1 && images.isEmpty) else {
            feed.error = String(appLocalized: "Choose up to four photos or one video per post.")
            return
        }
        do {
            if let item = videos.first {
                guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                    throw MediaUploader.UploadError.invalidVideo
                }
                videoURL = picked.url
            } else {
                var loaded = images
                for item in items {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        throw MediaUploader.UploadError.invalidImage
                    }
                    loaded.append(image)
                }
                images = loaded
            }
            feed.error = nil
        } catch {
            feed.error = error.localizedDescription
        }
    }

    private func clearVideo() {
        if let videoURL, videoURL.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: videoURL)
        }
        videoURL = nil
    }

    private func submit() async {
        let note = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if await feed.create(
            session: session,
            destinations: destinations,
            body: note,
            images: images,
            videoURL: videoURL,
            taggedUserIDs: FeedMention.taggedUserIDs(in: note, people: mentionPeople)
        ) {
            bodyText = ""
            images = []
            clearVideo()
            onPosted?()
        }
    }
}

struct FightPostCard: View {
    let post: FitFightFightPost
    var targetCommentID: UUID? = nil
    var onTargetCommentLoaded: (() -> Void)? = nil
    var onOpen: (() -> Void)?
    var onOpenPhoto: (URL) -> Void

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @State private var showActions = false
    @State private var confirmDelete = false
    @State private var editing = false
    @State private var draft = ""

    var body: some View {
        FFCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ProfileIdentityLink(userID: post.author.userId, source: "feed") {
                        CompanionAvatar(
                            personID: post.author.userId.uuidString,
                            companionID: post.author.companionId,
                            isYou: post.mine,
                            monogram: post.author.initials,
                            photoURL: post.author.photoURL,
                            size: 38
                        )
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        ProfileIdentityLink(userID: post.author.userId, source: "feed") {
                            Text(verbatim: post.author.atHandle)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                                .lineLimit(1)
                        }
                        HStack(spacing: 5) {
                            Text(post.channelLabel)
                                .lineLimit(1)
                            Text("·")
                            Text(post.createdDate, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                                .fixedSize()
                        }
                        .ffType(.micro)
                        .foregroundStyle(theme.textTertiary)
                        .contentShape(Rectangle())
                        .onTapGesture { onOpen?() }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(alignment: .top, spacing: 0) {
                        TextTranslationButton(text: post.body)
                        Button {
                            showActions = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(theme.textFaint)
                                .frame(height: 20)
                                .frame(width: 44, height: 44, alignment: .top)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .accessibilityLabel(String(appLocalized: "Post actions"))
                    }
                }
                if !post.tags.isEmpty {
                    Text(post.tags.map { "@\($0.handle)" }.joined(separator: " "))
                        .ffType(.caption)
                        .foregroundStyle(theme.mossText)
                }
                if !post.body.isEmpty {
                    Text(post.body)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(post.media) { media in
                    MediaAttachment(media: media, onOpenPhoto: onOpenPhoto)
                }
                FightPostEngagement(post: post, targetCommentID: targetCommentID, onTargetCommentLoaded: onTargetCommentLoaded)
            }
        }
        .confirmationDialog(String(appLocalized: "Post"), isPresented: $showActions, titleVisibility: .hidden) {
            if post.mine {
                Button(String(appLocalized: "Edit")) {
                    draft = post.body
                    editing = true
                }
                Button(String(appLocalized: "Delete"), role: .destructive) {
                    confirmDelete = true
                }
            } else {
                Button(String(appLocalized: "Report")) {
                    Task { await feed.report(session: session, post: post) }
                }
                Button(String(appLocalized: "Hide this person"), role: .destructive) {
                    Task { await feed.hide(session: session, authorID: post.author.userId) }
                }
            }
            Button(String(appLocalized: "Cancel"), role: .cancel) {}
        }
        .alert(String(appLocalized: "Delete this post?"), isPresented: $confirmDelete) {
            Button(String(appLocalized: "Delete"), role: .destructive) {
                Task { await feed.delete(session: session, post: post) }
            }
            Button(String(appLocalized: "Cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $editing) {
            FightPostEditSheet(
                draft: $draft,
                main: post.broadcast || post.audience == "main" || post.fightId == nil,
                fightIDs: {
                    var ids = post.channels.map(\.fightId)
                    if let fightId = post.fightId, !ids.contains(fightId) {
                        ids.append(fightId)
                    }
                    return ids
                }()
            ) {
                let note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if await feed.update(session: session, post: post, body: note) {
                    editing = false
                }
            }
            .environmentObject(session)
            .environmentObject(feed)
            .fitFightTheme(theme)
            .presentationBackground(theme.bg)
        }
    }
}

private struct FightPostEditSheet: View {
    @Binding var draft: String
    var main: Bool
    var fightIDs: [UUID]
    var onSave: () async -> Void

    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var mentionPeople: [FitFightFightPost.Author] = []
    @FocusState private var draftFocused: Bool

    var body: some View {
        FFScreen(clearance: false) {
            FFSheetHeader(title: String(appLocalized: "Edit post")) { dismiss() }
            FFCard {
                FeedMentionField(text: $draft, people: $mentionPeople, main: main, fightIDs: fightIDs) {
                    TextField(String(appLocalized: "Add a note or some proof…"), text: $draft, axis: .vertical)
                        .focused($draftFocused)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(3...8)
                        .onChange(of: draft) { _, value in
                            if value.count > 500 {
                                draft = String(value.prefix(500))
                            }
                        }
                }
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            FFButton(
                title: feed.isSaving ? String(appLocalized: "Saving…") : String(appLocalized: "Save"),
                kind: .primary,
                fullWidth: true
            ) {
                Task { await onSave() }
            }
            .disabled(feed.isSaving)
        }
    }
}

struct FeedOpenedPhoto: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct FightPostPhotoViewer: View {
    let url: URL
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { dismiss() }
            RemotePhoto(url: url, kind: .photo, contentMode: .fit) {
                theme.control
            }
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { dismiss() }
            .accessibilityHidden(true)
            VStack {
                HStack {
                    Spacer()
                    Button(String(appLocalized: "Close")) { dismiss() }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                        .frame(minWidth: 44, minHeight: 44)
                        .buttonStyle(FFHapticPlainStyle())
                }
                Spacer()
            }
            .padding(.horizontal, theme.space.screenPadding)
        }
    }
}

private struct CameraPhotoPicker: UIViewControllerRepresentable {
    var onCapture: (UIImage) -> Void
    var onCancel: () -> Void

    static var isAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        picker.mediaTypes = [UTType.image.identifier]
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {
        picker.delegate = context.coordinator
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onCapture: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            Task { @MainActor in
                onCancel()
            }
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let image = info[.originalImage] as? UIImage
            Task { @MainActor in
                if let image {
                    onCapture(image)
                } else {
                    onCancel()
                }
            }
        }
    }
}

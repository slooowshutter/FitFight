import AVKit
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
            if !needsLiveRefresh { stalePostIDs.subtract(refreshed.map(\.id)) }
            nextCursor = result.nextCursor
            if !more {
                revision += 1
                error = nil
            }
            RemoteImageLoader.shared.prefetch(
                refreshed.compactMap { $0.author.avatar?.url },
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
        videoURL: URL? = nil
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
                taggedUserIDs: [],
                accessToken: token
            )
            guard session.authSession?.user.id == userID, cachedUserID == userID else { return false }
            error = nil
            await load(session: session, fightID: lastFightID)
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
    var showsChrome: Bool = true

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
            if showsChrome {
                FFScreenTitle(
                    title: String(localized: "Feed"),
                    subtitle: String(localized: "Posts from fights you’re in."),
                    trailing: AnyView(composeButton)
                )
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if feed.posts.isEmpty && feed.isLoading {
                if !isRefreshingFeed {
                    FFLoadingBlock()
                }
            } else if feed.posts.isEmpty && !feed.isLoading {
                FFCard {
                    Text(String(localized: "Nothing here yet. Tap + to post."))
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

    private var feedRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: isRefreshingFeed,
            message: String(localized: "Loading"),
            action: {
                isRefreshingFeed = true
                defer { isRefreshingFeed = false }
                await feed.load(session: session)
            }
        )
    }

    private var composeButton: some View {
        FeedComposeButton { composing = true }
    }
}

struct FeedComposeSheet: View {
    var defaultFightID: UUID? = nil
    var onPosted: (() -> Void)? = nil

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: Set<FeedPostDestination>

    init(defaultFightID: UUID? = nil, onPosted: (() -> Void)? = nil) {
        self.defaultFightID = defaultFightID
        self.onPosted = onPosted
        _destinations = State(
            initialValue: defaultFightID.map { Set([FeedPostDestination.fight($0)]) } ?? []
        )
    }

    private var fights: [Fight] {
        postableFights(model.fights)
    }

    var body: some View {
        FFScreen(clearance: false) {
            HStack {
                Text(String(localized: "New post"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            Text("Your post will only appear in the channels you select. You can choose more than one.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if fights.isEmpty && defaultFightID == nil {
                FFCard {
                    Text(String(localized: "Join a fight first, then post from here."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                FightPostComposer(
                    destinations: Array(destinations),
                    destination: AnyView(FeedDestinationMenu(fights: fights, destinations: $destinations))
                ) {
                    onPosted?()
                    dismiss()
                }
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
    }
}

struct FeedDestinationMenu: View {
    let fights: [Fight]
    @Binding var destinations: Set<FeedPostDestination>
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    private var allFightDestinations: Set<FeedPostDestination> {
        Set(fights.compactMap { fight in
            UUID(uuidString: fight.id).map { FeedPostDestination.fight($0) }
        })
    }

    private var everythingSelected: Bool {
        destinations.contains(.main)
            && !allFightDestinations.isEmpty
            && allFightDestinations.isSubset(of: destinations)
    }

    private var label: String {
        if destinations.isEmpty {
            return String(localized: "Choose where")
        }
        if everythingSelected {
            return String(localized: "All fights")
        }
        if destinations.count == 1, let id = destinations.first?.fightId {
            return fights.first(where: { $0.id.caseInsensitiveCompare(id.uuidString) == .orderedSame })?.listTitle
                ?? String(localized: "Choose where")
        }
        return String(localized: "\(destinations.count) fights")
    }

    var body: some View {
        if staticRender {
            menuLabel
        } else {
            Menu {
                Button {
                    if everythingSelected {
                        destinations.removeAll()
                    } else {
                        destinations = allFightDestinations.union([.main])
                    }
                } label: {
                    destinationLabel(String(localized: "All fights"), selected: everythingSelected)
                }
                ForEach(fights) { fight in
                    if let id = UUID(uuidString: fight.id) {
                        Button {
                            toggle(.fight(id))
                        } label: {
                            destinationLabel(fight.listTitle, selected: destinations.contains(.fight(id)))
                        }
                    }
                }
            } label: {
                menuLabel
            }
            .menuOrder(.fixed)
            .menuActionDismissBehavior(.disabled)
            .accessibilityLabel(String(localized: "Choose where"))
            .accessibilityValue(label)
        }
    }

    private var menuLabel: some View {
        HStack(spacing: 4) {
            Text(label)
                .ffType(.label)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(destinations.isEmpty ? theme.emberText : theme.mossText)
    }

    @ViewBuilder
    private func destinationLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func toggle(_ destination: FeedPostDestination) {
        if destinations.contains(destination) {
            destinations.remove(destination)
            destinations.remove(.main)
        } else {
            destinations.insert(destination)
        }
    }
}

private struct FeedComposeButton: View {
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.mossOn)
                .frame(width: 36, height: 36)
                .background(theme.mossFill, in: Circle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(String(localized: "New post"))
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
                    Text(String(localized: "Tap + to post to this fight."))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                Spacer(minLength: 0)
                FeedComposeButton { composing = true }
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
                    onOpen: fightID == nil ? post.fightId.map { id in { model.openFightFromFeed(id: id.uuidString) } } : nil,
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
                        Button(String(localized: "Try again")) {
                            Task { await store.load(session: session, fightID: fightID, more: true) }
                        }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                        .buttonStyle(FFHapticPlainStyle())
                    } else if store.isLoadingMore {
                        ProgressView()
                            .tint(theme.textSecondary)
                            .accessibilityLabel(String(localized: "Loading"))
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

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    @State private var bodyText = ""
    @State private var mediaItems: [PhotosPickerItem] = []
    @State private var isLoadingMedia = false
    @State private var images: [UIImage] = []
    @State private var videoURL: URL?
    @State private var showMediaSource = false
    @State private var showLibrary = false
    @State private var showCamera = false
    @State private var pendingMedia: MediaSource?

    private enum MediaSource {
        case camera
        case library
    }

    var body: some View {
        FFCard {
            VStack(alignment: .leading, spacing: 12) {
                if staticRender {
                    Text(String(localized: "Add a note or some proof…"))
                        .ffType(.body)
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 63, alignment: .topLeading)
                } else {
                    TextField(String(localized: "Add a note or some proof…"), text: $bodyText, axis: .vertical)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(3...6)
                        .onChange(of: bodyText) { _, value in
                            if value.count > 500 {
                                bodyText = String(value.prefix(500))
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
                        Text(String(localized: "Video"))
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                    }
                    .onTapGesture {
                        clearVideo()
                    }
                }
                if let destination {
                    HStack {
                        Text("Channels")
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                        Spacer(minLength: 8)
                        destination
                    }
                    .padding(.vertical, 8)
                }
                HStack(alignment: .center, spacing: 10) {
                    Button {
                        showCamera = false
                        showLibrary = false
                        if CameraPhotoPicker.isAvailable {
                            showMediaSource = true
                        } else {
                            presentMedia(.library, waitForSourceDialog: false)
                        }
                    } label: {
                        Label(String(localized: "Media"), systemImage: "photo.on.rectangle.angled")
                            .ffType(.label)
                            .foregroundStyle(theme.mossText)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(images.count >= 4 || videoURL != nil || isLoadingMedia || feed.isSaving)
                    if isLoadingMedia { ProgressView().tint(theme.mossText) }
                    Spacer(minLength: 8)
                    FFButton(
                        title: feed.isSaving ? String(localized: "Posting…") : String(localized: "Post"),
                        kind: .primary,
                        fullWidth: false
                    ) {
                        Task { await submit() }
                    }
                    .disabled(!canPost)
                }
            }
        }
        .confirmationDialog(String(localized: "Add media"), isPresented: $showMediaSource, titleVisibility: .visible) {
            Button(String(localized: "Take Photo")) {
                pendingMedia = .camera
            }
            Button(String(localized: "Photo Library")) {
                pendingMedia = .library
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .onChange(of: showMediaSource) { _, presented in
            guard !presented else { return }
            let next = pendingMedia
            pendingMedia = nil
            guard let next else { return }
            presentMedia(next, waitForSourceDialog: true)
        }
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

    private func presentMedia(_ source: MediaSource, waitForSourceDialog: Bool) {
        Task { @MainActor in
            showCamera = false
            showLibrary = false
            if waitForSourceDialog {
                // NOTE: the composer is already a sheet; presenting camera/library while Add media is still dismissing never appears.
                try? await Task.sleep(for: .milliseconds(450))
            } else {
                await Task.yield()
            }
            guard !Task.isCancelled else { return }
            switch source {
            case .camera:
                showCamera = true
            case .library:
                showLibrary = true
            }
        }
    }

    private func loadMedia(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false; mediaItems = [] }
        let videos = items.filter { item in
            item.supportedContentTypes.contains { $0.conforms(to: .movie) }
        }
        guard videos.isEmpty || (items.count == 1 && images.isEmpty) else {
            feed.error = String(localized: "Choose up to four photos or one video per post.")
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
            videoURL: videoURL
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
                    CompanionAvatar(
                        personID: post.author.userId.uuidString,
                        companionID: post.author.companionId,
                        isYou: post.mine,
                        monogram: post.author.initials,
                        photoURL: post.author.avatar?.url,
                        size: 38
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: post.author.atHandle)
                            .ffType(.rowTitle)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text(post.channelLabel)
                                .lineLimit(1)
                            Text("·")
                            Text(post.createdDate, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                                .fixedSize()
                        }
                        .ffType(.micro)
                        .foregroundStyle(theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onOpen?()
                    }
                    Button {
                        showActions = true
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(theme.textFaint)
                            .frame(width: 32, height: 20)
                            .frame(height: 38, alignment: .top)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityLabel(String(localized: "Post actions"))
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
                    if let url = media.url {
                        if media.kind == "video" {
                            FightPostVideo(url: url)
                        } else {
                            FightPostPhoto(
                                url: url,
                                width: media.width,
                                height: media.height,
                                onOpen: { onOpenPhoto(url) }
                            )
                        }
                    }
                }
                FightPostEngagement(post: post, targetCommentID: targetCommentID, onTargetCommentLoaded: onTargetCommentLoaded)
            }
        }
        .confirmationDialog(String(localized: "Post"), isPresented: $showActions, titleVisibility: .hidden) {
            if post.mine {
                Button(String(localized: "Edit")) {
                    draft = post.body
                    editing = true
                }
                Button(String(localized: "Delete"), role: .destructive) {
                    confirmDelete = true
                }
            } else {
                Button(String(localized: "Report")) {
                    Task { await feed.report(session: session, post: post) }
                }
                Button(String(localized: "Hide this person"), role: .destructive) {
                    Task { await feed.hide(session: session, authorID: post.author.userId) }
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .alert(String(localized: "Delete this post?"), isPresented: $confirmDelete) {
            Button(String(localized: "Delete"), role: .destructive) {
                Task { await feed.delete(session: session, post: post) }
            }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .sheet(isPresented: $editing) {
            FightPostEditSheet(draft: $draft) {
                let note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if await feed.update(session: session, post: post, body: note) {
                    editing = false
                }
            }
            .environmentObject(feed)
            .fitFightTheme(theme)
            .presentationBackground(theme.bg)
        }
    }
}

private struct FightPostEditSheet: View {
    @Binding var draft: String
    var onSave: () async -> Void

    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FFScreen(clearance: false) {
            HStack {
                Text(String(localized: "Edit post"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            FFCard {
                TextField(String(localized: "Add a note or some proof…"), text: $draft, axis: .vertical)
                    .ffType(.body)
                    .foregroundStyle(theme.text)
                    .lineLimit(3...8)
                    .onChange(of: draft) { _, value in
                        if value.count > 500 {
                            draft = String(value.prefix(500))
                        }
                    }
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            FFButton(
                title: feed.isSaving ? String(localized: "Saving…") : String(localized: "Save"),
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

private struct FightPostPhoto: View {
    let url: URL
    let width: Int
    let height: Int
    let onOpen: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        Button(action: onOpen) {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .overlay {
                    RemotePhoto(url: url, kind: .photo) {
                        theme.control
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(String(localized: "View photo"))
    }

    private var ratio: CGFloat {
        CGFloat(max(width, 1)) / CGFloat(max(height, 1))
    }
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
                    Button(String(localized: "Close")) { dismiss() }
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

private struct FightPostVideo: View {
    let url: URL
    @Environment(\.ffTheme) private var theme
    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .onAppear {
                if player == nil {
                    player = AVPlayer(url: url)
                }
            }
            .onDisappear {
                player?.pause()
                player = nil
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

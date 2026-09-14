import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FeedStore: ObservableObject {
    @Published var posts: [FitFightFightPost] = []
    @Published var nextCursor: String?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    private let api = FitFightAPI()
    private var listLoad = 0
    private var lastFightID: UUID?

    func load(session: SessionStore, fightID: UUID? = nil, more: Bool = false) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            posts = CompanionPreview.posts(fightID: fightID)
            nextCursor = nil
            return
        }
        #endif
        lastFightID = fightID
        listLoad += 1
        let load = listLoad
        isLoading = true
        defer {
            if load == listLoad { isLoading = false }
        }
        do {
            let token = try await session.freshAccessToken()
            let result: FitFightFightPostList
            if let fightID {
                result = try await api.fightPosts(fightID: fightID, cursor: more ? nextCursor : nil, accessToken: token)
            } else {
                result = try await api.feed(cursor: more ? nextCursor : nil, accessToken: token)
            }
            guard load == listLoad else { return }
            posts = more ? posts + result.posts.filter { post in !posts.contains(where: { $0.id == post.id }) } : result.posts
            nextCursor = result.nextCursor
            error = nil
            RemoteImageLoader.shared.prefetch(
                posts.compactMap { $0.author.avatar?.url },
                kind: .avatar
            )
            RemoteImageLoader.shared.prefetch(
                posts.flatMap { $0.media }.compactMap { $0.kind == "video" ? nil : $0.url },
                kind: .photo
            )
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard load == listLoad else { return }
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
        isSaving = true
        defer { isSaving = false }
        do {
            var mediaIDs: [UUID] = []
            if let videoURL {
                mediaIDs.append(try await MediaUploader.uploadVideo(videoURL, purpose: "fight_post", session: session, api: api).id)
            }
            for image in images {
                mediaIDs.append(try await MediaUploader.upload(image, purpose: "fight_post", session: session, api: api).id)
            }
            let token = try await session.freshAccessToken()
            _ = try await api.createFeedPosts(
                body: body,
                mediaIDs: mediaIDs,
                destinations: destinations,
                taggedUserIDs: [],
                accessToken: token
            )
            error = nil
            await load(session: session, fightID: lastFightID)
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    func prepare(fightID: UUID) {
        lastFightID = fightID
    }

    func replace(_ post: FitFightFightPost) {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index] = post
        }
    }

    func delete(session: SessionStore, post: FitFightFightPost) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.deleteFightPost(postID: post.id, accessToken: token)
            posts.removeAll { $0.id == post.id }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func update(session: SessionStore, post: FitFightFightPost, body: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.updateFightPost(postID: post.id, body: body, accessToken: token)
            replace(result.post)
            error = nil
            return true
        } catch {
            if Task.isCancelled || error is CancellationError { return false }
            self.error = error.localizedDescription
            return false
        }
    }

    func report(session: SessionStore, post: FitFightFightPost) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.reportFightPost(postID: post.id, reason: "other", accessToken: token)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func hide(session: SessionStore, authorID: UUID) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.blockFeedAuthor(userID: authorID, accessToken: token)
            posts.removeAll { $0.author.userId == authorID }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func react(session: SessionStore, post: FitFightFightPost, emoji: String) async {
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.reactToFightPost(postID: post.id, emoji: emoji, accessToken: token)
            replace(post.updating(reactions: result.reactions))
        } catch {
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
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @State private var composing = false

    var body: some View {
        FFScreen(refresh: feedRefresh) {
            FFScreenTitle(
                title: String(localized: "Feed"),
                subtitle: String(localized: "Posts from fights you’re in."),
                trailing: AnyView(FeedComposeButton { composing = true })
            )
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
            if feed.posts.isEmpty && feed.isLoading {
                FFLoadingBlock()
            } else if feed.posts.isEmpty && !feed.isLoading {
                FFCard {
                    Text(String(localized: "Nothing here yet. Tap + to post."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(feed.posts) { post in
                FightPostCard(
                    post: post,
                    onOpen: post.fightId.map { fightID in
                        { model.openFightFromFeed(id: fightID.uuidString) }
                    }
                )
            }
            if feed.nextCursor != nil {
                FFButton(title: String(localized: "More"), kind: .ghost, fullWidth: true) {
                    Task { await feed.load(session: session, more: true) }
                }
                .disabled(feed.isLoading)
            }
        }
        .task {
            guard !staticRender, !CompanionPreview.isEnabled else { return }
            await feed.load(session: session)
        }
        .sheet(isPresented: $composing) {
            FeedComposeSheet()
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(feed)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    private var feedRefresh: FFRefreshConfig {
        FFRefreshConfig(
            isRefreshing: model.isRefreshingFights,
            message: model.refreshStatusText,
            action: {
                await model.refreshFights(session: session, steps: steps, trigger: .manual)
                await feed.load(session: session)
            }
        )
    }
}

struct FeedComposeButton: View {
    var action: () -> Void

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

struct FeedComposeSheet: View {
    var lockedFightID: UUID? = nil

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var destinations: Set<FeedPostDestination> = []

    private var fights: [Fight] {
        postableFights(model.fights)
    }

    var body: some View {
        FFScreen(top: AnyView(VersionBanner()), clearance: false) {
            HStack {
                Text(String(localized: "New post"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            Text(lockedFightID == nil
                 ? String(localized: "Your post will only appear in the channels you select. You can choose more than one.")
                 : String(localized: "This post stays in this fight."))
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if let lockedFightID {
                FightPostComposer(destinations: [.fight(lockedFightID)]) {
                    dismiss()
                }
            } else if fights.isEmpty {
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
                    dismiss()
                }
            }
            if let error = feed.error, !error.isEmpty {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }
        }
        .onAppear {
            if let lockedFightID {
                feed.prepare(fightID: lockedFightID)
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
        !allFightDestinations.isEmpty && allFightDestinations.isSubset(of: destinations)
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
                        destinations = allFightDestinations
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
        } else {
            destinations.insert(destination)
        }
    }
}

struct FightPostsSection: View {
    let fightID: UUID

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var fightFeed: FeedStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: theme.space.cardGap) {
            if let error = fightFeed.error, !error.isEmpty {
                Text(error)
                    .ffType(.caption)
                    .foregroundStyle(theme.emberText)
            }
            if fightFeed.posts.isEmpty && fightFeed.isLoading {
                FFLoadingBlock()
            } else if fightFeed.posts.isEmpty && !fightFeed.isLoading {
                FFCard {
                    Text(String(localized: "Nothing here yet. Tap + to post."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(fightFeed.posts) { post in
                FightPostCard(post: post, onOpen: nil)
            }
        }
        .task(id: fightID) {
            await fightFeed.load(session: session, fightID: fightID)
        }
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
                    PhotosPicker(
                        selection: $mediaItems,
                        maxSelectionCount: max(1, 4 - images.count),
                        matching: .any(of: [.images, .videos])
                    ) {
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
        .onChange(of: mediaItems) { _, items in
            Task { await loadMedia(items) }
        }
    }

    private var canPost: Bool {
        let note = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !feed.isSaving && !isLoadingMedia && !destinations.isEmpty && (!note.isEmpty || !images.isEmpty || videoURL != nil)
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
    var onOpen: (() -> Void)?

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
                            Text(post.isMain ? String(localized: "Public") : post.fightName)
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
                            FightPostPhoto(url: url, width: media.width, height: media.height)
                        }
                    }
                }
                FightPostEngagement(post: post)
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
        FFScreen(top: AnyView(VersionBanner()), clearance: false) {
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

private struct FightPostPhoto: View {
    let url: URL
    let width: Int
    let height: Int

    @Environment(\.ffTheme) private var theme

    var body: some View {
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
    }

    private var ratio: CGFloat {
        CGFloat(max(width, 1)) / CGFloat(max(height, 1))
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

import AVKit
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FeedbackStore: ObservableObject {
    @Published var posts: [FitFightFeedbackPost] = []
    @Published var comments: [FitFightFeedbackComment] = []
    @Published var detail: FitFightFeedbackPost?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var isLaunchingFix = false
    @Published var canLaunchFix = false
    @Published var error: String?

    private let api = FitFightAPI()
    private var listLoad = 0
    private var detailLoad = 0
    private var voting: Set<UUID> = []
    private var voteClock = 0
    private var votes: [UUID: (clock: Int, voted: Bool, voteCount: Int)] = [:]
    private var commentClock = 0
    private var postedComments: [UUID: [(clock: Int, comment: FitFightFeedbackComment)]] = [:]
    private var commentsFor: UUID?

    func load(session: SessionStore, kind: String?) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            posts = Self.previewPosts.filter { kind == nil || $0.kind == kind }
            return
        }
        #endif
        listLoad += 1
        let load = listLoad
        let voteStartedAt = voteClock
        let localCounts = Dictionary(uniqueKeysWithValues: posts.map { ($0.id, $0.commentCount) })
        isLoading = true
        defer {
            if load == listLoad { isLoading = false }
        }
        do {
            let token = try await session.freshAccessToken()
            let posts = try await api.listFeedback(kind: kind, accessToken: token).posts
            guard load == listLoad else { return }
            self.posts = posts.map { fetched in
                var post = keepingNewerVote(fetched, startedAt: voteStartedAt)
                if let local = localCounts[post.id] {
                    post.commentCount = max(post.commentCount, local)
                }
                return post
            }
            RemoteImageLoader.shared.prefetch(
                self.posts.flatMap(\.media).compactMap { media in
                    RequestAttachment.showsPhoto(media) ? media.url : nil
                },
                kind: .photo
            )
            error = nil
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard load == listLoad else { return }
            self.error = error.localizedDescription
        }
    }

    func loadDetail(session: SessionStore, postID: UUID) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            detail = Self.previewPosts.first { $0.id == postID }
            comments = Self.previewComments
            canLaunchFix = false
            return
        }
        #endif
        detailLoad += 1
        let load = detailLoad
        let voteStartedAt = voteClock
        let commentStartedAt = commentClock
        if commentsFor != postID {
            comments = []
            commentsFor = postID
        }
        isLoading = true
        defer {
            if load == detailLoad { isLoading = false }
        }
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.feedbackDetail(postID: postID, accessToken: token)
            guard load == detailLoad else { return }
            let extras = postedAfter(postID: result.post.id, startedAt: commentStartedAt)
            var comments = result.comments
            for extra in extras where !comments.contains(where: { $0.id == extra.id }) {
                comments.append(extra)
            }
            var post = keepingNewerVote(result.post, startedAt: voteStartedAt)
            post.commentCount += comments.count - result.comments.count
            detail = post
            self.comments = comments
            commentsFor = post.id
            canLaunchFix = result.canLaunchFix
            RemoteImageLoader.shared.prefetch(
                post.media.compactMap { media in
                    RequestAttachment.showsPhoto(media) ? media.url : nil
                },
                kind: .photo
            )
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = post
            }
            error = nil
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard load == detailLoad else { return }
            self.error = error.localizedDescription
        }
    }

    func vote(session: SessionStore, postID: UUID) async {
        guard voting.insert(postID).inserted else { return }
        defer { voting.remove(postID) }
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.toggleFeedbackVote(postID: postID, accessToken: token)
            voteClock += 1
            votes[postID] = (voteClock, result.voted, result.voteCount)
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index].voted = result.voted
                posts[index].voteCount = result.voteCount
            }
            if detail?.id == postID {
                detail?.voted = result.voted
                detail?.voteCount = result.voteCount
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func submit(
        session: SessionStore,
        kind: String,
        title: String,
        body: String,
        images: [UIImage],
        videos: [URL],
        files: [URL]
    ) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            var mediaIDs: [UUID] = []
            for image in images {
                mediaIDs.append(try await MediaUploader.upload(image, purpose: "feedback", session: session, api: api).id)
            }
            for videoURL in videos {
                mediaIDs.append(try await MediaUploader.uploadVideo(videoURL, purpose: "feedback", session: session, api: api).id)
            }
            for fileURL in files {
                mediaIDs.append(try await MediaUploader.uploadFile(fileURL, purpose: "feedback", session: session, api: api).id)
            }
            let token = try await session.freshAccessToken()
            _ = try await api.createFeedback(
                FitFightCreateFeedback(
                    kind: kind,
                    title: title,
                    body: body,
                    mediaIds: mediaIDs,
                    metadata: .current()
                ),
                accessToken: token
            )
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    func launchFix(session: SessionStore, postID: UUID) async -> URL? {
        isLaunchingFix = true
        defer { isLaunchingFix = false }
        do {
            let token = try await session.freshAccessToken()
            let launched = try await api.launchFeedbackFix(
                postID: postID,
                metadata: .current(),
                accessToken: token
            )
            error = nil
            return launched.agentURL
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func report(session: SessionStore, post: FitFightFeedbackPost) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.reportFeedbackPost(postID: post.id, reason: "other", accessToken: token)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func hide(session: SessionStore, authorID: UUID) async {
        do {
            let token = try await session.freshAccessToken()
            try await api.blockFeedbackAuthor(userID: authorID, accessToken: token)
            posts.removeAll { $0.authorId == authorID }
            if detail?.authorId == authorID {
                detail = nil
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            self.error = error.localizedDescription
        }
    }

    func comment(session: SessionStore, postID: UUID, body: String) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let token = try await session.freshAccessToken()
            let created = try await api.createFeedbackComment(
                postID: postID,
                body: body,
                metadata: .current(),
                accessToken: token
            )
            commentClock += 1
            postedComments[postID, default: []].append((commentClock, created.comment))
            if commentsFor == postID, !comments.contains(where: { $0.id == created.comment.id }) {
                comments.append(created.comment)
            }
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index].commentCount += 1
            }
            if detail?.id == postID {
                detail?.commentCount += 1
            }
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }

    private func keepingNewerVote(_ post: FitFightFeedbackPost, startedAt: Int) -> FitFightFeedbackPost {
        guard let vote = votes[post.id], vote.clock > startedAt else { return post }
        var post = post
        post.voted = vote.voted
        post.voteCount = vote.voteCount
        return post
    }

    private func postedAfter(postID: UUID, startedAt: Int) -> [FitFightFeedbackComment] {
        (postedComments[postID] ?? []).compactMap { item in
            item.clock > startedAt ? item.comment : nil
        }
    }

    static func previewBoard() -> FeedbackStore {
        let store = FeedbackStore()
        store.posts = previewPosts
        return store
    }

    static func previewDetail() -> FeedbackStore {
        let store = previewBoard()
        store.detail = previewPosts[0]
        store.comments = previewComments
        store.canLaunchFix = true
        return store
    }

    fileprivate static let previewChartBugID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1")!

    private static let previewMetadata = FitFightFeedbackMetadata(
        appVersion: "1.0.0",
        appBuild: "183",
        backend: "staging",
        language: "fr",
        locale: "fr_FR",
        timeZone: "Europe/Paris",
        os: "iOS",
        osVersion: "26.0",
        deviceModel: "iPhone17,2",
        look: "night"
    )

    private static let previewPosts: [FitFightFeedbackPost] = [
        FitFightFeedbackPost(
            id: previewChartBugID,
            kind: "bug",
            title: "Steps chart is blank",
            body: "The daily Steps chart on a live fight stays empty after a successful sync.",
            voteCount: 8,
            commentCount: 2,
            voted: true,
            authorId: UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!,
            authorHandle: "maya_moves",
            mine: false,
            createdAt: previewDate("2026-09-03T18:00:00Z"),
            metadata: previewMetadata
        ),
        FitFightFeedbackPost(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2")!,
            kind: "feature",
            title: "Show weekly totals",
            body: "A weekly Steps total on You would make it easier to plan a fight.",
            voteCount: 5,
            commentCount: 1,
            voted: false,
            authorId: UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!,
            authorHandle: "dorian",
            mine: false,
            createdAt: previewDate("2026-09-03T12:00:00Z")
        ),
    ]

    private static let previewComments: [FitFightFeedbackComment] = [
        FitFightFeedbackComment(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3")!,
            body: "Same here after the Watch catches up.",
            authorHandle: "dorian",
            createdAt: previewDate("2026-09-03T19:00:00Z"),
            metadata: previewMetadata
        ),
        FitFightFeedbackComment(
            id: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa4")!,
            body: "Pulling to refresh did not fill the bars.",
            authorHandle: "maya_moves",
            createdAt: previewDate("2026-09-03T20:00:00Z")
        ),
    ]

    private static func previewDate(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso) ?? Date()
    }
}

@MainActor
enum RequestsScreenshot {
    static func board() -> RequestsView {
        RequestsView(store: .previewBoard())
    }

    static func detail() -> some View {
        RequestDetailView(postID: FeedbackStore.previewChartBugID, store: .previewDetail())
    }

    static func compose() -> some View {
        ComposeRequestView(store: FeedbackStore())
    }
}

enum RequestFilter: Hashable, CaseIterable {
    case top, features, bugs

    var title: String {
        switch self {
        case .top: return String(localized: "Top")
        case .features: return String(localized: "Features")
        case .bugs: return String(localized: "Bugs")
        }
    }

    var kind: String? {
        switch self {
        case .top: return nil
        case .features: return "feature"
        case .bugs: return "bug"
        }
    }
}

enum RequestsChrome {
    case sheet
    case tab
}

struct RequestsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: FeedbackStore
    var chrome: RequestsChrome
    var lockedFilter: RequestFilter?
    var filterSource: Binding<RequestFilter>?
    var onCompose: (() -> Void)?
    @State private var filter: RequestFilter
    @State private var composing = false
    @State private var openPostID: UUID?

    init(
        store: FeedbackStore,
        chrome: RequestsChrome = .sheet,
        lockedFilter: RequestFilter? = nil,
        filter: Binding<RequestFilter>? = nil,
        onCompose: (() -> Void)? = nil
    ) {
        _store = ObservedObject(wrappedValue: store)
        self.chrome = chrome
        self.lockedFilter = lockedFilter
        self.filterSource = filter
        self.onCompose = onCompose
        let start: RequestFilter
        if let lockedFilter {
            start = lockedFilter
        } else if let filter {
            start = filter.wrappedValue
        } else if chrome == .tab {
            start = .bugs
        } else {
            start = .top
        }
        _filter = State(initialValue: start)
    }

    var body: some View {
        Group {
            if staticRender {
                list
            } else {
                NavigationStack {
                    list
                        .navigationDestination(item: $openPostID) { postID in
                            RequestDetailView(
                                postID: postID,
                                store: store,
                                showsVersionBanner: chrome == .sheet
                            )
                                .toolbar(.hidden, for: .navigationBar)
                        }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .task(id: activeFilter) {
            guard !staticRender else { return }
            await store.load(session: session, kind: activeFilter.kind)
        }
        .sheet(isPresented: $composing, onDismiss: {
            guard !staticRender else { return }
            Task { await store.load(session: session, kind: activeFilter.kind) }
        }) {
            ComposeRequestView(store: store)
                .environmentObject(session)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    private var activeFilter: RequestFilter {
        lockedFilter ?? filterSource?.wrappedValue ?? filter
    }

    private var filterSelection: Binding<RequestFilter> {
        filterSource ?? $filter
    }

    private var filterItems: [RequestFilter] {
        if lockedFilter != nil { return [] }
        if chrome == .tab { return [.features, .bugs] }
        return RequestFilter.allCases
    }

    private var list: some View {
        VStack(spacing: 0) {
            if chrome == .sheet {
                VersionBanner()
                HStack {
                    Text("Bugs & requests")
                        .ffType(.title)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Button("Close") { dismiss() }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)
            }

            if !filterItems.isEmpty {
                FFSegmented(items: filterItems, selection: filterSelection) { $0.title }
                    .padding(.horizontal, theme.space.screenPadding)
                    .padding(.bottom, 12)
            }

            if let error = store.error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    .padding(.horizontal, theme.space.screenPadding)
                    .padding(.bottom, 8)
            }

            Group {
                if staticRender {
                    postsStack
                } else {
                    ScrollView {
                        postsStack
                    }
                    .refreshable {
                        await store.load(session: session, kind: activeFilter.kind)
                    }
                }
            }

            FFScreenCTA(title: String(localized: "New request")) {
                store.error = nil
                if let onCompose {
                    onCompose()
                } else {
                    composing = true
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg)
    }

    private var postsStack: some View {
        let rows = ForEach(store.posts) { post in
            RequestRow(
                post: post,
                onOpen: { openPostID = post.id },
                onVote: {
                    Task { await store.vote(session: session, postID: post.id) }
                },
                onReport: {
                    Task { await store.report(session: session, post: post) }
                },
                onHide: {
                    Task { await store.hide(session: session, authorID: post.authorId) }
                }
            )
        }
        let extras = Group {
            if store.isLoading && store.posts.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
            if store.posts.isEmpty && !store.isLoading {
                FFEmptyState(
                    systemImage: "bubble.left.and.bubble.right",
                    title: String(localized: "No requests yet"),
                    message: String(localized: "Post a bug or a feature request. Other people can upvote and comment with their username.")
                )
            }
        }
        return Group {
            if staticRender {
                VStack(alignment: .leading, spacing: 10) {
                    extras
                    rows
                }
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    extras
                    rows
                }
            }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 24)
        .fixedSize(horizontal: false, vertical: staticRender)
    }
}

private enum RequestAttachment {
    static func showsPhoto(_ media: FitFightMedia) -> Bool {
        media.kind == "photo" || ["image/jpeg", "image/png", "image/webp"].contains(media.contentType)
    }

    static func showsVideo(_ media: FitFightMedia) -> Bool {
        media.kind == "video" || media.contentType == "video/mp4" || media.contentType == "video/quicktime"
    }
}

private struct RequestMediaStack: View {
    let media: [FitFightMedia]
    var compact: Bool = false

    @Environment(\.ffTheme) private var theme

    var body: some View {
        if !media.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if compact {
                    compactRow
                } else {
                    ForEach(media) { item in
                        RequestMediaItem(media: item)
                    }
                }
            }
        }
    }

    private var compactRow: some View {
        let photos = media.filter { RequestAttachment.showsPhoto($0) && $0.url != nil }
        return HStack(spacing: 6) {
            ForEach(Array(photos.prefix(4))) { item in
                if let url = item.url {
                    RemotePhoto(url: url, kind: .photo) { theme.control }
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            if media.contains(where: { RequestAttachment.showsVideo($0) }) {
                Image(systemName: "video.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.mossText)
                    .frame(width: 44, height: 44)
                    .background(theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            let files = media.filter { !RequestAttachment.showsPhoto($0) && !RequestAttachment.showsVideo($0) }
            if !files.isEmpty {
                Image(systemName: "doc.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(theme.control, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }
}

private struct RequestMediaItem: View {
    let media: FitFightMedia
    @Environment(\.ffTheme) private var theme
    @State private var player: AVPlayer?

    var body: some View {
        if let url = media.url, RequestAttachment.showsPhoto(media) {
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
                .overlay {
                    RemotePhoto(url: url, kind: .photo) { theme.control }
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
        } else if let url = media.url, RequestAttachment.showsVideo(media) {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
                .onAppear {
                    if player == nil { player = AVPlayer(url: url) }
                }
                .onDisappear {
                    player?.pause()
                    player = nil
                }
        } else if let url = media.url {
            Link(destination: url) {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(theme.mossText)
                    Text(media.originalFilename)
                        .ffType(.caption)
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(
                    theme.card,
                    in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                )
                .ffBorder(theme.hairline, radius: theme.radius.field)
            }
        }
    }

    private var ratio: CGFloat {
        CGFloat(max(media.width, 1)) / CGFloat(max(media.height, 1))
    }
}

private struct RequestRow: View {
    let post: FitFightFeedbackPost
    let onOpen: () -> Void
    let onVote: () -> Void
    let onReport: () -> Void
    let onHide: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: 10) {
                    Color.clear
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            FFTag(
                                post.kind == "bug" ? String(localized: "Bug") : String(localized: "Feature"),
                                tone: post.kind == "bug" ? .ember : .moss
                            )
                            Spacer(minLength: 0)
                            if !post.mine {
                                RequestPostMenu(onReport: onReport, onHide: onHide)
                            }
                            Text(post.createdAt, format: .relative(presentation: .named))
                                .ffType(.caption)
                                .foregroundStyle(theme.textFaint)
                        }
                        Text(post.title)
                            .ffType(.rowTitle)
                            .foregroundStyle(theme.text)
                            .multilineTextAlignment(.leading)
                        Text(post.body)
                            .ffType(.caption)
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        RequestMediaStack(media: post.media, compact: true)
                        Text(
                            String(
                                localized: "feedback.meta",
                                defaultValue: "@\(post.authorHandle) · \(post.commentCount) comments"
                            )
                        )
                        .ffType(.micro)
                        .foregroundStyle(theme.textFaint)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
                .ffBorder(theme.hairline, radius: theme.radius.card)
            }
            .buttonStyle(FFHapticPlainStyle())

            Button(action: onVote) {
                VStack(spacing: 2) {
                    Image(systemName: post.voted ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 22, weight: .bold))
                    Text(verbatim: "\(post.voteCount)")
                        .ffType(.micro)
                        .fontWeight(.heavy)
                }
                .foregroundStyle(post.voted ? theme.mossText : theme.textSecondary)
                .frame(width: 44)
                .padding(.top, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(FFPressStyle(scale: 0.92))
            .accessibilityLabel(String(localized: "Upvote"))
            .padding(.leading, 14)
            .padding(.top, 14)
        }
    }
}

private struct RequestDetailView: View {
    let postID: UUID
    @ObservedObject var store: FeedbackStore
    var showsVersionBanner: Bool = true
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var comment = ""
    @State private var launchedAgentURL: URL?
    @FocusState private var commentFocused: Bool

    private var post: FitFightFeedbackPost? {
        store.detail?.id == postID ? store.detail : store.posts.first(where: { $0.id == postID })
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsVersionBanner {
                VersionBanner()
            }
            HStack(alignment: .top, spacing: 10) {
                FFNavDetail(
                    title: post?.title ?? String(localized: "Request"),
                    subtitle: post.map { "@\($0.authorHandle)" },
                    onBack: { dismiss() }
                )
                if let post, !post.mine {
                    RequestPostMenu(
                        onReport: {
                            Task { await store.report(session: session, post: post) }
                        },
                        onHide: {
                            Task {
                                await store.hide(session: session, authorID: post.authorId)
                                dismiss()
                            }
                        }
                    )
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 12)

            if let error = store.error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    .padding(.horizontal, theme.space.screenPadding)
                    .padding(.top, 8)
            }

            Group {
                if staticRender {
                    detailStack
                } else {
                    ScrollView {
                        detailStack
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }

            HStack(spacing: 10) {
                if staticRender {
                    Text("Add a comment")
                        .ffType(.body)
                        .foregroundStyle(theme.textFaint)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            theme.card,
                            in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                        )
                        .ffBorder(theme.line, radius: theme.radius.field)
                } else {
                    TextField(String(localized: "Add a comment"), text: $comment, axis: .vertical)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1...4)
                        .focused($commentFocused)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            theme.card,
                            in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                        )
                        .ffBorder(commentFocused ? theme.mossEdge : theme.line, radius: theme.radius.field)
                }
                FFButton(
                    title: String(localized: "Post"),
                    enabled: canComment,
                    action: {
                        Task { await sendComment() }
                    }
                )
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)
        }
        .background(theme.bg.ignoresSafeArea())
        .task {
            guard !staticRender else { return }
            await store.loadDetail(session: session, postID: postID)
        }
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let post {
                HStack(spacing: 8) {
                    FFTag(
                        post.kind == "bug" ? String(localized: "Bug") : String(localized: "Feature"),
                        tone: post.kind == "bug" ? .ember : .moss
                    )
                    Button(action: {
                        Task { await store.vote(session: session, postID: post.id) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: post.voted ? "arrow.up.circle.fill" : "arrow.up.circle")
                            Text(
                                String(
                                    localized: "feedback.votes",
                                    defaultValue: "\(post.voteCount) upvotes"
                                )
                            )
                        }
                        .ffType(.label)
                        .foregroundStyle(post.voted ? theme.mossText : theme.textSecondary)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    Spacer()
                }

                Text(post.body)
                    .ffType(.body)
                    .foregroundStyle(theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                RequestMediaStack(media: post.media)

                if store.canLaunchFix {
                    if launchedAgentURL != nil {
                        FFNotice(
                            text: String(localized: "Cursor is on it. A pull request will show up when it’s done."),
                            tone: .moss,
                            systemImage: "sparkles",
                            actionTitle: String(localized: "Open"),
                            action: {
                                if let launchedAgentURL {
                                    openURL(launchedAgentURL)
                                }
                            }
                        )
                    }
                    FFButton(
                        title: store.isLaunchingFix
                            ? String(localized: "Sending…")
                            : String(localized: "Send to Cursor"),
                        kind: .secondary,
                        enabled: !store.isLaunchingFix && !store.isSaving,
                        fullWidth: true,
                        action: {
                            Task { await sendToCursor() }
                        }
                    )
                }

                FFSectionHeader(title: String(localized: "Comments"))
                    .padding(.top, 8)

                if store.isLoading && store.comments.isEmpty {
                    ProgressView()
                } else if store.comments.isEmpty {
                    Text("No comments yet.")
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }

                ForEach(store.comments) { item in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: "@\(item.authorHandle)")
                                .ffType(.label)
                                .foregroundStyle(theme.mossText)
                            Spacer()
                            Text(item.createdAt, format: .relative(presentation: .named))
                                .ffType(.caption)
                                .foregroundStyle(theme.textFaint)
                        }
                        Text(item.body)
                            .ffType(.body)
                            .foregroundStyle(theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .background(
                        theme.card,
                        in: RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous)
                    )
                    .ffBorder(theme.hairline, radius: theme.radius.field)
                }
            }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .fixedSize(horizontal: false, vertical: staticRender)
    }

    private var canComment: Bool {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 500 && !store.isSaving
    }

    private func sendComment() async {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard await store.comment(session: session, postID: postID, body: trimmed) else { return }
        comment = ""
        commentFocused = false
    }

    private func sendToCursor() async {
        guard let url = await store.launchFix(session: session, postID: postID) else { return }
        launchedAgentURL = url
    }
}

private struct RequestPostMenu: View {
    let onReport: () -> Void
    let onHide: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Menu {
            Button(String(localized: "Report")) {
                onReport()
            }
            Button(String(localized: "Hide this person"), role: .destructive) {
                onHide()
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.textFaint)
                .frame(width: 32, height: 32)
        }
        .buttonStyle(FFHapticPlainStyle())
    }
}

struct ComposeRequestView: View {
    @ObservedObject var store: FeedbackStore
    var heading: String = String(localized: "New request")
    var embedded: Bool = false
    var isActive: Bool = true
    var onPosted: ((RequestFilter) -> Void)? = nil
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ComposeKind = .bug
    @State private var title = ""
    @State private var details = ""
    @State private var mediaItems: [PhotosPickerItem] = []
    @State private var isLoadingMedia = false
    @State private var images: [UIImage] = []
    @State private var videos: [URL] = []
    @State private var files: [URL] = []
    @State private var showingFileImporter = false
    @FocusState private var titleFocused: Bool
    @FocusState private var detailsFocused: Bool

    private enum ComposeKind: Hashable, CaseIterable {
        case bug, feature

        var title: String {
            switch self {
            case .bug: return String(localized: "Bug")
            case .feature: return String(localized: "Feature")
            }
        }

        var value: String {
            switch self {
            case .bug: return "bug"
            case .feature: return "feature"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !embedded {
                VersionBanner()
            }
            HStack {
                Text(heading)
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                if !embedded {
                    Button("Close") { dismiss() }
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            Group {
                if staticRender {
                    composeStack
                } else {
                    ScrollView {
                        composeStack
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }

            FFScreenCTA(
                title: store.isSaving ? String(localized: "Posting…") : String(localized: "Post"),
                enabled: canPost,
                busy: store.isSaving
            ) {
                Task { await submit() }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        .onChange(of: isActive) { _, active in
            if !active {
                titleFocused = false
                detailsFocused = false
            }
        }
        .onChange(of: mediaItems) { _, items in
            Task { await loadPickedMedia(items) }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            loadPickedFiles(result)
        }
    }

    private var composeStack: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let error = store.error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
            }

            Text("Posted with your username. Signed-in people can see it, upvote, and comment.")
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)

            FFSegmented(items: ComposeKind.allCases, selection: $kind) { $0.title }

            FFField(
                label: String(localized: "Title"),
                state: titleFocused ? .focused : .normal,
                counter: "\(title.count)/80"
            ) {
                if staticRender {
                    Text("Short and specific")
                        .foregroundStyle(theme.textFaint)
                } else {
                    TextField(String(localized: "Short and specific"), text: $title)
                        .focused($titleFocused)
                        .onChange(of: title) { _, value in
                            if value.count > 80 { title = String(value.prefix(80)) }
                        }
                }
            }

            FFField(
                label: String(localized: "Details"),
                state: detailsFocused ? .focused : .normal,
                help: String(localized: "What happened, or what you want. Be specific."),
                counter: "\(details.count)/2000",
                minHeight: 120
            ) {
                if staticRender {
                    Text("Describe it")
                        .foregroundStyle(theme.textFaint)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                } else {
                    TextField(String(localized: "Describe it"), text: $details, axis: .vertical)
                        .focused($detailsFocused)
                        .lineLimit(6...12)
                        .onChange(of: details) { _, value in
                            if value.count > 2000 { details = String(value.prefix(2000)) }
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
                                .onTapGesture { images.remove(at: index) }
                        }
                    }
                }
            }
            ForEach(Array(videos.enumerated()), id: \.offset) { index, _ in
                HStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .foregroundStyle(theme.mossText)
                    Text(String(localized: "Video"))
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                }
                .onTapGesture { removeVideo(at: index) }
            }
            ForEach(Array(files.enumerated()), id: \.offset) { index, url in
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(theme.mossText)
                    Text(url.lastPathComponent)
                        .ffType(.caption)
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .onTapGesture { removeFile(at: index) }
            }

            Text("Add a photo, a video, or any file.")
                .ffType(.caption)
                .foregroundStyle(theme.textSecondary)

            HStack(spacing: 16) {
                PhotosPicker(
                    selection: $mediaItems,
                    maxSelectionCount: max(1, remainingSlots),
                    matching: .any(of: [.images, .videos])
                ) {
                    Label(String(localized: "Media"), systemImage: "photo.on.rectangle.angled")
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(remainingSlots == 0 || isLoadingMedia || store.isSaving)
                Button {
                    showingFileImporter = true
                } label: {
                    Label(String(localized: "File"), systemImage: "paperclip")
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(remainingSlots == 0 || isLoadingMedia || store.isSaving)
                if isLoadingMedia { ProgressView().tint(theme.mossText) }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.bottom, 24)
        .fixedSize(horizontal: false, vertical: staticRender)
    }

    private var remainingSlots: Int {
        max(0, 8 - images.count - videos.count - files.count)
    }

    private var canPost: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.count >= 1
            && trimmedDetails.count >= 1
            && !store.isSaving
            && !isLoadingMedia
    }

    private func loadPickedMedia(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isLoadingMedia = true
        defer { isLoadingMedia = false; mediaItems = [] }
        var remaining = remainingSlots
        do {
            for item in items {
                guard remaining > 0 else { break }
                if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                    guard let picked = try await item.loadTransferable(type: PickedVideo.self) else {
                        throw MediaUploader.UploadError.invalidVideo
                    }
                    videos.append(picked.url)
                } else {
                    guard let data = try await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        throw MediaUploader.UploadError.invalidImage
                    }
                    images.append(image)
                }
                remaining -= 1
            }
            store.error = nil
        } catch {
            store.error = error.localizedDescription
        }
    }

    private func loadPickedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            store.error = error.localizedDescription
        case .success(let urls):
            var remaining = remainingSlots
            do {
                for url in urls {
                    guard remaining > 0 else { break }
                    let dest = try copyImportedFile(url)
                    let type = UTType(filenameExtension: dest.pathExtension)
                    if type?.conforms(to: .image) == true, let image = UIImage(contentsOfFile: dest.path) {
                        images.append(image)
                        try? FileManager.default.removeItem(at: dest)
                    } else if type?.conforms(to: .movie) == true {
                        videos.append(dest)
                    } else {
                        files.append(dest)
                    }
                    remaining -= 1
                }
                store.error = nil
            } catch {
                store.error = error.localizedDescription
            }
        }
    }

    private func copyImportedFile(_ url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let ext = url.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }

    private func removeVideo(at index: Int) {
        let url = videos.remove(at: index)
        if url.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func removeFile(at index: Int) {
        let url = files.remove(at: index)
        if url.path.hasPrefix(FileManager.default.temporaryDirectory.path) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func submit() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if await store.submit(
            session: session,
            kind: kind.value,
            title: trimmedTitle,
            body: trimmedDetails,
            images: images,
            videos: videos,
            files: files
        ) {
            title = ""
            details = ""
            images = []
            videos = []
            files = []
            if let onPosted {
                onPosted(kind == .feature ? .features : .bugs)
            } else {
                dismiss()
            }
        }
    }
}

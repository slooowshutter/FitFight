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
    @Published var canDelete = false
    @Published var canArchive = false
    @Published var isArchiving = false
    @Published var isDeleting = false
    @Published var error: String?
    @Published var openDetailID: UUID?
    @Published var menuAction: RequestMenuAction?

    private let api = FitFightAPI()
    private var listLoad = 0
    private var detailLoad = 0
    private var listStatus = "open"
    private var listSort = "votes"
    private var archiveClock = 0
    private var archives: [UUID: (clock: Int, state: FitFightFeedbackArchive)] = [:]
    private var deletedPostIDs: Set<UUID> = []
    private var voting: Set<UUID> = []
    private var voteClock = 0
    private var votes: [UUID: (clock: Int, voted: Bool, voteCount: Int)] = [:]
    private var commentClock = 0
    private var postedComments: [UUID: [(clock: Int, comment: FitFightFeedbackComment)]] = [:]
    private var commentsFor: UUID?

    func load(session: SessionStore, kind: String?, status: String = "open", sort: String = "votes") async {
        listStatus = status
        listSort = sort
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            posts = Self.previewPosts.filter { (kind == nil || $0.kind == kind) && $0.archived == (status == "archived") }
            sortPosts()
            return
        }
        #endif
        listLoad += 1
        let load = listLoad
        let archiveStartedAt = archiveClock
        let voteStartedAt = voteClock
        let commentStartedAt = commentClock
        isLoading = true
        defer {
            if load == listLoad { isLoading = false }
        }
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.listFeedback(kind: kind, status: status, sort: sort, accessToken: token)
            guard load == listLoad else { return }
            canArchive = result.canArchive
            self.posts = result.posts.filter { !deletedPostIDs.contains($0.id) }.map { fetched in
                var post = keepingNewerArchive(keepingNewerVote(fetched, startedAt: voteStartedAt), startedAt: archiveStartedAt)
                if !postedAfter(postID: post.id, startedAt: commentStartedAt).isEmpty,
                   let local = self.posts.first(where: { $0.id == post.id }) {
                    post.commentCount = max(post.commentCount, local.commentCount)
                }
                return post
            }.filter { $0.archived == (status == "archived") }
            sortPosts()
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
        canDelete = false
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
        let archiveStartedAt = archiveClock
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
            guard load == detailLoad, !deletedPostIDs.contains(postID) else { return }
            let extras = postedAfter(postID: result.post.id, startedAt: commentStartedAt)
            var comments = result.comments
            for extra in extras where !comments.contains(where: { $0.id == extra.id }) {
                comments.append(extra)
            }
            var post = keepingNewerArchive(keepingNewerVote(result.post, startedAt: voteStartedAt), startedAt: archiveStartedAt)
            post.commentCount += comments.count - result.comments.count
            detail = post
            self.comments = comments
            commentsFor = post.id
            canLaunchFix = result.canLaunchFix
            canDelete = result.canDelete
            canArchive = result.canArchive
            RemoteImageLoader.shared.prefetch(
                post.media.compactMap { media in
                    RequestAttachment.showsPhoto(media) ? media.url : nil
                },
                kind: .photo
            )
            if let index = posts.firstIndex(where: { $0.id == post.id }) {
                posts[index] = post
                posts.removeAll { $0.archived != (listStatus == "archived") }
            }
            error = nil
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard load == detailLoad, !deletedPostIDs.contains(postID) else { return }
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
                sortPosts()
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
        guard !isLaunchingFix else { return nil }
        isLaunchingFix = true
        defer { isLaunchingFix = false }
        do {
            let token = try await session.freshAccessToken()
            let launched = try await api.launchFeedbackFix(
                postID: postID,
                metadata: .current(),
                accessToken: token
            )
            await loadDetail(session: session, postID: postID)
            return launched.agentURL
        } catch {
            await loadDetail(session: session, postID: postID)
            self.error = error.localizedDescription
            return nil
        }
    }

    func delete(session: SessionStore, postID: UUID) async -> Bool {
        guard !isDeleting && !isArchiving else { return false }
        isDeleting = true
        let detailStartedAt = detailLoad
        defer { isDeleting = false }
        do {
            let token = try await session.freshAccessToken()
            try await api.deleteFeedbackPost(postID: postID, accessToken: token)
            // Ignore stale copies of this request without cancelling reads for another screen.
            deletedPostIDs.insert(postID)
            posts.removeAll { $0.id == postID }
            if detail?.id == postID {
                detail = nil
            }
            if commentsFor == postID {
                comments = []
                commentsFor = nil
                canDelete = false
                canLaunchFix = false
                error = nil
            }
            archives.removeValue(forKey: postID)
            votes.removeValue(forKey: postID)
            postedComments.removeValue(forKey: postID)
            return true
        } catch {
            if detailLoad == detailStartedAt || commentsFor == postID {
                self.error = error.localizedDescription
            }
            return false
        }
    }

    func archive(session: SessionStore, postID: UUID, archived: Bool, reason: String?) async -> Bool {
        guard !isArchiving && !isDeleting else { return false }
        isArchiving = true
        let detailStartedAt = detailLoad
        defer { isArchiving = false }
        do {
            let token = try await session.freshAccessToken()
            let state = try await api.archiveFeedbackPost(postID: postID, archived: archived, reason: reason, accessToken: token)
            archiveClock += 1
            archives[postID] = (archiveClock, state)
            if let index = posts.firstIndex(where: { $0.id == postID }) {
                posts[index].archived = state.archived
                posts[index].archiveReason = state.archiveReason
                posts.removeAll { $0.archived != (listStatus == "archived") }
            }
            if detail?.id == postID {
                detail?.archived = state.archived
                detail?.archiveReason = state.archiveReason
            }
            if detailLoad == detailStartedAt || commentsFor == postID { error = nil }
            return true
        } catch {
            if detailLoad == detailStartedAt || commentsFor == postID { self.error = error.localizedDescription }
            return false
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

    private func keepingNewerArchive(_ post: FitFightFeedbackPost, startedAt: Int) -> FitFightFeedbackPost {
        guard let archive = archives[post.id], archive.clock > startedAt else { return post }
        var post = post
        post.archived = archive.state.archived
        post.archiveReason = archive.state.archiveReason
        return post
    }

    private func sortPosts() {
        posts.sort { left, right in
            if listSort == "votes", left.voteCount != right.voteCount { return left.voteCount > right.voteCount }
            if left.createdAt != right.createdAt {
                return listSort == "oldest" ? left.createdAt < right.createdAt : left.createdAt > right.createdAt
            }
            return left.id.uuidString < right.id.uuidString
        }
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
        RequestsView(store: .previewBoard(), filter: .constant(RequestFilter()))
    }

    static func detail() -> some View {
        RequestDetailView(postID: FeedbackStore.previewChartBugID, store: .previewDetail())
    }

    static func compose() -> some View {
        ComposeRequestView(store: FeedbackStore())
    }

    static func filters() -> some View {
        RequestFiltersSheet(draft: RequestFilter(), onApply: { _ in })
            .frame(height: 560)
    }
}

struct RequestFilter: Hashable {
    enum Kind: String, CaseIterable {
        case all, feature, bug

        var title: String {
            switch self {
            case .all: return String(appLocalized: "All")
            case .feature: return String(appLocalized: "Features")
            case .bug: return String(appLocalized: "Bugs")
            }
        }
    }

    enum Status: String, CaseIterable {
        case open, archived

        var title: String {
            switch self {
            case .open: return String(appLocalized: "feedback.open", defaultValue: "Open")
            case .archived: return String(appLocalized: "Archived")
            }
        }
    }

    enum Sort: String, CaseIterable {
        case votes, newest, oldest

        var title: String {
            switch self {
            case .votes: return String(appLocalized: "Most upvoted")
            case .newest: return String(appLocalized: "Newest first")
            case .oldest: return String(appLocalized: "Oldest first")
            }
        }
    }

    var type: Kind = .all
    var status: Status = .open
    var sort: Sort = .votes
    var kind: String? { type == .all ? nil : type.rawValue }
}

private struct RequestFiltersSheet: View {
    @State var draft: RequestFilter
    let onApply: (RequestFilter) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender

    var body: some View {
        VStack(spacing: 16) {
            FFSheetHeader(title: String(appLocalized: "Sort & filter")) { dismiss() }
            if staticRender {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .top) {
                        choices.fixedSize(horizontal: false, vertical: true)
                    }
                    .clipped()
            } else {
                ScrollView { choices }
            }
            FFScreenCTA(title: String(appLocalized: "Show feedback")) {
                onApply(draft)
                dismiss()
            }
            Button(String(appLocalized: "Reset to defaults")) { draft = RequestFilter() }
                .ffType(.label).foregroundStyle(theme.textSecondary)
                .frame(minHeight: 44)
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 16) {
            FFSection(title: String(appLocalized: "Status"), extraTop: false) {
                FFSegmented(items: RequestFilter.Status.allCases, selection: $draft.status) { $0.title }
            }
            FFSection(title: String(appLocalized: "Type"), extraTop: false) {
                FFSegmented(items: RequestFilter.Kind.allCases, selection: $draft.type) { $0.title }
            }
            FFSection(title: String(appLocalized: "Sort by"), extraTop: false) {
                FFGroupedRows {
                    ForEach(RequestFilter.Sort.allCases, id: \.self) { sort in
                        if sort != .votes { FFDivider() }
                        FFGroupedRow(title: sort.title, trailing: AnyView(
                            Image(systemName: "checkmark")
                                .foregroundStyle(theme.mossText)
                                .opacity(draft.sort == sort ? 1 : 0)
                        )) { draft.sort = sort }
                        .accessibilityAddTraits(draft.sort == sort ? .isSelected : [])
                    }
                }
            }
        }
    }
}

private struct RequestArchiveSheet: View {
    let post: FitFightFeedbackPost
    @ObservedObject var store: FeedbackStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.ffTheme) private var theme
    @State private var reason = ""
    @FocusState private var reasonFocused: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text(post.archived ? String(appLocalized: "Reopen feedback") : String(appLocalized: "Archive feedback"))
                    .ffType(.title)
                Spacer()
                Button(String(appLocalized: "Cancel")) { dismiss() }
                    .ffType(.label).foregroundStyle(theme.mossText)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(store.isArchiving)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(post.title).ffType(.heading)
                    Text(post.archived
                         ? String(appLocalized: "Reopen this feedback with its existing votes and discussion. People can vote and comment again.")
                         : String(appLocalized: "Keep this feedback, its votes, and its discussion in Archived. New votes and comments will close. You can reopen it later."))
                        .ffType(.body).foregroundStyle(theme.textSecondary)
                    if !post.archived {
                        TextField(String(appLocalized: "Public reason (optional)"), text: $reason, axis: .vertical)
                            .focused($reasonFocused)
                            .ffType(.body)
                            .lineLimit(3...6)
                            .padding(14)
                            .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.field))
                            .ffBorder(theme.line, radius: theme.radius.field)
                            .disabled(store.isArchiving)
                    }
                    if let error = store.error {
                        FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    }
                }
                .ffKeyboardDismissOnBackgroundTap()
            }
            .scrollDismissesKeyboard(.interactively)
            FFScreenCTA(
                title: post.archived ? String(appLocalized: "Reopen feedback") : String(appLocalized: "Archive feedback"),
                enabled: reason.trimmingCharacters(in: .whitespacesAndNewlines).count <= 280 && !store.isArchiving && !store.isDeleting,
                busy: store.isArchiving
            ) {
                Task {
                    if await store.archive(session: session, postID: post.id, archived: !post.archived,
                                           reason: reason.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        dismiss()
                    }
                }
            }
        }
        .foregroundStyle(theme.text)
        .ffKeyboardDismissOnBackgroundTap()
        .padding(.horizontal, theme.space.screenPadding)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .interactiveDismissDisabled(store.isArchiving)
    }
}

/// The Feedback tab's board. The tab owns the title and the compose sheet.
struct RequestsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject var store: FeedbackStore
    @Binding var filter: RequestFilter
    @State private var openPostID: UUID?
    @State private var showingFilters = false
    @State private var deletingPost: FitFightFeedbackPost?
    @State private var archivingPost: FitFightFeedbackPost?

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
                                store: store
                            )
                                .toolbar(.hidden, for: .navigationBar)
                        }
                }
                .toolbar(.hidden, for: .navigationBar)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .task(id: filter) {
            guard !staticRender else { return }
            await store.load(session: session, kind: filter.kind, status: filter.status.rawValue, sort: filter.sort.rawValue)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !staticRender {
                Task { await store.load(session: session, kind: filter.kind, status: filter.status.rawValue, sort: filter.sort.rawValue) }
            }
        }
        .sheet(isPresented: $showingFilters) {
            RequestFiltersSheet(draft: filter) { filter = $0 }
                .fitFightTheme(theme)
                .presentationBackground(theme.overlay)
                .presentationCornerRadius(theme.radius.shell)
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(560), .large])
        }
        .sheet(item: $archivingPost) { post in
            RequestArchiveSheet(post: post, store: store)
                .fitFightTheme(theme)
                .presentationBackground(theme.overlay)
                .presentationCornerRadius(theme.radius.shell)
                .presentationDragIndicator(.visible)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog(String(appLocalized: "Delete request?"), isPresented: Binding(
            get: { deletingPost != nil },
            set: { if !$0 { deletingPost = nil } }
        ), titleVisibility: .visible, presenting: deletingPost) { post in
            Button(String(appLocalized: "Delete"), role: .destructive) {
                Task { _ = await store.delete(session: session, postID: post.id) }
            }
            Button(String(appLocalized: "Cancel"), role: .cancel) {}
        } message: { _ in
            Text("This removes the request, comments, and votes for everyone. This cannot be undone.")
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text(String(appLocalized: "feedback.post-count", defaultValue: "\(store.posts.count) posts"))
                    .ffType(.label)
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Button { showingFilters = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.mossText)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FFHapticPlainStyle())
                // Match the header action's column without shrinking the label's tap area.
                .frame(width: 36)
                .accessibilityLabel(String(appLocalized: "Filter feedback"))
                .accessibilityValue("\(filter.status.title), \(filter.type.title), \(filter.sort.title)")
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, 12)

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
                        await store.load(session: session, kind: filter.kind, status: filter.status.rawValue, sort: filter.sort.rawValue)
                    }
                }
            }
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
                },
                onDelete: post.mine || store.canArchive ? { deletingPost = post } : nil,
                onArchive: store.canArchive ? { archivingPost = post } : nil
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
                    title: filter == RequestFilter() ? String(appLocalized: "No requests yet") : String(appLocalized: "No matching feedback"),
                    message: filter == RequestFilter()
                        ? String(appLocalized: "Post a bug or a feature request. Other people can upvote and comment with their username.")
                        : String(appLocalized: "Try changing the filters to see other feedback.")
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
                        MediaAttachment(media: item)
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

/// A Feed or Feedback attachment: photo, inline video, or a file link.
/// Photos open the viewer when `onOpenPhoto` is set.
struct MediaAttachment: View {
    let media: FitFightMedia
    var onOpenPhoto: ((URL) -> Void)? = nil
    @Environment(\.ffTheme) private var theme
    @State private var player: AVPlayer?

    var body: some View {
        if let url = media.url, RequestAttachment.showsPhoto(media) {
            if let onOpenPhoto {
                Button { onOpenPhoto(url) } label: { photo(url) }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityLabel(String(appLocalized: "View photo"))
            } else {
                photo(url)
            }
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

    private func photo(_ url: URL) -> some View {
        Color.clear
            .aspectRatio(CGFloat(max(media.width, 1)) / CGFloat(max(media.height, 1)), contentMode: .fit)
            .frame(maxWidth: .infinity)
            .fixedSize(horizontal: false, vertical: true)
            .overlay {
                RemotePhoto(url: url, kind: .photo) { theme.control }
            }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: theme.radius.field, style: .continuous))
    }
}

private struct RequestRow: View {
    let post: FitFightFeedbackPost
    let onOpen: () -> Void
    let onVote: () -> Void
    let onReport: () -> Void
    let onHide: () -> Void
    var onDelete: (() -> Void)? = nil
    var onArchive: (() -> Void)? = nil
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button(action: onVote) {
                VStack(spacing: 2) {
                    Image(systemName: post.voted ? "arrow.up.circle.fill" : "arrow.up.circle")
                        .font(.system(size: 22, weight: .bold))
                    Text(verbatim: "\(post.voteCount)").ffType(.micro).fontWeight(.heavy)
                }
                .foregroundStyle(post.voted ? theme.mossText : theme.textSecondary)
                .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(FFPressStyle(scale: 0.92))
            .accessibilityLabel(String(appLocalized: "Upvote"))
            .disabled(post.archived)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    FFTag(post.kind == "bug" ? String(appLocalized: "Bug") : String(appLocalized: "Feature"), tone: post.kind == "bug" ? .ember : .moss)
                    Spacer(minLength: 0)
                    if !post.mine || onDelete != nil || onArchive != nil {
                        RequestPostMenu(canReport: !post.mine, onReport: onReport, onHide: onHide,
                                        onDelete: onDelete, onArchive: onArchive, archived: post.archived)
                    }
                    Text(post.createdAt, format: .relative(presentation: .named)).ffType(.caption).foregroundStyle(theme.textFaint)
                }
                Button(action: onOpen) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(post.title).ffType(.rowTitle).foregroundStyle(theme.text)
                        Text(post.body).ffType(.caption).foregroundStyle(theme.textSecondary).lineLimit(2)
                        RequestMediaStack(media: post.media, compact: true)
                    }.multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(FFHapticPlainStyle())
                HStack(spacing: 4) {
                    ProfileIdentityLink(userID: post.authorId, source: "feedback") {
                        Text(verbatim: "@\(post.authorHandle)")
                    }
                    Text(verbatim: "·")
                    Button(action: onOpen) {
                        Text(post.commentCount == 1
                             ? String(appLocalized: "1 comment")
                             : String(appLocalized: "feedback.comment-count", defaultValue: "\(post.commentCount) comments"))
                            .frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
                .ffType(.micro).foregroundStyle(theme.textFaint)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(theme.card, in: RoundedRectangle(cornerRadius: theme.radius.card, style: .continuous))
        .ffBorder(theme.hairline, radius: theme.radius.card)
    }
}

private struct RequestDetailView: View {
    let postID: UUID
    @ObservedObject var store: FeedbackStore
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var model: AppModel
    @Environment(\.ffTheme) private var theme
    @Environment(\.ffStaticRender) private var staticRender
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var comment = ""
    @State private var launchedAgentURL: URL?
    @State private var confirmingDeletion = false
    @State private var showingArchive = false
    @FocusState private var commentFocused: Bool

    private var post: FitFightFeedbackPost? {
        store.detail?.id == postID ? store.detail : store.posts.first(where: { $0.id == postID })
    }

    var body: some View {
        VStack(spacing: 0) {
            FFNavDetail(
                title: post?.title ?? String(appLocalized: "Request"),
                onBack: { dismiss() }
            )
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
                    .refreshable { await store.loadDetail(session: session, postID: postID) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ffKeyboardDismissOnBackgroundTap()
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if post?.archived != true {
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
                        TextField(String(appLocalized: "Add a comment"), text: $comment, axis: .vertical)
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
                        title: String(appLocalized: "Post"),
                        enabled: canComment,
                        action: {
                            Task { await sendComment() }
                        }
                    )
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.vertical, 12)
                .background(theme.bg)
                // NOTE: pushed NavigationStack screens do not inherit the root tab bar's safe-area inset.
                .padding(.bottom, model.tabBarHeight)
            }
        }
        .background(theme.bg.ignoresSafeArea())
        .sheet(isPresented: $showingArchive) {
            if let post {
                RequestArchiveSheet(post: post, store: store)
                    .fitFightTheme(theme)
                    .presentationBackground(theme.overlay)
                    .presentationCornerRadius(theme.radius.shell)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
            }
        }
        .confirmationDialog(String(appLocalized: "Delete request?"), isPresented: $confirmingDeletion, titleVisibility: .visible) {
            Button(String(appLocalized: "Delete"), role: .destructive) {
                Task {
                    if await store.delete(session: session, postID: postID) {
                        dismiss()
                    }
                }
            }
            Button(String(appLocalized: "Cancel"), role: .cancel) {}
        } message: {
            Text("This removes the request, comments, and votes for everyone. This cannot be undone.")
        }
        .task {
            guard !staticRender else { return }
            await store.loadDetail(session: session, postID: postID)
        }
        .onAppear { store.openDetailID = postID }
        .onDisappear {
            if store.openDetailID == postID { store.openDetailID = nil }
        }
        // The post menu lives in the Feedback hub bar; it asks this screen to act.
        .onChange(of: store.menuAction) { _, action in
            guard let action, let post else { return }
            store.menuAction = nil
            switch action {
            case .hide:
                Task {
                    await store.hide(session: session, authorID: post.authorId)
                    dismiss()
                }
            case .delete: confirmingDeletion = true
            case .archive: showingArchive = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !staticRender {
                Task { await store.loadDetail(session: session, postID: postID) }
            }
        }
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let post {
                HStack(spacing: 8) {
                    FFTag(
                        post.kind == "bug" ? String(appLocalized: "Bug") : String(appLocalized: "Feature"),
                        tone: post.kind == "bug" ? .ember : .moss
                    )
                    Button(action: {
                        Task { await store.vote(session: session, postID: post.id) }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: post.voted ? "arrow.up.circle.fill" : "arrow.up.circle")
                            Text(
                                String(
                                    appLocalized: "feedback.votes",
                                    defaultValue: "\(post.voteCount) upvotes"
                                )
                            )
                        }
                        .ffType(.label)
                        .foregroundStyle(post.voted ? theme.mossText : theme.textSecondary)
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(post.archived)
                    Spacer()
                }

                if post.archived {
                    FFNotice(
                        text: String(appLocalized: "This feedback is archived. Votes and comments are closed."),
                        tone: .neutral,
                        systemImage: "archivebox"
                    )
                    if let reason = post.archiveReason {
                        Text(reason).ffType(.body).foregroundStyle(theme.textSecondary)
                    }
                }

                ProfileIdentityLink(userID: post.authorId, source: "feedback") {
                    Text(verbatim: "@\(post.authorHandle)").ffType(.label).foregroundStyle(theme.mossText)
                }

                Text(post.body)
                    .ffType(.body)
                    .foregroundStyle(theme.text)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                RequestMediaStack(media: post.media)

                if store.canLaunchFix && !post.archived {
                    if launchedAgentURL != nil {
                        FFNotice(
                            text: String(appLocalized: "Cursor is on it. A pull request will show up when it’s done."),
                            tone: .moss,
                            systemImage: "sparkles",
                            actionTitle: String(appLocalized: "Open"),
                            action: {
                                if let launchedAgentURL {
                                    openURL(launchedAgentURL)
                                }
                            }
                        )
                    }
                    FFButton(
                        title: store.isLaunchingFix
                            ? String(appLocalized: "Sending…")
                            : String(appLocalized: "Send to Cursor"),
                        kind: .secondary,
                        enabled: !store.isLaunchingFix && !store.isSaving && !store.isDeleting,
                        fullWidth: true,
                        action: {
                            Task { await sendToCursor() }
                        }
                    )
                }

                FFSectionHeader(title: String(appLocalized: "Comments"))
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
                            ProfileIdentityLink(userID: item.authorId, source: "feedback") {
                                Text(verbatim: "@\(item.authorHandle)")
                                    .ffType(.label).foregroundStyle(theme.mossText)
                            }
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
        .ffKeyboardDismissOnBackgroundTap()
    }

    private var canComment: Bool {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 2 && trimmed.count <= 500 && post?.archived != true && !store.isSaving && !store.isDeleting && !store.isArchiving
    }

    private func sendComment() async {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard await store.comment(session: session, postID: postID, body: trimmed) else { return }
        comment = ""
        commentFocused = false
        await store.loadDetail(session: session, postID: postID)
    }

    private func sendToCursor() async {
        guard let url = await store.launchFix(session: session, postID: postID) else { return }
        launchedAgentURL = url
    }
}

enum RequestMenuAction {
    case hide, delete, archive
}

struct RequestPostMenu: View {
    var canReport = true
    let onReport: () -> Void
    let onHide: () -> Void
    var onDelete: (() -> Void)? = nil
    var onArchive: (() -> Void)? = nil
    var archived = false
    @Environment(\.ffTheme) private var theme

    var body: some View {
        Menu {
            if canReport {
                Button(String(appLocalized: "Report")) {
                    onReport()
                }
                Button(String(appLocalized: "Hide this person"), role: .destructive) {
                    onHide()
                }
            }
            if let onArchive {
                Button(archived ? String(appLocalized: "Reopen feedback") : String(appLocalized: "Archive feedback"),
                       systemImage: archived ? "arrow.uturn.backward" : "archivebox", action: onArchive)
            }
            if let onDelete {
                Button(String(appLocalized: "Delete request"), role: .destructive, action: onDelete)
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
    var onPosted: (() -> Void)? = nil
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
            case .bug: return String(appLocalized: "Bug")
            case .feature: return String(appLocalized: "Feature")
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
            FFSheetHeader(title: String(appLocalized: "New request")) { dismiss() }
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
                title: store.isSaving ? String(appLocalized: "Posting…") : String(appLocalized: "Post"),
                enabled: canPost,
                busy: store.isSaving
            ) {
                Task { await submit() }
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ffKeyboardDismissOnBackgroundTap()
        .background(theme.bg.ignoresSafeArea())
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
                label: String(appLocalized: "Title"),
                state: titleFocused ? .focused : .normal,
                counter: "\(title.count)/80"
            ) {
                if staticRender {
                    Text("Short and specific")
                        .foregroundStyle(theme.textFaint)
                } else {
                    TextField(String(appLocalized: "Short and specific"), text: $title)
                        .focused($titleFocused)
                        .onChange(of: title) { _, value in
                            if value.count > 80 { title = String(value.prefix(80)) }
                        }
                }
            }

            FFField(
                label: String(appLocalized: "Details"),
                state: detailsFocused ? .focused : .normal,
                help: String(appLocalized: "What happened, or what you want. Be specific."),
                counter: "\(details.count)/2000",
                minHeight: 120
            ) {
                if staticRender {
                    Text("Describe it")
                        .foregroundStyle(theme.textFaint)
                        .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
                } else {
                    TextField(String(appLocalized: "Describe it"), text: $details, axis: .vertical)
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
                    Text(String(appLocalized: "Video"))
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
                    Label(String(appLocalized: "Media"), systemImage: "photo.on.rectangle.angled")
                        .ffType(.label)
                        .foregroundStyle(theme.mossText)
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(remainingSlots == 0 || isLoadingMedia || store.isSaving)
                Button {
                    showingFileImporter = true
                } label: {
                    Label(String(appLocalized: "File"), systemImage: "paperclip")
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
        .ffKeyboardDismissOnBackgroundTap()
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
                onPosted()
            } else {
                dismiss()
            }
        }
    }
}

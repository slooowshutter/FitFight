import SwiftUI

@MainActor
final class FeedbackStore: ObservableObject {
    @Published var posts: [FitFightFeedbackPost] = []
    @Published var comments: [FitFightFeedbackComment] = []
    @Published var detail: FitFightFeedbackPost?
    @Published var isLoading = false
    @Published var isSaving = false
    @Published var error: String?

    private let api = FitFightAPI()

    func load(session: SessionStore, kind: String?) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await session.freshAccessToken()
            posts = try await api.listFeedback(kind: kind, accessToken: token).posts
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadDetail(session: SessionStore, postID: UUID) async {
        comments = []
        isLoading = true
        defer { isLoading = false }
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.feedbackDetail(postID: postID, accessToken: token)
            detail = result.post
            comments = result.comments
            if let index = posts.firstIndex(where: { $0.id == result.post.id }) {
                posts[index] = result.post
            }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    func vote(session: SessionStore, postID: UUID) async {
        do {
            let token = try await session.freshAccessToken()
            let result = try await api.toggleFeedbackVote(postID: postID, accessToken: token)
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
        body: String
    ) async -> Bool {
        isSaving = true
        defer { isSaving = false }
        do {
            let token = try await session.freshAccessToken()
            let created = try await api.createFeedback(
                FitFightCreateFeedback(kind: kind, title: title, body: body),
                accessToken: token
            )
            posts.insert(created.post, at: 0)
            error = nil
            return true
        } catch {
            self.error = error.localizedDescription
            return false
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
                accessToken: token
            )
            comments.append(created.comment)
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
}

struct RequestsView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @StateObject private var store = FeedbackStore()
    @State private var filter: RequestFilter = .top
    @State private var composing = false
    @State private var openPostID: UUID?

    private enum RequestFilter: Hashable, CaseIterable {
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

    var body: some View {
        NavigationStack {
            list
                .navigationDestination(item: $openPostID) { postID in
                    RequestDetailView(postID: postID, store: store)
                        .toolbar(.hidden, for: .navigationBar)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .background(theme.bg.ignoresSafeArea())
        .task { await store.load(session: session, kind: filter.kind) }
        .onChange(of: filter) { _, value in
            Task { await store.load(session: session, kind: value.kind) }
        }
        .sheet(isPresented: $composing) {
            ComposeRequestView(store: store)
                .environmentObject(session)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
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

            FFSegmented(items: RequestFilter.allCases, selection: $filter) { $0.title }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 12)

            if let error = store.error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    .padding(.horizontal, theme.space.screenPadding)
                    .padding(.bottom, 8)
            }

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
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
                    ForEach(store.posts) { post in
                        RequestRow(
                            post: post,
                            onOpen: { openPostID = post.id },
                            onVote: {
                                Task { await store.vote(session: session, postID: post.id) }
                            }
                        )
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
            }
            .refreshable {
                await store.load(session: session, kind: filter.kind)
            }

            FFScreenCTA(title: String(localized: "New request")) {
                store.error = nil
                composing = true
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.bottom, 16)
        }
        .background(theme.bg)
    }
}

private struct RequestRow: View {
    let post: FitFightFeedbackPost
    let onOpen: () -> Void
    let onVote: () -> Void
    @Environment(\.ffTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
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
            }
            .buttonStyle(FFPressStyle(scale: 0.92))
            .accessibilityLabel(String(localized: "Upvote"))

            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        FFTag(
                            post.kind == "bug" ? String(localized: "Bug") : String(localized: "Feature"),
                            tone: post.kind == "bug" ? .ember : .moss
                        )
                        Spacer(minLength: 0)
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
            .buttonStyle(.plain)
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
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var comment = ""
    @FocusState private var commentFocused: Bool

    private var post: FitFightFeedbackPost? {
        store.detail?.id == postID ? store.detail : store.posts.first(where: { $0.id == postID })
    }

    var body: some View {
        VStack(spacing: 0) {
            VersionBanner()
            FFNavDetail(
                title: post?.title ?? String(localized: "Request"),
                subtitle: post.map { "@\($0.authorHandle)" },
                onBack: { dismiss() }
            )
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.top, 12)

            if let error = store.error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    .padding(.horizontal, theme.space.screenPadding)
                    .padding(.top, 8)
            }

            ScrollView {
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
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        Text(post.body)
                            .ffType(.body)
                            .foregroundStyle(theme.text)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)

                        FFSectionHeader(title: String(localized: "Comments"))
                            .padding(.top, 8)

                        if store.comments.isEmpty {
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
            }
            .scrollDismissesKeyboard(.interactively)

            HStack(spacing: 10) {
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
        .task { await store.loadDetail(session: session, postID: postID) }
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
}

private struct ComposeRequestView: View {
    @ObservedObject var store: FeedbackStore
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var kind: ComposeKind = .bug
    @State private var title = ""
    @State private var details = ""
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
            VersionBanner()
            HStack {
                Text("New request")
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button("Close") { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            ScrollView {
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
                        TextField(String(localized: "Short and specific"), text: $title)
                            .focused($titleFocused)
                            .onChange(of: title) { _, value in
                                if value.count > 80 { title = String(value.prefix(80)) }
                            }
                    }

                    FFField(
                        label: String(localized: "Details"),
                        state: detailsFocused ? .focused : .normal,
                        help: String(localized: "What happened, or what you want. Be specific."),
                        counter: "\(details.count)/2000",
                        minHeight: 120
                    ) {
                        TextField(String(localized: "Describe it"), text: $details, axis: .vertical)
                            .focused($detailsFocused)
                            .lineLimit(6...12)
                            .onChange(of: details) { _, value in
                                if value.count > 2000 { details = String(value.prefix(2000)) }
                            }
                    }
                }
                .padding(.horizontal, theme.space.screenPadding)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

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
        .background(theme.bg.ignoresSafeArea())
    }

    private var canPost: Bool {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.count >= 8
            && trimmedDetails.count >= 20
            && !store.isSaving
    }

    private func submit() async {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if await store.submit(
            session: session,
            kind: kind.value,
            title: trimmedTitle,
            body: trimmedDetails
        ) {
            dismiss()
        }
    }
}

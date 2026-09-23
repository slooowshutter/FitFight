import SwiftUI

struct FightPostEngagement: View {
    let post: FitFightFightPost
    var targetCommentID: UUID? = nil
    var onTargetCommentLoaded: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    @State private var comments: [FitFightFightPostComment] = []
    @State private var nextCursor: String?
    @State private var loadedCommentPages = 0
    @State private var open = false
    @State private var showingReactions = false
    @State private var showingCustomEmoji = false
    @State private var replyTo: FitFightFightPostComment?
    @State private var draft = ""
    @State private var mentionPeople: [FitFightFightPost.Author] = []
    @State private var customEmoji = ""
    @State private var loading = false
    @State private var loadingComments = false
    @State private var reloadComments = false
    @State private var commentsVersion = 0
    @State private var didRevealTarget = false
    @State private var likingCommentIDs: Set<UUID> = []
    @State private var profileComment: FitFightFightPostComment?
    @FocusState private var composerFocused: Bool

    private let quickEmoji = ["🔥", "💪", "😂", "❤️", "👏", "😮"]

    init(post: FitFightFightPost, targetCommentID: UUID? = nil, onTargetCommentLoaded: (() -> Void)? = nil) {
        self.post = post
        self.targetCommentID = targetCommentID
        self.onTargetCommentLoaded = onTargetCommentLoaded
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            _comments = State(initialValue: post.commentCount == 0 ? [] : CompanionPreview.comments(postID: post.id))
            _open = State(initialValue: post.commentCount > 0)
            if ProcessInfo.processInfo.environment["FF_COMMENT_REPLY_PREVIEW"] == "1" {
                _replyTo = State(initialValue: CompanionPreview.comments(postID: post.id).first)
            }
        }
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            actions
            if open {
                if loadingComments {
                    ProgressView()
                        .tint(theme.mossText)
                }
                ForEach(displayedComments) { row in
                    commentRow(row.comment)
                        .padding(.leading, CGFloat(min(row.depth, 4)) * 14)
                        .id(row.id)
                }
                if nextCursor != nil {
                    Button(String(appLocalized: "More comments")) {
                        Task { await loadComments(more: true) }
                    }
                    .ffType(.caption)
                    .foregroundStyle(theme.mossText)
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(loadingComments || loading)
                }
                FeedMentionField(
                    text: $draft,
                    people: $mentionPeople,
                    main: post.broadcast || post.audience == "main" || post.fightId == nil,
                    fightIDs: {
                        var ids = post.channels.map(\.fightId)
                        if let fightId = post.fightId, !ids.contains(fightId) {
                            ids.append(fightId)
                        }
                        return ids
                    }(),
                    loadsOnFirstMention: true
                ) {
                    HStack(alignment: .center, spacing: 0) {
                        TextField(
                            replyTo.map { String(appLocalized: "Reply to @\($0.author.handle)…") }
                                ?? String(appLocalized: "Write a comment…"),
                            text: $draft,
                            axis: .vertical
                        )
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1...4)
                        .focused($composerFocused)
                        .padding(.leading, 14)
                        .padding(.vertical, 10)
                        .frame(minHeight: 44, alignment: .center)
                        if replyTo != nil {
                            Button {
                                replyTo = nil
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(theme.textSecondary)
                                    .frame(width: 44, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(FFHapticPlainStyle())
                            .accessibilityLabel(String(appLocalized: "Cancel reply"))
                        }
                        Button {
                            Task { await sendComment() }
                        } label: {
                            Group {
                                if loading {
                                    ProgressView().tint(theme.mossText)
                                } else {
                                    Image(systemName: "arrow.up.circle.fill")
                                        .font(.system(size: 28, weight: .semibold))
                                        .foregroundStyle(canSendComment ? theme.mossText : theme.textFaint)
                                }
                            }
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(FFHapticPlainStyle())
                        .disabled(!canSendComment)
                        .accessibilityLabel(loading ? String(appLocalized: "Posting…") : String(appLocalized: "Send"))
                    }
                    .background(theme.control, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .ffBorder(theme.hairline, radius: 22)
                }
            }
        }
        .task {
            if post.commentCount > 0 || targetCommentID != nil {
                open = true
                await loadComments()
            }
            #if DEBUG && targetEnvironment(simulator)
            if CompanionPreview.isEnabled,
               ProcessInfo.processInfo.environment["FF_COMMENT_FOCUS_PREVIEW"] == "1",
               post.id == CompanionPreview.posts().first?.id {
                composerFocused = true
            }
            #endif
        }
        .onChange(of: post.commentCount) { previous, count in
            if previous == 0 && count > 0 {
                open = true
            }
            if open {
                Task { await loadComments() }
            }
        }
        .onChange(of: feed.revision) { _, _ in
            if open { Task { await loadComments() } }
        }
        .onChange(of: comments.map(\.id)) { _, ids in
            if !didRevealTarget, let targetCommentID, ids.contains(targetCommentID) {
                didRevealTarget = true
                onTargetCommentLoaded?()
            }
        }
        .sheet(item: $profileComment) { comment in
            ProfileSheet(userID: comment.author.userId, source: "comments")
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingReactions) {
            FightPostReactionsSheet(post: post)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
        .alert(String(appLocalized: "React"), isPresented: $showingCustomEmoji) {
            TextField(String(appLocalized: "Emoji"), text: $customEmoji)
            Button(String(appLocalized: "Cancel"), role: .cancel) { customEmoji = "" }
            Button(String(appLocalized: "React")) {
                if let emoji = firstEmoji(in: customEmoji) {
                    Task { await feed.react(session: session, post: post, emoji: emoji) }
                }
                customEmoji = ""
            }
            .disabled(firstEmoji(in: customEmoji) == nil || feed.reactingPostIDs.contains(post.id))
        }
    }

    private var canSendComment: Bool {
        !loading && !loadingComments && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actions: some View {
        let rankedEmoji = post.reactions.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.emoji < rhs.emoji
        }.map(\.emoji)
        let emojiOptions = rankedEmoji + quickEmoji.filter { !rankedEmoji.contains($0) }

        return VStack(alignment: .leading, spacing: 0) {
            FFDivider(inset: 0)
            HStack(spacing: 4) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(emojiOptions, id: \.self) { emoji in
                            let reaction = post.reactions.first { $0.emoji == emoji }
                            Button {
                                Task { await feed.react(session: session, post: post, emoji: emoji) }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(emoji)
                                    if let reaction { Text(verbatim: "\(reaction.count)") }
                                }
                                .ffType(.caption)
                                .foregroundStyle(reaction?.mine == true ? theme.mossText : theme.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(reaction?.mine == true ? theme.mossWash : reaction == nil ? theme.card : theme.control, in: Capsule())
                                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(FFHapticPlainStyle())
                            .disabled(feed.reactingPostIDs.contains(post.id))
                            .accessibilityLabel(emoji)
                            .accessibilityValue(reaction.map { String($0.count) } ?? "0")
                            .accessibilityAddTraits(reaction?.mine == true ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 44)
                Button {
                    showingCustomEmoji = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(feed.reactingPostIDs.contains(post.id))
                .accessibilityLabel(String(appLocalized: "Other emoji…"))
            }
            HStack {
                Button {
                    open.toggle()
                    if open && comments.isEmpty {
                        Task { await loadComments() }
                    }
                    if open && post.commentCount == 0 { composerFocused = true }
                } label: {
                    Text(
                        post.commentCount == 0
                            ? String(appLocalized: "Comment")
                            : post.commentCount == 1
                                ? String(appLocalized: "1 comment")
                                : String(appLocalized: "\(post.commentCount) comments")
                    )
                    .ffType(.caption)
                    .foregroundStyle(theme.mossText)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FFHapticPlainStyle())
                Spacer(minLength: 8)
                if !post.reactions.isEmpty {
                    Button(String(appLocalized: "View reactions")) { showingReactions = true }
                        .ffType(.micro)
                        .foregroundStyle(theme.textSecondary)
                        .frame(minHeight: 44)
                        .buttonStyle(FFHapticPlainStyle())
                }
            }
            .frame(height: 24)
            .padding(.top, 10)
        }
    }

    private var displayedComments: [DisplayedFightComment] {
        let commentIDs = Set(comments.map(\.id))
        let children = Dictionary(grouping: comments, by: \.parentId)
        func ordered(_ items: [FitFightFightPostComment]) -> [FitFightFightPostComment] {
            items.sorted { lhs, rhs in
                if lhs.createdDate != rhs.createdDate { return lhs.createdDate > rhs.createdDate }
                return lhs.id.uuidString > rhs.id.uuidString
            }
        }
        var rows: [DisplayedFightComment] = []
        var stack: [(FitFightFightPostComment, Int)] = ordered(
            comments.filter { comment in comment.parentId.map { !commentIDs.contains($0) } ?? true }
        )
        .reversed()
        .map { ($0, 0) }
        while let (comment, depth) = stack.popLast() {
            rows.append(DisplayedFightComment(comment: comment, depth: depth))
            for child in ordered(children[comment.id] ?? []).reversed() {
                stack.append((child, depth + 1))
            }
        }
        return rows
    }

    private func commentRow(_ comment: FitFightFightPostComment) -> some View {
        var author = AttributedString(comment.author.atHandle)
        author.font = theme.font(.label)
        author.foregroundColor = theme.text
        author.link = URL(string: "fitfight-profile://author")

        return HStack(alignment: .top, spacing: 0) {
            ProfileIdentityLink(userID: comment.author.userId, source: "comments") {
                CompanionAvatar(
                    personID: comment.author.userId.uuidString,
                    companionID: comment.author.companionId,
                    isYou: comment.mine,
                    monogram: comment.author.initials,
                    photoURL: comment.author.avatar?.url,
                    size: 28
                )
                .frame(width: 44, height: 44, alignment: .topLeading)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(author)
                        .tint(theme.text)
                        .lineLimit(1)
                        .environment(\.openURL, OpenURLAction { _ in
                            profileComment = comment
                            return .handled
                        })
                    Text(comment.createdDate, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                        .font(.ff(theme.type.spec(.micro).size, 500))
                        .foregroundStyle(theme.textFaint)
                        .lineLimit(1)
                }
                Text(comment.body)
                    .font(.ff(theme.type.spec(.body).size, 500))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Button(String(appLocalized: "Reply")) {
                        replyTo = comment
                        composerFocused = true
                    }
                    .ffType(.micro)
                    .foregroundStyle(theme.textSecondary)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                    .buttonStyle(FFHapticPlainStyle())
                    TextTranslationButton(text: comment.body, alignment: .center)
                    Menu {
                        if comment.mine {
                            Button(String(appLocalized: "Delete"), role: .destructive) {
                                Task { await deleteComment(comment) }
                            }
                        } else {
                            Button(String(appLocalized: "Report")) {
                                Task { await reportComment(comment) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.textFaint)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                    .accessibilityLabel(String(appLocalized: "Comment actions"))
                    Spacer(minLength: 0)
                }
                .frame(height: 24)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 8)
            Button {
                Task { await likeComment(comment) }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: comment.likedByMe == true ? "heart.fill" : "heart")
                        .font(.system(size: 16, weight: .semibold))
                    if let count = comment.likeCount, count > 0 {
                        Text(verbatim: "\(count)")
                            .ffType(.micro)
                            .monospacedDigit()
                    }
                }
                .foregroundStyle(comment.likedByMe == true ? theme.mossText : theme.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(FFHapticPlainStyle())
            .padding(.top, 12)
            .disabled(likingCommentIDs.contains(comment.id))
            .accessibilityLabel(comment.likedByMe == true ? String(appLocalized: "Unlike comment") : String(appLocalized: "Like comment"))
            .accessibilityValue(String(comment.likeCount ?? 0))
        }
    }

    private func loadComments(more: Bool = false) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            comments = post.commentCount == 0 ? [] : CompanionPreview.comments(postID: post.id)
            return
        }
        #endif
        guard let userID = session.authSession?.user.id else { return }
        if loadingComments {
            reloadComments = true
            return
        }
        loadingComments = true
        defer { if session.authSession?.user.id == userID { loadingComments = false } }
        var append = more
        let requestedPages = max(1, loadedCommentPages + (more ? 1 : 0))
        repeat {
            reloadComments = false
            let version = commentsVersion
            let retainedIDs = Set(comments.map(\.id))
            var refreshed = append ? comments : []
            var cursor = append ? nextCursor : nil
            var pages = append ? loadedCommentPages : 0
            do {
                let token = try await session.freshAccessToken()
                guard !Task.isCancelled, session.authSession?.user.id == userID else { return }
                repeat {
                    let result = try await FitFightAPI().fightPostComments(
                        postID: post.id,
                        cursor: cursor,
                        accessToken: token,
                        sort: .recent
                    )
                    guard !Task.isCancelled, session.authSession?.user.id == userID else { return }
                    if commentsVersion != version || reloadComments {
                        // A response started before a write or invalidation must not undo it.
                        reloadComments = true
                        break
                    }
                    refreshed += result.comments.filter { comment in !refreshed.contains(where: { $0.id == comment.id }) }
                    cursor = result.nextCursor
                    pages += 1
                    if cursor == nil { break }
                    if pages >= requestedPages,
                       retainedIDs.isSubset(of: Set(refreshed.map(\.id))) {
                        if let targetCommentID, !refreshed.contains(where: { $0.id == targetCommentID }) { continue }
                        break
                    }
                } while true
                if !reloadComments {
                    // Publish all retained pages together so a failed later page cannot collapse the thread.
                    let pendingLikes = Dictionary(uniqueKeysWithValues: comments.filter { likingCommentIDs.contains($0.id) }.map { ($0.id, $0) })
                    comments = refreshed.map { comment in
                        guard let pending = pendingLikes[comment.id] else { return comment }
                        var updated = comment
                        updated.likeCount = pending.likeCount
                        updated.likedByMe = pending.likedByMe
                        return updated
                    }
                    nextCursor = cursor
                    loadedCommentPages = pages
                }
            } catch {
                if Task.isCancelled || error is CancellationError { return }
                guard session.authSession?.user.id == userID else { return }
                if !reloadComments { feed.error = error.localizedDescription }
            }
            append = false
        } while reloadComments
    }

    private func likeComment(_ comment: FitFightFightPostComment) async {
        guard let userID = session.authSession?.user.id,
              !likingCommentIDs.contains(comment.id),
              let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        let previous = comments[index]
        let liked = previous.likedByMe != true
        likingCommentIDs.insert(comment.id)
        commentsVersion += 1
        comments[index].likedByMe = liked
        comments[index].likeCount = max(0, (previous.likeCount ?? 0) + (liked ? 1 : -1))
        defer {
            if session.authSession?.user.id == userID {
                likingCommentIDs.remove(comment.id)
            }
        }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID else { return }
            let result = try await FitFightAPI().setFightPostCommentLike(
                postID: post.id, commentID: comment.id, liked: liked, accessToken: token
            )
            guard session.authSession?.user.id == userID else { return }
            commentsVersion += 1
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].likeCount = result.likeCount
                comments[index].likedByMe = result.likedByMe
            }
        } catch {
            guard session.authSession?.user.id == userID else { return }
            commentsVersion += 1
            if let index = comments.firstIndex(where: { $0.id == comment.id }) {
                comments[index].likeCount = previous.likeCount
                comments[index].likedByMe = previous.likedByMe
            }
            if !(error is CancellationError) { feed.error = error.localizedDescription }
        }
    }

    private func sendComment() async {
        let note = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, let userID = session.authSession?.user.id else { return }
        let parentID = replyTo?.id
        loading = true
        defer { if session.authSession?.user.id == userID { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID else { return }
            let created = try await FitFightAPI().createFightPostComment(
                postID: post.id,
                body: note,
                parentID: parentID,
                accessToken: token
            )
            guard session.authSession?.user.id == userID else { return }
            commentsVersion += 1
            if !comments.contains(where: { $0.id == created.comment.id }) {
                comments.append(created.comment)
            }
            draft = ""
            replyTo = nil
            if let current = feed.posts.first(where: { $0.id == post.id }) {
                feed.replace(current.updating(commentCount: created.commentCount ?? current.commentCount + 1))
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID else { return }
            feed.error = error.localizedDescription
        }
    }

    private func deleteComment(_ comment: FitFightFightPostComment) async {
        guard let userID = session.authSession?.user.id else { return }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID else { return }
            let result = try await FitFightAPI().deleteFightPostComment(postID: post.id, commentID: comment.id, accessToken: token)
            guard session.authSession?.user.id == userID else { return }
            commentsVersion += 1
            let children = Dictionary(grouping: comments, by: \.parentId)
            var removed = Set<UUID>()
            var pending = [comment.id]
            while let id = pending.popLast() {
                guard removed.insert(id).inserted else { continue }
                pending.append(contentsOf: (children[id] ?? []).map(\.id))
            }
            comments.removeAll { removed.contains($0.id) }
            if let replyTo, removed.contains(replyTo.id) { self.replyTo = nil }
            if let current = feed.posts.first(where: { $0.id == post.id }) {
                feed.replace(current.updating(commentCount: result.commentCount ?? max(0, current.commentCount - removed.count)))
            }
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID else { return }
            feed.error = error.localizedDescription
        }
    }

    private func reportComment(_ comment: FitFightFightPostComment) async {
        guard let userID = session.authSession?.user.id else { return }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID else { return }
            try await FitFightAPI().reportFightPostComment(postID: post.id, commentID: comment.id, accessToken: token)
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID else { return }
            feed.error = error.localizedDescription
        }
    }

    private func firstEmoji(in value: String) -> String? {
        guard let segment = value.precomposedStringWithCanonicalMapping.first else { return nil }
        let candidate = String(segment)
        return candidate.unicodeScalars.contains(where: { $0.properties.isEmoji }) ? candidate : nil
    }
}

private struct FightPostReactionsSheet: View {
    let post: FitFightFightPost

    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var people: [FitFightFightPostReactionPerson] = []
    @State private var nextCursor: String?
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        FFScreen(clearance: false) {
            FFSheetHeader(title: String(appLocalized: "Reactions")) { dismiss() }
            if !people.isEmpty {
                FFCard {
                    ForEach(people) { person in
                        ProfileIdentityLink(userID: person.userId, source: "reactions") {
                            HStack(spacing: 12) {
                            Text(person.emoji)
                                .ffType(.title)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("@\(person.handle)")
                                    .ffType(.label)
                                    .foregroundStyle(theme.text)
                                Text(person.displayName)
                                    .ffType(.caption)
                                    .foregroundStyle(theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                        }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } else if !loading && error == nil {
                Text(String(appLocalized: "No reactions yet"))
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            }
            if loading {
                ProgressView()
                    .tint(theme.mossText)
            }
            if let error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                FFButton(title: String(appLocalized: "Retry"), kind: .ghost) {
                    Task { await loadPeople(more: !people.isEmpty) }
                }
                .disabled(loading)
            } else if nextCursor != nil {
                FFButton(title: String(appLocalized: "More reactions"), kind: .ghost) {
                    Task { await loadPeople(more: true) }
                }
                .disabled(loading)
            }
        }
        .task { await loadPeople() }
    }

    private func loadPeople(more: Bool = false) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            if let reaction = post.reactions.first {
                people = CompanionPreview.people.dropFirst().prefix(reaction.count).map { person in
                    FitFightFightPostReactionPerson(
                        userId: UUID(uuidString: person.id)!,
                        handle: String(person.handle.dropFirst()),
                        displayName: person.name,
                        emoji: reaction.emoji
                    )
                }
            }
            loading = false
            return
        }
        #endif
        guard let userID = session.authSession?.user.id else { return }
        loading = true
        error = nil
        defer { if session.authSession?.user.id == userID { loading = false } }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID else { return }
            let result = try await FitFightAPI().fightPostReactionPeople(
                postID: post.id,
                cursor: more ? nextCursor : nil,
                accessToken: token
            )
            guard !Task.isCancelled, session.authSession?.user.id == userID else { return }
            people = more
                ? people + result.people.filter { person in !people.contains(where: { $0.id == person.id }) }
                : result.people
            nextCursor = result.nextCursor
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID else { return }
            self.error = error.localizedDescription
        }
    }
}

private struct DisplayedFightComment: Identifiable {
    let comment: FitFightFightPostComment
    let depth: Int
    var id: UUID { comment.id }
}

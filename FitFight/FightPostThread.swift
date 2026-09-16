import SwiftUI

struct FightPostEngagement: View {
    let post: FitFightFightPost

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var feed: FeedStore
    @Environment(\.ffTheme) private var theme

    @State private var comments: [FitFightFightPostComment] = []
    @State private var nextCursor: String?
    @State private var open = false
    @State private var showingReactions = false
    @State private var replyTo: FitFightFightPostComment?
    @State private var draft = ""
    @State private var loading = false
    @State private var loadingComments = false

    private let likeEmoji = "👏"
    private let quickEmoji = ["🔥", "💪", "😂", "❤️", "👏", "😮"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !post.reactions.isEmpty {
                reactionChips
                Button(String(localized: "View reactions")) { showingReactions = true }
                    .ffType(.caption)
                    .foregroundStyle(theme.mossText)
                    .buttonStyle(FFHapticPlainStyle())
            }
            actions
            if open {
                if loadingComments {
                    ProgressView()
                        .tint(theme.mossText)
                }
                ForEach(displayedComments) { row in
                    commentRow(row.comment)
                        .padding(.leading, CGFloat(min(row.depth, 4)) * 14)
                }
                if nextCursor != nil {
                    Button(String(localized: "More comments")) {
                        Task { await loadComments(more: true) }
                    }
                    .ffType(.caption)
                    .foregroundStyle(theme.mossText)
                    .buttonStyle(FFHapticPlainStyle())
                    .disabled(loadingComments || loading)
                }
                if let replyTo {
                    HStack {
                        Text(String(localized: "Replying to @\(replyTo.author.handle)"))
                            .ffType(.micro)
                            .foregroundStyle(theme.textSecondary)
                        Spacer()
                        Button(String(localized: "Cancel")) { self.replyTo = nil }
                            .ffType(.micro)
                            .foregroundStyle(theme.mossText)
                            .buttonStyle(FFHapticPlainStyle())
                    }
                }
                HStack {
                    TextField(String(localized: "Write a comment…"), text: $draft, axis: .vertical)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .lineLimit(1...4)
                    FFButton(
                        title: loading ? String(localized: "Posting…") : String(localized: "Send"),
                        kind: .ghost,
                        fullWidth: false
                    ) {
                        Task { await sendComment() }
                    }
                    .disabled(loading || loadingComments || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .task {
            if post.commentCount > 0 {
                open = true
                await loadComments()
            }
        }
        .onChange(of: post.commentCount) { previous, count in
            if previous == 0 && count > 0 {
                open = true
                if comments.isEmpty {
                    Task { await loadComments() }
                }
            }
        }
        .sheet(isPresented: $showingReactions) {
            FightPostReactionsSheet(post: post)
                .environmentObject(session)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }

    // NOTE: nested horizontal ScrollView plus a tiny emoji field sat inside Feed's
    // vertical scroll, so the like controls were easy to miss and often untappable.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            FFDivider(inset: 0)
            HStack(spacing: 16) {
                likeButton
                commentButton
                reactMenu
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44)
        }
        .disabled(feed.reactingPostIDs.contains(post.id))
        .accessibilityValue(feed.reactingPostIDs.contains(post.id) ? String(localized: "Saving…") : "")
    }

    private var liked: Bool {
        post.reactions.contains { $0.mine }
    }

    private var likeCount: Int {
        post.reactions.reduce(0) { $0 + $1.count }
    }

    private var likeButton: some View {
        Button {
            let emoji = post.reactions.first(where: \.mine)?.emoji ?? likeEmoji
            Task { await feed.react(session: session, post: post, emoji: emoji) }
        } label: {
            HStack(spacing: 6) {
                Text(post.reactions.first(where: \.mine)?.emoji ?? likeEmoji)
                if likeCount > 0 {
                    Text(verbatim: "\(likeCount)")
                }
            }
            .ffType(.caption)
            .foregroundStyle(liked ? theme.mossText : theme.textSecondary)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .accessibilityLabel(liked ? String(localized: "Remove reaction") : String(localized: "Cheer this post"))
        .accessibilityValue(likeCount > 0 ? String(likeCount) : "")
    }

    private var commentButton: some View {
        Button {
            open.toggle()
            if open && comments.isEmpty {
                Task { await loadComments() }
            }
        } label: {
            Text(
                post.commentCount == 0
                    ? String(localized: "Comment")
                    : post.commentCount == 1
                        ? String(localized: "1 comment")
                        : String(localized: "\(post.commentCount) comments")
            )
            .ffType(.caption)
            .foregroundStyle(theme.mossText)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(FFHapticPlainStyle())
    }

    private var reactMenu: some View {
        Menu {
            ForEach(quickEmoji, id: \.self) { emoji in
                Button {
                    Task { await feed.react(session: session, post: post, emoji: emoji) }
                } label: {
                    Text(emoji)
                }
            }
        } label: {
            Image(systemName: "face.smiling")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(theme.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(FFHapticPlainStyle())
        .menuOrder(.fixed)
        .accessibilityLabel(String(localized: "React"))
    }

    private var reactionChips: some View {
        HStack(spacing: 8) {
            ForEach(post.reactions, id: \.emoji) { reaction in
                Button {
                    Task { await feed.react(session: session, post: post, emoji: reaction.emoji) }
                } label: {
                    Text("\(reaction.emoji) \(reaction.count)")
                        .ffType(.caption)
                        .foregroundStyle(reaction.mine ? theme.mossOn : theme.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(reaction.mine ? theme.mossFill : theme.control, in: Capsule())
                }
                .buttonStyle(FFHapticPlainStyle())
            }
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .disabled(feed.reactingPostIDs.contains(post.id))
    }

    private var displayedComments: [DisplayedFightComment] {
        let commentIDs = Set(comments.map(\.id))
        let children = Dictionary(grouping: comments, by: \.parentId)
        var rows: [DisplayedFightComment] = []
        var stack: [(FitFightFightPostComment, Int)] = comments
            .filter { comment in comment.parentId.map { !commentIDs.contains($0) } ?? true }
            .reversed()
            .map { ($0, 0) }
        while let (comment, depth) = stack.popLast() {
            rows.append(DisplayedFightComment(comment: comment, depth: depth))
            for child in (children[comment.id] ?? []).reversed() {
                stack.append((child, depth + 1))
            }
        }
        return rows
    }

    private func commentRow(_ comment: FitFightFightPostComment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                CompanionAvatar(
                    personID: comment.author.userId.uuidString,
                    companionID: comment.author.companionId,
                    isYou: comment.mine,
                    monogram: comment.author.initials,
                    photoURL: comment.author.avatar?.url,
                    size: 26
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(comment.author.atHandle)
                        .ffType(.caption)
                        .foregroundStyle(theme.text)
                    Text(comment.body)
                        .ffType(.body)
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 12) {
                        Text(comment.createdDate, style: .relative)
                            .ffType(.micro)
                            .foregroundStyle(theme.textFaint)
                        Button(String(localized: "Reply")) {
                            replyTo = comment
                        }
                        .ffType(.micro)
                        .foregroundStyle(theme.mossText)
                        .buttonStyle(FFHapticPlainStyle())
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    if comment.mine {
                        Button(String(localized: "Delete"), role: .destructive) {
                            Task { await deleteComment(comment) }
                        }
                    } else {
                        Button(String(localized: "Report")) {
                            Task { await reportComment(comment) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.textFaint)
                }
                .buttonStyle(FFHapticPlainStyle())
            }
        }
    }

    private func loadComments(more: Bool = false) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            comments = post.commentCount == 0 ? [] : CompanionPreview.comments(postID: post.id)
            return
        }
        #endif
        guard !loadingComments, let userID = session.authSession?.user.id else { return }
        loadingComments = true
        defer { if session.authSession?.user.id == userID { loadingComments = false } }
        do {
            let token = try await session.freshAccessToken()
            guard session.authSession?.user.id == userID else { return }
            let result = try await FitFightAPI().fightPostComments(
                postID: post.id,
                cursor: more ? nextCursor : nil,
                accessToken: token
            )
            guard session.authSession?.user.id == userID else { return }
            comments = more
                ? comments + result.comments.filter { comment in !comments.contains(where: { $0.id == comment.id }) }
                : result.comments
            nextCursor = result.nextCursor
        } catch {
            if Task.isCancelled || error is CancellationError { return }
            guard session.authSession?.user.id == userID else { return }
            feed.error = error.localizedDescription
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
            HStack {
                Text(String(localized: "Reactions"))
                    .ffType(.title)
                    .foregroundStyle(theme.text)
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
                    .buttonStyle(FFHapticPlainStyle())
            }
            if !people.isEmpty {
                FFCard {
                    ForEach(people) { person in
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
            } else if !loading && error == nil {
                Text(String(localized: "No reactions yet"))
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            }
            if loading {
                ProgressView()
                    .tint(theme.mossText)
            }
            if let error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                FFButton(title: String(localized: "Retry"), kind: .ghost) {
                    Task { await loadPeople(more: !people.isEmpty) }
                }
                .disabled(loading)
            } else if nextCursor != nil {
                FFButton(title: String(localized: "More reactions"), kind: .ghost) {
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

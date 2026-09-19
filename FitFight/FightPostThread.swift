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
    @State private var commentSort = FightPostCommentSort.comments
    @State private var loadedCommentSort = FightPostCommentSort.comments
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
                FFSegmented(
                    items: FightPostCommentSort.allCases,
                    selection: $commentSort
                ) { $0.title }
                .accessibilityLabel(String(localized: "Comment order"))
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
                    }()
                ) {
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
        }
        .task {
            if post.commentCount > 0 || targetCommentID != nil {
                open = true
                await loadComments()
            }
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
        .onChange(of: commentSort) { _, _ in
            nextCursor = nil
            Task { await loadComments() }
        }
        .sheet(isPresented: $showingReactions) {
            FightPostReactionsSheet(post: post)
                .environmentObject(session)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
        .alert(String(localized: "React"), isPresented: $showingCustomEmoji) {
            TextField(String(localized: "Emoji"), text: $customEmoji)
            Button(String(localized: "Cancel"), role: .cancel) { customEmoji = "" }
            Button(String(localized: "React")) {
                if let emoji = firstEmoji(in: customEmoji) {
                    Task { await feed.react(session: session, post: post, emoji: emoji) }
                }
                customEmoji = ""
            }
            .disabled(firstEmoji(in: customEmoji) == nil || feed.reactingPostIDs.contains(post.id))
        }
    }

    private var actions: some View {
        let mine = post.reactions.first(where: \.mine)
        let count = post.reactions.reduce(0) { $0 + $1.count }
        return VStack(alignment: .leading, spacing: 0) {
            FFDivider(inset: 0)
            HStack(spacing: 16) {
                Button {
                    let emoji = mine?.emoji ?? "👏"
                    Task { await feed.react(session: session, post: post, emoji: emoji) }
                } label: {
                    HStack(spacing: 6) {
                        Text(mine?.emoji ?? "👏")
                        if count > 0 { Text(verbatim: "\(count)") }
                    }
                    .ffType(.caption)
                    .foregroundStyle(mine == nil ? theme.textSecondary : theme.mossText)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(FFHapticPlainStyle())
                .accessibilityLabel(mine == nil ? String(localized: "Cheer this post") : String(localized: "Remove reaction"))
                .accessibilityValue(count > 0 ? String(count) : "")

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

                Menu {
                    ForEach(quickEmoji, id: \.self) { emoji in
                        Button(emoji) {
                            Task { await feed.react(session: session, post: post, emoji: emoji) }
                        }
                    }
                    Button(String(localized: "Other emoji…")) {
                        showingCustomEmoji = true
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
                Spacer(minLength: 0)
            }
        }
        .disabled(feed.reactingPostIDs.contains(post.id))
        .accessibilityValue(feed.reactingPostIDs.contains(post.id) ? String(localized: "Saving…") : "")
    }

    private var reactionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
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
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
            }
        }
        .disabled(feed.reactingPostIDs.contains(post.id))
        .accessibilityValue(feed.reactingPostIDs.contains(post.id) ? String(localized: "Saving…") : "")
    }

    private var displayedComments: [DisplayedFightComment] {
        let commentIDs = Set(comments.map(\.id))
        let children = Dictionary(grouping: comments, by: \.parentId)
        func replyCount(_ comment: FitFightFightPostComment) -> Int {
            var count = 0
            var pending = children[comment.id] ?? []
            while let next = pending.popLast() {
                count += 1
                pending.append(contentsOf: children[next.id] ?? [])
            }
            return count
        }
        func ordered(_ items: [FitFightFightPostComment]) -> [FitFightFightPostComment] {
            items.sorted { lhs, rhs in
                switch commentSort {
                case .comments:
                    let left = replyCount(lhs)
                    let right = replyCount(rhs)
                    if left != right { return left > right }
                    if lhs.createdDate != rhs.createdDate { return lhs.createdDate > rhs.createdDate }
                    return lhs.id.uuidString > rhs.id.uuidString
                case .recent:
                    if lhs.createdDate != rhs.createdDate { return lhs.createdDate > rhs.createdDate }
                    return lhs.id.uuidString > rhs.id.uuidString
                }
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
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                ProfileIdentityLink(userID: comment.author.userId, source: "comments") {
                    CompanionAvatar(
                        personID: comment.author.userId.uuidString,
                        companionID: comment.author.companionId,
                        isYou: comment.mine,
                        monogram: comment.author.initials,
                        photoURL: comment.author.photoURL,
                        size: 26
                    )
                }
                VStack(alignment: .leading, spacing: 3) {
                    ProfileIdentityLink(userID: comment.author.userId, source: "comments") {
                        Text(comment.author.atHandle)
                            .ffType(.caption)
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                    }
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
                .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .top, spacing: 0) {
                    TextTranslationButton(text: comment.body)
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
                            .frame(height: 20)
                            .frame(width: 44, height: 44, alignment: .top)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(FFHapticPlainStyle())
                }
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
        guard let userID = session.authSession?.user.id else { return }
        if loadingComments {
            reloadComments = true
            return
        }
        loadingComments = true
        defer { if session.authSession?.user.id == userID { loadingComments = false } }
        var append = more
        let requestedSort = commentSort
        let requestedPages = loadedCommentSort == requestedSort ? max(1, loadedCommentPages + (more ? 1 : 0)) : 1
        repeat {
            reloadComments = false
            let version = commentsVersion
            let sort = commentSort
            let retainedIDs = loadedCommentSort == sort ? Set(comments.map(\.id)) : []
            var refreshed = append && loadedCommentSort == sort ? comments : []
            var cursor = append && loadedCommentSort == sort ? nextCursor : nil
            var pages = append && loadedCommentSort == sort ? loadedCommentPages : 0
            do {
                let token = try await session.freshAccessToken()
                guard !Task.isCancelled, session.authSession?.user.id == userID else { return }
                repeat {
                    let result = try await FitFightAPI().fightPostComments(
                        postID: post.id,
                        cursor: cursor,
                        accessToken: token,
                        sort: sort
                    )
                    guard !Task.isCancelled, session.authSession?.user.id == userID else { return }
                    if commentsVersion != version || commentSort != sort || reloadComments {
                        // A response started before a write, sort change, or invalidation must not undo it.
                        reloadComments = true
                        break
                    }
                    refreshed += result.comments.filter { comment in !refreshed.contains(where: { $0.id == comment.id }) }
                    cursor = result.nextCursor
                    pages += 1
                    if cursor == nil { break }
                    if pages >= (sort == requestedSort ? requestedPages : 1),
                       retainedIDs.isSubset(of: Set(refreshed.map(\.id))) {
                        if let targetCommentID, !refreshed.contains(where: { $0.id == targetCommentID }) { continue }
                        break
                    }
                } while true
                if !reloadComments {
                    // Publish all retained pages together so a failed later page cannot collapse the thread.
                    comments = refreshed
                    nextCursor = cursor
                    loadedCommentSort = sort
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

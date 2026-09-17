import SwiftUI

struct FeedPostLink: Identifiable, Hashable {
    let id: UUID
    var commentID: UUID? = nil
}

struct FeedActivityItem: Decodable, Identifiable {
    struct Person: Decodable {
        let userId: UUID
        let handle: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case handle
        }
    }

    let id: String
    let kind: String
    let occurredAt: Date?
    let actor: Person
    let subject: Person?
    let fightId: UUID
    let fightName: String
    let postId: UUID?
    let commentId: UUID?
    let body: String

    enum CodingKeys: String, CodingKey {
        case id, kind, actor, subject, body
        case occurredAt = "occurred_at"
        case fightId = "fight_id"
        case fightName = "fight_name"
        case postId = "post_id"
        case commentId = "comment_id"
    }

    var summary: String {
        switch kind {
        case "feed_post":
            return String(localized: "activity.post", defaultValue: "@\(actor.handle) posted")
        case "post_comment":
            return String(localized: "activity.comment", defaultValue: "@\(actor.handle) commented")
        case "comment_reply":
            return String(localized: "activity.reply", defaultValue: "@\(actor.handle) replied")
        case "post_reaction":
            return String(localized: "activity.reaction", defaultValue: "@\(actor.handle) reacted")
        case "invited":
            if let subject {
                return String(localized: "activity.invitation", defaultValue: "@\(actor.handle) invited @\(subject.handle)")
            }
            return String(localized: "Invitation")
        case "accepted":
            return String(localized: "activity.joined", defaultValue: "@\(actor.handle) joined")
        case "deferred":
            return String(localized: "activity.next-round", defaultValue: "@\(actor.handle) joined the next round")
        case "declined":
            return String(localized: "activity.declined", defaultValue: "@\(actor.handle) declined")
        case "withdrawn":
            return String(localized: "activity.left", defaultValue: "@\(actor.handle) left")
        case "disqualified":
            return String(localized: "activity.disqualified", defaultValue: "@\(actor.handle) was disqualified")
        default:
            return String(localized: "Fight activity")
        }
    }
}

struct FeedActivityList: Decodable {
    let events: [FeedActivityItem]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case events
        case nextCursor = "next_cursor"
    }
}

@MainActor
final class FeedActivityStore: ObservableObject {
    @Published var events: [FeedActivityItem] = []
    @Published var nextCursor: String?
    @Published var isLoading = false
    @Published var error: String?
    private var generation = 0

    func load(session: SessionStore, more: Bool = false) async {
        guard let userID = session.authSession?.user.id else { return }
        generation += 1
        let request = generation
        isLoading = true
        defer { if request == generation { isLoading = false } }
        do {
            let token = try await session.freshAccessToken()
            guard !Task.isCancelled, session.authSession?.user.id == userID else { return }
            let result = try await FitFightAPI().feedActivity(cursor: more ? nextCursor : nil, accessToken: token)
            guard !Task.isCancelled, request == generation, session.authSession?.user.id == userID else { return }
            events = more ? events + result.events.filter { item in !events.contains(where: { $0.id == item.id }) } : result.events
            nextCursor = result.nextCursor
            error = nil
        } catch {
            guard !Task.isCancelled, request == generation, session.authSession?.user.id == userID else { return }
            self.error = error.localizedDescription
        }
    }
}

struct FeedActivityView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @StateObject private var activity = FeedActivityStore()

    var body: some View {
        FFScreen(refresh: FFRefreshConfig(
            isRefreshing: activity.isLoading,
            message: String(localized: "Loading"),
            action: { await activity.load(session: session) }
        )) {
            Text(String(localized: "Posts, comments, reactions and membership history from your fights."))
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
            if let error = activity.error {
                FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                FFButton(title: String(localized: "Try again"), kind: .ghost, fullWidth: true) {
                    Task { await activity.load(session: session) }
                }
            }
            if activity.events.isEmpty && activity.isLoading {
                FFLoadingBlock()
            } else if activity.events.isEmpty && activity.error == nil {
                Text(String(localized: "No activity yet."))
                    .ffType(.body)
                    .foregroundStyle(theme.textSecondary)
            }
            ForEach(activity.events) { event in
                Button {
                    if let postID = event.postId {
                        model.tab = .feed
                        model.openPost = FeedPostLink(id: postID, commentID: event.commentId)
                    } else {
                        model.openFightFromFeed(id: event.fightId.uuidString)
                    }
                } label: {
                    FFCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(verbatim: event.summary)
                                .ffType(.rowTitle)
                                .foregroundStyle(theme.text)
                            Text(verbatim: event.fightName)
                                .ffType(.caption)
                                .foregroundStyle(theme.mossText)
                            if !event.body.isEmpty {
                                Text(verbatim: event.body)
                                    .ffType(.body)
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(3)
                            }
                            Text(event.occurredAt?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Time not recorded"))
                                .ffType(.micro)
                                .foregroundStyle(theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .buttonStyle(FFHapticPlainStyle())
            }
            if activity.nextCursor != nil {
                FFButton(title: String(localized: "More"), kind: .ghost, fullWidth: true) {
                    Task { await activity.load(session: session, more: true) }
                }
                .disabled(activity.isLoading)
            }
        }
        .navigationTitle(String(localized: "Activity"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(theme.mossText)
        .task(id: model.feedRevision) { await activity.load(session: session) }
    }
}

struct FightPostDetailView: View {
    let target: FeedPostLink
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @StateObject private var postFeed = FeedStore()
    @State private var openedPhoto: FeedOpenedPhoto?

    var body: some View {
        ScrollViewReader { reader in
            FFScreen(refresh: FFRefreshConfig(
                isRefreshing: postFeed.isLoading,
                message: String(localized: "Loading"),
                action: { await postFeed.load(session: session, postID: target.id) }
            )) {
                if let error = postFeed.error {
                    FFNotice(text: error, tone: .ember, systemImage: "exclamationmark.triangle")
                    FFButton(title: String(localized: "Try again"), kind: .ghost, fullWidth: true) {
                        Task { await postFeed.load(session: session, postID: target.id) }
                    }
                }
                if let post = postFeed.posts.first {
                    FightPostCard(
                        post: post,
                        targetCommentID: target.commentID,
                        onTargetCommentLoaded: {
                            if let commentID = target.commentID {
                                Task { @MainActor in
                                    await Task.yield()
                                    reader.scrollTo(commentID, anchor: .center)
                                }
                            }
                        },
                        onOpen: post.fightId.map { id in { model.openFightFromFeed(id: id.uuidString) } },
                        onOpenPhoto: { openedPhoto = FeedOpenedPhoto(url: $0) }
                    )
                } else if postFeed.isLoading {
                    FFLoadingBlock()
                } else if postFeed.error == nil {
                    Text(String(localized: "This post is no longer available."))
                        .ffType(.body)
                        .foregroundStyle(theme.textSecondary)
                }
            }
        }
        .environmentObject(postFeed)
        .navigationTitle(String(localized: "Post"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(theme.bg, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(theme.mossText)
        .task(id: "\(target.id):\(model.feedRevision)") {
            await postFeed.load(session: session, postID: target.id)
        }
        .fullScreenCover(item: $openedPhoto) { photo in
            FightPostPhotoViewer(url: photo.url)
                .fitFightTheme(theme)
                .presentationBackground(theme.bg)
        }
    }
}

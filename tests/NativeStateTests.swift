import Foundation

// Production methods are appended by scripts/test_native_state.py. Only their
// platform and network boundaries are replaced so requests can finish out of order.
struct TestUser { let id: UUID }
struct TestSession { let user: TestUser }
struct TestAuth { var currentUser: TestUser? }
struct TestClient { var auth: TestAuth }
enum TestFailure: Error { case offline }
enum FitFightAPIError: Error { case http(status: Int, code: String?, message: String?) }
struct UIImage {}
struct FeedPostDestination {
    var type: String = ""
}
struct TestMedia { let id: UUID }

@MainActor enum MediaUploader {
    static func upload(_ image: UIImage, purpose: String, session: SessionStore, api: FitFightAPI) async throws -> TestMedia {
        throw TestFailure.offline
    }

    static func uploadVideo(_ url: URL, purpose: String, session: SessionStore, api: FitFightAPI) async throws -> TestMedia {
        throw TestFailure.offline
    }
}

@MainActor final class SessionStore {
    var authSession: TestSession?
    var client: TestClient
    var failsToken = false
    var holdsToken = false
    var tokenRequests: [CheckedContinuation<String, Error>] = []

    init(userID: UUID = UUID()) {
        authSession = TestSession(user: TestUser(id: userID))
        client = TestClient(auth: TestAuth(currentUser: TestUser(id: userID)))
    }

    func freshAccessToken() async throws -> String {
        if failsToken { throw TestFailure.offline }
        if holdsToken {
            return try await withCheckedThrowingContinuation { tokenRequests.append($0) }
        }
        return "test-access-token"
    }
}

@MainActor final class HealthKitStepsStore {
    enum SyncTrigger { case foreground, manual }
}

@MainActor enum CompanionPreview {
    static let isEnabled = false
    static let writeUnavailable = "Preview"
}

enum FightRefreshPhase { case idle, readingHealth, uploading, updatingFights }

@MainActor final class AppModel {
    var refreshTask: Task<Void, Never>?
    var refreshLineTask: Task<Void, Never>?
    var refreshUserID: UUID?
    var pendingRefresh: (session: SessionStore, steps: HealthKitStepsStore, trigger: HealthKitStepsStore.SyncTrigger, requestAccess: Bool)?
    var isRefreshingFights = false
    var refreshPhase: FightRefreshPhase = .idle
    var refreshLine = 0
    var companionPreviewNotice: String?
    var started = 0
    var continuations: [CheckedContinuation<Void, Never>] = []
    var accessRequests: [Bool] = []

    func performRefreshFights(session: SessionStore, steps: HealthKitStepsStore, trigger: HealthKitStepsStore.SyncTrigger, requestAccess: Bool) async {
        started += 1
        accessRequests.append(requestAccess)
        await withCheckedContinuation { continuations.append($0) }
    }

    func phaseDuration() async -> Duration {
        let start = ContinuousClock.now
        await holdRefreshPhase(.readingHealth) {}
        return start.duration(to: .now)
    }
}

@MainActor final class FitFightAPI {
    static var commentRequests: [(sort: FightPostCommentSort, cursor: String?)] = []
    static var commentLists: [CheckedContinuation<FitFightFightPostCommentList, Error>] = []
    static var commentCreations: [CheckedContinuation<FitFightFightPostCommentResponse, Error>] = []
    static var commentDeletions: [CheckedContinuation<FitFightFightPostCommentDeletion, Error>] = []
    static var commentReports: [CheckedContinuation<Void, Error>] = []
    static var commentPages: [String: FitFightFightPostCommentList]?

    func fightPostComments(
        postID: UUID,
        cursor: String?,
        accessToken: String,
        sort: FightPostCommentSort = .comments
    ) async throws -> FitFightFightPostCommentList {
        Self.commentRequests.append((sort, cursor))
        if let pages = Self.commentPages {
            guard let page = pages[cursor ?? ""] else { throw TestFailure.offline }
            return page
        }
        return try await withCheckedThrowingContinuation { Self.commentLists.append($0) }
    }
    func createFightPostComment(postID: UUID, body: String, parentID: UUID?, accessToken: String) async throws -> FitFightFightPostCommentResponse {
        try await withCheckedThrowingContinuation { Self.commentCreations.append($0) }
    }
    func deleteFightPostComment(postID: UUID, commentID: UUID, accessToken: String) async throws -> FitFightFightPostCommentDeletion {
        try await withCheckedThrowingContinuation { Self.commentDeletions.append($0) }
    }
    func reportFightPostComment(postID: UUID, commentID: UUID, accessToken: String) async throws {
        try await withCheckedThrowingContinuation { Self.commentReports.append($0) }
    }
    var listRequests = 0
    var listCursors: [String?] = []
    var postRequests: [UUID] = []
    var postResults: [UUID: FitFightFightPost]?
    var reactionRequests = 0
    var lists: [CheckedContinuation<FitFightFightPostList, Error>] = []
    var reactions: [CheckedContinuation<FitFightFightPostReactionList, Error>] = []
    var creations: [CheckedContinuation<FitFightFightPostBatch, Error>] = []
    var deletions: [CheckedContinuation<Void, Error>] = []
    var updates: [CheckedContinuation<FitFightFightPostResponse, Error>] = []

    func feed(cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        listRequests += 1
        listCursors.append(cursor)
        return try await withCheckedThrowingContinuation { lists.append($0) }
    }

    func fightPosts(fightID: UUID, cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        try await feed(cursor: cursor, accessToken: accessToken)
    }

    func fightPost(postID: UUID, accessToken: String) async throws -> FitFightFightPostResponse {
        postRequests.append(postID)
        if let results = postResults {
            guard let post = results[postID] else { throw TestFailure.offline }
            return .init(post: post)
        }
        return try await withCheckedThrowingContinuation { updates.append($0) }
    }

    func reactToFightPost(postID: UUID, emoji: String, accessToken: String) async throws -> FitFightFightPostReactionList {
        reactionRequests += 1
        return try await withCheckedThrowingContinuation { reactions.append($0) }
    }

    func createFeedPosts(body: String, mediaIDs: [UUID], destinations: [FeedPostDestination], taggedUserIDs: [UUID], accessToken: String) async throws -> FitFightFightPostBatch {
        try await withCheckedThrowingContinuation { creations.append($0) }
    }

    func deleteFightPost(postID: UUID, accessToken: String) async throws {
        try await withCheckedThrowingContinuation { deletions.append($0) }
    }

    func updateFightPost(postID: UUID, body: String, accessToken: String) async throws -> FitFightFightPostResponse {
        try await withCheckedThrowingContinuation { updates.append($0) }
    }

    func reportFightPost(postID: UUID, reason: String, accessToken: String) async throws {}
    func blockFeedAuthor(userID: UUID, accessToken: String) async throws {}
}

@MainActor final class RemoteImageLoader {
    enum Kind { case avatar, photo }
    static let shared = RemoteImageLoader()
    func prefetch(_ urls: [URL], kind: Kind) {}
}

@MainActor final class FeedRequestPaths {
    var paths: [String] = []
    func get(path: String, accessToken: String, expected: Set<Int>) async throws -> FitFightFightPostList {
        paths.append(path)
        return .init(posts: [], nextCursor: nil)
    }
}

@MainActor final class FeedRefreshHarness {
    let model = AppModel()
    let session = SessionStore()
    let steps = HealthKitStepsStore()
    let feed = FeedStore()
    var isRefreshingFeed = false
}

@MainActor final class FeedStore {
    var revision = 0
    var posts: [FitFightFightPost] = []
    var nextCursor: String?
    var isLoading = false
    var isLoadingMore = false
    var isSaving = false
    var error: String?
    var moreError: String?
    var reactingPostIDs: Set<UUID> = []
    let api = FitFightAPI()
    var listLoad = 0
    var lastFightID: UUID?
    var cachedUserID: UUID?
    var visiblePostIDs: Set<UUID> = []
    var stalePostIDs: Set<UUID> = []
    var liveLoad = 0
    var needsLiveRefresh = false
}

@MainActor final class FightPostThreadState {
    let post: FitFightFightPost
    let session = SessionStore()
    let feed = FeedStore()
    var comments: [FitFightFightPostComment] = []
    var replyTo: FitFightFightPostComment?
    var draft = ""
    var nextCursor: String?
    var commentSort = FightPostCommentSort.comments
    var loadedCommentSort = FightPostCommentSort.comments
    var loading = false
    var loadingComments = false
    var open = false
    var reloadComments = false
    var commentsVersion = 0
    var targetCommentID: UUID?
    init(post: FitFightFightPost) { self.post = post }
}

@main struct NativeStateTests {
    @MainActor static func main() async {
        var failures = 0
        func check(_ success: Bool, _ message: String) {
            print("\(success ? "PASS" : "FAIL"): \(message)")
            if !success { failures += 1 }
        }

        let model = AppModel()
        let session = SessionStore()
        let steps = HealthKitStepsStore()
        var secondCompleted = false
        let first = Task { await model.refreshFights(session: session, steps: steps) }
        while model.started == 0 { await Task.yield() }
        let second = Task {
            await model.refreshFights(session: session, steps: steps, trigger: .manual, requestAccess: true)
            secondCompleted = true
        }
        try? await Task.sleep(for: .milliseconds(20))
        let third = Task { await model.refreshFights(session: session, steps: steps, trigger: .manual) }
        try? await Task.sleep(for: .milliseconds(20))
        check(!secondCompleted, "overlapping pull waits while sync is suspended")
        model.continuations.removeFirst().resume()
        while model.started < 2 { await Task.yield() }
        check(model.accessRequests == [false, true], "later refresh retains the pending Health permission request")
        model.continuations.removeFirst().resume()
        await first.value
        await second.value
        await third.value
        check(!model.isRefreshingFights, "all refresh callers complete with loading settled")
        check(await model.phaseDuration() < .milliseconds(200), "a completed refresh phase has no forced half-second delay")

        let foreground = AppModel()
        var foregroundCompleted = false
        let foregroundFirst = Task {
            await foreground.refreshFights(session: session, steps: steps)
            foregroundCompleted = true
        }
        let foregroundSecond = Task { await foreground.refreshFights(session: session, steps: steps) }
        while foreground.started == 0 { await Task.yield() }
        try? await Task.sleep(for: .milliseconds(20))
        foreground.continuations.removeFirst().resume()
        while !foregroundCompleted && foreground.started < 2 { await Task.yield() }
        check(foreground.started == 1, "overlapping foreground callers share one HealthKit and standings refresh")
        if foreground.started == 2 { foreground.continuations.removeFirst().resume() }
        await foregroundFirst.value
        await foregroundSecond.value

        let post = FitFightFightPost(
            id: UUID(), audience: "fights", fightId: UUID(), fightName: "Test fight",
            body: "Original", createdAt: "2026-09-15T12:00:00Z",
            author: .init(userId: UUID(), handle: "test", displayName: "Test", avatar: nil),
            media: [], tags: [], reactions: [], commentCount: 0, mine: false
        )
        let reactions = FitFightFightPostReactionList(reactions: [.init(emoji: "👍", count: 1, mine: true)])
        let newerPost = FitFightFightPost(
            id: UUID(), audience: post.audience, fightId: post.fightId, fightName: post.fightName,
            body: "Newer", createdAt: "2026-09-16T12:00:00Z", author: post.author,
            media: [], tags: [], reactions: [], commentCount: 0, mine: false
        )
        let pagedFeed = FeedStore()
        pagedFeed.activate(userID: session.authSession?.user.id)
        pagedFeed.posts = [post]
        let refreshPages = Task { await pagedFeed.load(session: session) }
        while pagedFeed.api.lists.isEmpty { await Task.yield() }
        pagedFeed.api.lists.removeFirst().resume(returning: .init(posts: [newerPost], nextCursor: "older-page"))
        for _ in 0..<100 { await Task.yield() }
        for continuation in pagedFeed.api.lists {
            continuation.resume(returning: .init(posts: [post.updating(commentCount: 1)], nextCursor: nil))
        }
        pagedFeed.api.lists = []
        await refreshPages.value
        check(pagedFeed.api.listRequests == 1 && pagedFeed.posts.map(\.id) == [newerPost.id],
              "pull refresh fetches only the first page instead of refetching all previously loaded pages")

        let paths = FeedRequestPaths()
        _ = try? await paths.feed(cursor: nil, accessToken: "token")
        _ = try? await paths.feed(scope: "fights", cursor: "2026-09-16T12:00:00.123456Z|cursor-id", accessToken: "token")
        _ = try? await paths.fightPosts(fightID: UUID(), cursor: "next-page", accessToken: "token")
        check(paths.paths.allSatisfy { URLComponents(string: $0)?.queryItems?.contains(URLQueryItem(name: "limit", value: "10")) == true },
              "initial and paginated feeds request exactly ten posts through the existing API")
        check(URLComponents(string: paths.paths[1])?.queryItems?.first(where: { $0.name == "cursor" })?.value == "2026-09-16T12:00:00.123456Z|cursor-id",
              "ten-post pagination preserves the server cursor exactly")

        let firstRevision = pagedFeed.revision
        pagedFeed.error = "Earlier refresh failed"
        let nextPage = Task { await pagedFeed.load(session: session, more: true) }
        while pagedFeed.api.lists.isEmpty { await Task.yield() }
        await pagedFeed.load(session: session, more: true)
        check(pagedFeed.api.listRequests == 2 && pagedFeed.api.listCursors.last! == "older-page" && pagedFeed.isLoadingMore,
              "overlapping infinite-scroll triggers share one next-page request")
        pagedFeed.api.lists.removeFirst().resume(returning: .init(posts: [newerPost, post], nextCursor: "last-page"))
        await nextPage.value
        check(pagedFeed.posts.map(\.id) == [newerPost.id, post.id] && pagedFeed.revision == firstRevision,
              "pagination appends unique posts without reordering existing cards or reloading their threads")
        check(pagedFeed.error == "Earlier refresh failed", "appending a page does not change the screen header above existing cards")

        let pull = FeedRefreshHarness()
        let pulling = Task { await pull.refreshForTest() }
        for _ in 0..<100 { await Task.yield() }
        check(pull.feed.api.listRequests == 1 && pull.model.started == 0 && pull.isRefreshingFeed,
              "pull-to-refresh immediately requests feed data without starting or waiting for HealthKit sync")
        if pull.feed.api.lists.isEmpty {
            for continuation in pull.model.continuations { continuation.resume() }
            pull.model.continuations = []
        }
        while pull.feed.api.lists.isEmpty { await Task.yield() }
        pull.feed.api.lists.removeFirst().resume(returning: .init(posts: [newerPost], nextCursor: nil))
        await pulling.value
        check(pull.feed.posts.map(\.id) == [newerPost.id] && !pull.isRefreshingFeed,
              "the refresh indicator waits for the actual server response")

        let stalePage = Task { await pagedFeed.load(session: session, more: true) }
        while pagedFeed.api.lists.isEmpty { await Task.yield() }
        let freshPage = Task { await pagedFeed.load(session: session) }
        while pagedFeed.api.lists.count < 2 { await Task.yield() }
        pagedFeed.api.lists.removeLast().resume(returning: .init(posts: [newerPost], nextCursor: "fresh-cursor"))
        await freshPage.value
        pagedFeed.api.lists.removeFirst().resume(returning: .init(posts: [post], nextCursor: nil))
        await stalePage.value
        check(pagedFeed.posts.map(\.id) == [newerPost.id] && pagedFeed.nextCursor == "fresh-cursor",
              "pull refresh supersedes an older next-page request and its cursor")

        let failedPage = Task { await pagedFeed.load(session: session, more: true) }
        while pagedFeed.api.lists.isEmpty { await Task.yield() }
        pagedFeed.api.lists.removeFirst().resume(throwing: TestFailure.offline)
        await failedPage.value
        check(pagedFeed.posts.map(\.id) == [newerPost.id] && pagedFeed.moreError != nil && pagedFeed.error == nil && pagedFeed.nextCursor == "fresh-cursor",
              "pagination failure retains the reading position and retry cursor without adding an error above the feed")
        pagedFeed.nextCursor = nil
        let requestsAtEnd = pagedFeed.api.listRequests
        await pagedFeed.load(session: session, more: true)
        check(pagedFeed.api.listRequests == requestsAtEnd && !pagedFeed.isLoadingMore,
              "an exhausted feed makes no further page requests")

        let visibleFeed = FeedStore()
        visibleFeed.activate(userID: session.authSession?.user.id)
        visibleFeed.posts = [newerPost, post]
        visibleFeed.nextCursor = "keep-cursor"
        visibleFeed.visiblePostIDs = [post.id]
        let livePost = Task { await visibleFeed.refreshVisible(session: session) }
        while visibleFeed.api.updates.isEmpty { await Task.yield() }
        check(visibleFeed.api.postRequests == [post.id] && visibleFeed.api.listRequests == 0,
              "a live event fetches the visible older post without replaying feed pages")
        visibleFeed.api.updates.removeFirst().resume(returning: .init(post: post.updating(commentCount: 2)))
        await livePost.value
        check(visibleFeed.posts.map(\.id) == [newerPost.id, post.id] && visibleFeed.posts.last?.commentCount == 2 && visibleFeed.nextCursor == "keep-cursor",
              "background refresh updates comments in place without changing the pagination cursor")
        check(visibleFeed.stalePostIDs == [newerPost.id], "offscreen posts remain marked for refresh when they reappear")
        visibleFeed.visiblePostIDs = [newerPost.id]
        let reappeared = Task { await visibleFeed.refreshVisible(session: session, invalidate: false) }
        while visibleFeed.api.updates.isEmpty { await Task.yield() }
        visibleFeed.api.updates.removeFirst().resume(returning: .init(post: newerPost.updating(commentCount: 1)))
        await reappeared.value
        check(visibleFeed.stalePostIDs.isEmpty && visibleFeed.posts.first?.commentCount == 1,
              "returning to an invalidated cached card gets fresh data")

        let liveDuringPage = Task { await visibleFeed.load(session: session, more: true) }
        while visibleFeed.api.lists.isEmpty { await Task.yield() }
        await visibleFeed.refreshVisible(session: session)
        visibleFeed.api.lists.removeFirst().resume(returning: .init(posts: [], nextCursor: nil))
        while visibleFeed.api.updates.isEmpty { await Task.yield() }
        visibleFeed.api.updates.removeFirst().resume(returning: .init(post: newerPost.updating(commentCount: 3)))
        await liveDuringPage.value
        check(visibleFeed.posts.first?.commentCount == 3 && !visibleFeed.needsLiveRefresh,
              "a live event during pagination is reconciled after the page completes")

        for more in [false, true] {
            let arriving = FeedStore()
            arriving.activate(userID: session.authSession?.user.id)
            arriving.posts = more ? [post] : []
            arriving.nextCursor = more ? "next-page" : nil
            let page = Task { await arriving.load(session: session, more: more) }
            while arriving.api.lists.isEmpty { await Task.yield() }
            await arriving.refreshVisible(session: session)
            arriving.api.lists.removeFirst().resume(returning: .init(posts: [newerPost], nextCursor: "older-page"))
            await page.value
            check(arriving.stalePostIDs.contains(newerPost.id),
                  "an event during \(more ? "pagination" : "initial load") invalidates posts in the arriving snapshot")
            arriving.visiblePostIDs = [newerPost.id]
            arriving.api.postResults = [newerPost.id: newerPost.updating(commentCount: 9)]
            if arriving.stalePostIDs.contains(newerPost.id) {
                await arriving.refreshVisible(session: session, invalidate: false)
            }
            check(arriving.posts.last?.commentCount == 9 && arriving.nextCursor == "older-page",
                  "an arriving stale card refreshes on appearance without losing its pagination cursor")
        }

        for pageFinishesFirst in [false, true] {
            let overlapping = FeedStore()
            overlapping.activate(userID: session.authSession?.user.id)
            overlapping.posts = [post]
            overlapping.nextCursor = "next-page"
            overlapping.visiblePostIDs = [post.id]
            let live = Task { await overlapping.refreshVisible(session: session) }
            while overlapping.api.updates.isEmpty { await Task.yield() }
            let page = Task { await overlapping.load(session: session, more: true) }
            while overlapping.api.lists.isEmpty { await Task.yield() }
            overlapping.api.postResults = [post.id: post.updating(commentCount: 7)]
            if pageFinishesFirst {
                overlapping.api.lists.removeFirst().resume(returning: .init(posts: [newerPost], nextCursor: nil))
                await page.value
            }
            overlapping.api.updates.removeFirst().resume(returning: .init(post: post.updating(commentCount: 7)))
            await live.value
            if !pageFinishesFirst {
                overlapping.api.lists.removeFirst().resume(returning: .init(posts: [newerPost], nextCursor: nil))
                await page.value
            }
            check(overlapping.posts.first?.commentCount == 7 && overlapping.posts.map(\.id) == [post.id, newerPost.id],
                  "pagination reconciles an earlier live read when \(pageFinishesFirst ? "the page" : "the live read") finishes first")
        }

        let oldLiveRead = Task { await visibleFeed.refreshVisible(session: session) }
        while visibleFeed.api.updates.isEmpty { await Task.yield() }
        visibleFeed.activate(userID: UUID())
        visibleFeed.api.updates.removeFirst().resume(returning: .init(post: newerPost))
        await oldLiveRead.value
        check(visibleFeed.posts.isEmpty && visibleFeed.visiblePostIDs.isEmpty && visibleFeed.stalePostIDs.isEmpty,
              "an old account's live read cannot restore its cached posts after account change")
        let feed = FeedStore()
        feed.cachedUserID = session.authSession?.user.id
        feed.posts = [post]
        feed.error = "Earlier error"
        let reaction = Task { await feed.react(session: session, post: post, emoji: "👍") }
        while feed.api.reactionRequests == 0 { await Task.yield() }
        check(feed.posts[0].reactions == reactions.reactions, "reaction count and selection update while HTTP is suspended")
        let duplicate = Task { await feed.react(session: session, post: post, emoji: "👍") }
        try? await Task.sleep(for: .milliseconds(20))
        check(feed.api.reactionRequests == 1, "repeat reaction taps cannot toggle the same post twice in flight")
        feed.posts = [post.updating(commentCount: 3)]
        for continuation in feed.api.reactions { continuation.resume(returning: reactions) }
        feed.api.reactions = []
        await reaction.value
        await duplicate.value
        check(feed.posts[0].commentCount == 3, "reaction response preserves a comment update received while waiting")
        check(feed.posts[0].reactions == reactions.reactions && feed.error == nil, "successful reaction updates the post and clears its old error")
        check(feed.reactingPostIDs.isEmpty, "reaction controls unlock when the request completes")

        let selected = feed.posts[0]
        let removeReaction = Task { await feed.react(session: session, post: selected, emoji: "👍") }
        while feed.api.reactions.isEmpty { await Task.yield() }
        check(feed.posts[0].reactions.isEmpty, "tapping the selected reaction removes it immediately")
        feed.posts[0] = feed.posts[0].updating(commentCount: 4)
        feed.api.reactions.removeFirst().resume(throwing: TestFailure.offline)
        await removeReaction.value
        check(feed.posts[0].reactions == selected.reactions && feed.error != nil, "failed reaction restores selection and shows an error")
        check(feed.posts[0].commentCount == 4, "reaction rollback preserves concurrent comments")

        let switchReaction = Task { await feed.react(session: session, post: selected, emoji: "🔥") }
        while feed.api.reactions.isEmpty { await Task.yield() }
        check(feed.posts[0].reactions == [.init(emoji: "🔥", count: 1, mine: true)], "switching emoji immediately moves the selection")
        let newSession = SessionStore()
        feed.activate(userID: newSession.authSession?.user.id)
        feed.posts = [post]
        let newReaction = Task { await feed.react(session: newSession, post: post, emoji: "💪") }
        while feed.api.reactions.count < 2 { await Task.yield() }
        feed.api.reactions.removeFirst().resume(returning: reactions)
        await switchReaction.value
        check(feed.posts[0].reactions == [.init(emoji: "💪", count: 1, mine: true)], "old-account completion cannot overwrite a new account's reaction")
        check(feed.reactingPostIDs.contains(post.id), "old-account completion cannot unlock the new account's request")
        feed.api.reactions.removeFirst().resume(returning: .init(reactions: [.init(emoji: "💪", count: 1, mine: true)]))
        await newReaction.value

        let otherSession = SessionStore()
        otherSession.failsToken = true
        await feed.load(session: otherSession)
        check(feed.posts.isEmpty, "a new account cannot see the previous account's feed when loading fails")

        let pending = FeedStore()
        pending.activate(userID: session.authSession?.user.id)
        pending.posts = [post]
        let pendingReaction = Task { await pending.react(session: session, post: post, emoji: "👍") }
        while pending.api.reactions.isEmpty { await Task.yield() }
        let duringReaction = Task { await pending.load(session: session) }
        while pending.api.lists.isEmpty { await Task.yield() }
        pending.api.lists.removeFirst().resume(returning: .init(posts: [post], nextCursor: nil))
        await duringReaction.value
        check(pending.posts[0].reactions == reactions.reactions, "feed reload preserves the optimistic reaction while HTTP is pending")
        let editDuringReaction = Task { await pending.update(session: session, post: post, body: post.body) }
        while pending.api.updates.isEmpty { await Task.yield() }
        pending.api.updates.removeFirst().resume(returning: .init(post: post))
        _ = await editDuringReaction.value
        check(pending.posts[0].reactions == reactions.reactions, "an edit response preserves the optimistic reaction while HTTP is pending")
        pending.api.reactions.removeFirst().resume(returning: reactions)
        await pendingReaction.value

        let delayed = FeedStore()
        let oldSession = SessionStore()
        let load = Task { await delayed.load(session: oldSession) }
        while delayed.api.listRequests == 0 { await Task.yield() }
        oldSession.authSession = nil
        oldSession.client.auth.currentUser = nil
        delayed.api.lists.removeFirst().resume(returning: .init(posts: [post], nextCursor: nil))
        await load.value
        check(delayed.posts.isEmpty, "a feed response arriving after signout cannot repopulate private posts")

        let mutations = FeedStore()
        mutations.activate(userID: session.authSession?.user.id)
        mutations.posts = [post]
        let create = Task {
            await mutations.create(session: session, destinations: [FeedPostDestination()], body: "A post", images: [])
        }
        let update = Task { await mutations.update(session: session, post: post, body: "Edited") }
        let delete = Task { await mutations.delete(session: session, post: post) }
        while mutations.api.creations.isEmpty || mutations.api.updates.isEmpty || mutations.api.deletions.isEmpty {
            await Task.yield()
        }
        mutations.activate(userID: otherSession.authSession?.user.id)
        mutations.posts = [post.updating(commentCount: 8)]
        mutations.isSaving = true
        mutations.error = "New account error"
        mutations.api.creations.removeFirst().resume(returning: .init(posts: [post]))
        mutations.api.updates.removeFirst().resume(returning: .init(post: post))
        mutations.api.deletions.removeFirst().resume()
        let oldCreateCompleted = await create.value
        let oldUpdateCompleted = await update.value
        await delete.value
        check(!oldCreateCompleted && !oldUpdateCompleted, "old-account save completions do not dismiss a new account's composer")
        check(mutations.posts == [post.updating(commentCount: 8)], "old-account edit and deletion responses cannot replace the new feed")
        check(mutations.isSaving && mutations.error == "New account error", "old-account completions preserve the new account's saving and error state")

        let sortAuthor = FitFightFightPost.Author(userId: UUID(), handle: "test", displayName: "Test", avatar: nil)
        let quiet = FitFightFightPostComment(
            id: UUID(), postId: post.id, parentId: nil, body: "Quiet",
            createdAt: "2026-09-16T12:00:00Z", author: sortAuthor, mine: false
        )
        let busy = FitFightFightPostComment(
            id: UUID(), postId: post.id, parentId: nil, body: "Busy",
            createdAt: "2026-09-16T11:00:00Z", author: sortAuthor, mine: false
        )
        let reply = FitFightFightPostComment(
            id: UUID(), postId: post.id, parentId: busy.id, body: "Reply",
            createdAt: "2026-09-16T11:30:00Z", author: sortAuthor, mine: false
        )
        let sortThread = FightPostThreadState(post: post)
        sortThread.comments = [quiet, busy, reply]
        check(sortThread.rowsForTest().map(\.0) == [busy.id, reply.id, quiet.id], "most comments shows the busiest thread first")
        sortThread.commentSort = .recent
        check(sortThread.rowsForTest().map(\.0) == [quiet.id, busy.id, reply.id], "most recent shows the newest root first")

        let thread = FightPostThreadState(post: post)
        let orphan = FitFightFightPostComment(
            id: UUID(), postId: post.id, parentId: UUID(), body: "Visible reply to hidden author",
            createdAt: post.createdAt, author: post.author, mine: false
        )
        let child = FitFightFightPostComment(
            id: UUID(), postId: post.id, parentId: orphan.id, body: "Reply",
            createdAt: post.createdAt, author: post.author, mine: false
        )
        let grandchild = FitFightFightPostComment(
            id: UUID(), postId: post.id, parentId: child.id, body: "Nested reply",
            createdAt: post.createdAt, author: post.author, mine: false
        )
        thread.comments = [orphan, child, grandchild]
        let refreshedThread = FightPostThreadState(post: post.updating(commentCount: 2))
        refreshedThread.comments = [orphan]
        refreshedThread.open = true
        refreshedThread.countChangedForTest(previous: 1, count: 2)
        try? await Task.sleep(for: .milliseconds(30))
        let requestedComments = !FitFightAPI.commentLists.isEmpty
        for continuation in FitFightAPI.commentLists {
            continuation.resume(returning: .init(comments: [orphan, child], nextCursor: nil))
        }
        FitFightAPI.commentLists = []
        try? await Task.sleep(for: .milliseconds(30))
        check(requestedComments && refreshedThread.comments.contains(child), "a peer comment appears in an already-open thread when its count refreshes")
        let duringRead = Task { await refreshedThread.loadForTest() }
        while FitFightAPI.commentLists.isEmpty { await Task.yield() }
        refreshedThread.countChangedForTest(previous: 2, count: 3)
        while !refreshedThread.reloadComments { await Task.yield() }
        FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: [orphan, child], nextCursor: nil))
        while FitFightAPI.commentLists.isEmpty { await Task.yield() }
        FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: [orphan, child, grandchild], nextCursor: nil))
        await duringRead.value
        check(refreshedThread.comments.contains(grandchild), "a comment arriving during a read queues another read")

        for queuedRefresh in [false, true] {
            let failedThread = FightPostThreadState(post: post.updating(commentCount: 2))
            failedThread.comments = [orphan]
            let failingRead = Task { await failedThread.loadForTest() }
            while FitFightAPI.commentLists.isEmpty { await Task.yield() }
            if queuedRefresh { await failedThread.loadForTest() }
            let requestsBeforeFailure = FitFightAPI.commentRequests.count
            FitFightAPI.commentPages = ["": .init(comments: [orphan, child], nextCursor: nil)]
            FitFightAPI.commentLists.removeFirst().resume(throwing: TestFailure.offline)
            await failingRead.value
            check(FitFightAPI.commentRequests.count == requestsBeforeFailure + (queuedRefresh ? 1 : 0),
                  "a failed comment read only runs another request when a refresh was already queued")
            check(failedThread.comments == (queuedRefresh ? [orphan, child] : [orphan]) && !failedThread.loadingComments,
                  "\(queuedRefresh ? "a queued refresh updates" : "an unqueued failure preserves") the thread after an earlier read fails")
            check(queuedRefresh ? failedThread.feed.error == nil : failedThread.feed.error != nil,
                  "a recovered queued refresh does not leave the earlier error visible")
            FitFightAPI.commentPages = nil
        }

        let changingSort = Task { await refreshedThread.loadForTest() }
        while FitFightAPI.commentLists.isEmpty { await Task.yield() }
        refreshedThread.commentSort = .recent
        refreshedThread.sortChangedForTest()
        while !refreshedThread.reloadComments { await Task.yield() }
        FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: [orphan], nextCursor: "old-sort"))
        while FitFightAPI.commentLists.isEmpty { await Task.yield() }
        check(FitFightAPI.commentRequests.last?.sort == .recent && FitFightAPI.commentRequests.last?.cursor == nil,
              "a sort change restarts the first page instead of reusing the previous order's cursor")
        check(refreshedThread.comments.contains(grandchild), "an older sort response cannot replace the displayed comments")
        FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: [grandchild, child, orphan], nextCursor: nil))
        await changingSort.value
        check(refreshedThread.comments.first?.id == grandchild.id, "the queued refresh uses the current comment order")

        let pagedThread = FightPostThreadState(post: post.updating(commentCount: 3))
        pagedThread.targetCommentID = grandchild.id
        let targeted = Task { await pagedThread.loadForTest() }
        while FitFightAPI.commentLists.isEmpty { await Task.yield() }
        FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: [orphan, child], nextCursor: "page-two"))
        while FitFightAPI.commentLists.isEmpty { await Task.yield() }
        FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: [grandchild], nextCursor: nil))
        await targeted.value
        check(pagedThread.comments == [orphan, child, grandchild], "a notification loads comments through the targeted page")

        let commentHistory = (0..<45).map { index in
            FitFightFightPostComment(
                id: UUID(), postId: post.id, parentId: nil, body: "Comment \(index)",
                createdAt: post.createdAt, author: post.author, mine: false
            )
        }
        for changeSort in [false, true] {
            let interruptedPage = FightPostThreadState(post: post.updating(commentCount: 45))
            let pages: [String: FitFightFightPostCommentList] = [
                "": .init(comments: Array(commentHistory.prefix(40)), nextCursor: "older-comments"),
                "older-comments": .init(comments: Array(commentHistory.suffix(5)), nextCursor: nil),
            ]
            FitFightAPI.commentPages = pages
            await interruptedPage.loadForTest()
            FitFightAPI.commentPages = nil
            let moreComments = Task { await interruptedPage.loadForTest(more: true) }
            while FitFightAPI.commentLists.isEmpty { await Task.yield() }
            check(FitFightAPI.commentRequests.last?.cursor == "older-comments", "More comments requests the next page")
            if changeSort {
                interruptedPage.commentSort = .recent
                interruptedPage.sortChangedForTest()
                while !interruptedPage.reloadComments { await Task.yield() }
            } else {
                await interruptedPage.loadForTest()
            }
            FitFightAPI.commentPages = pages
            FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: Array(commentHistory.suffix(5)), nextCursor: nil))
            await moreComments.value
            check(interruptedPage.comments == (changeSort ? Array(commentHistory.prefix(40)) : commentHistory),
                  changeSort ? "changing sort during pagination starts at the new first page" : "a live update during More comments preserves the requested next page")
            check(interruptedPage.nextCursor == (changeSort ? "older-comments" : nil) && !interruptedPage.loadingComments,
                  "interrupted comment pagination settles at the cursor for the displayed pages")
            FitFightAPI.commentPages = nil
        }

        let retainedThread = FightPostThreadState(post: post.updating(commentCount: 45))
        retainedThread.commentSort = .recent
        FitFightAPI.commentPages = [
            "": .init(comments: Array(commentHistory.prefix(40)), nextCursor: "older-comments"),
            "older-comments": .init(comments: Array(commentHistory.suffix(5)), nextCursor: nil),
        ]
        await retainedThread.loadForTest()
        await retainedThread.loadForTest(more: true)
        check(retainedThread.comments == commentHistory, "More comments loads both pages before an automatic refresh")
        FitFightAPI.commentPages?["older-comments"] = .init(comments: Array(commentHistory[40..<44]), nextCursor: nil)
        await retainedThread.loadForTest()
        check(retainedThread.comments == Array(commentHistory.prefix(44)) && retainedThread.nextCursor == nil,
              "automatic refresh preserves older loaded comments and removes a deleted comment")

        let beforeFailedRefresh = retainedThread.comments
        FitFightAPI.commentPages = ["": .init(comments: Array(commentHistory.prefix(40)), nextCursor: "unavailable-page")]
        await retainedThread.loadForTest()
        check(retainedThread.comments == beforeFailedRefresh && retainedThread.nextCursor == nil && retainedThread.feed.error != nil,
              "a failed later refresh page leaves the complete loaded thread and cursor intact")

        let rankedThread = FightPostThreadState(post: post.updating(commentCount: 45))
        rankedThread.comments = Array(commentHistory.prefix(40))
        rankedThread.feed.posts = [post.updating(commentCount: 45)]
        rankedThread.draft = "A new lower-ranked comment"
        let rankedSend = Task { await rankedThread.sendForTest() }
        while FitFightAPI.commentCreations.isEmpty { await Task.yield() }
        let confirmedComment = commentHistory[44]
        FitFightAPI.commentCreations.removeFirst().resume(returning: .init(comment: confirmedComment, commentCount: 46))
        await rankedSend.value
        FitFightAPI.commentPages = [
            "": .init(comments: Array(commentHistory.prefix(40)), nextCursor: "lower-ranked"),
            "lower-ranked": .init(comments: Array(commentHistory.suffix(5)), nextCursor: nil),
        ]
        await rankedThread.loadForTest()
        check(rankedThread.comments.contains(confirmedComment),
              "automatic ranked refresh retains a confirmed local comment outside the first page")
        FitFightAPI.commentPages = nil

        check(thread.rowsForTest().map { $0.0 } == [orphan.id, child.id, grandchild.id], "visible replies survive when their parent author is hidden")
        check(thread.rowsForTest().map { $0.1 } == [0, 1, 2], "children of a hidden-parent reply retain their nesting")
        thread.replyTo = grandchild
        thread.feed.posts = [post.updating(reactions: reactions.reactions, commentCount: 12)]
        let parentDeletion = Task { await thread.deleteForTest(orphan) }
        while FitFightAPI.commentDeletions.isEmpty { await Task.yield() }
        FitFightAPI.commentDeletions.removeFirst().resume(returning: .init(deleted: true, commentCount: 2))
        await parentDeletion.value
        check(thread.comments.isEmpty && thread.replyTo == nil, "deleting a comment removes all loaded descendants and cancels replies to them")
        check(thread.feed.posts[0].commentCount == 2, "deletion uses the server count including unloaded descendants")
        check(thread.feed.posts[0].reactions == reactions.reactions, "authoritative comment count preserves current reactions")

        thread.draft = "Another comment"
        let creation = Task { await thread.sendForTest() }
        while FitFightAPI.commentCreations.isEmpty { await Task.yield() }
        thread.comments = [child]
        thread.feed.posts = [post.updating(reactions: reactions.reactions, commentCount: 3)]
        thread.feed.reactingPostIDs = [post.id]
        FitFightAPI.commentCreations.removeFirst().resume(returning: .init(comment: child, commentCount: 3))
        await creation.value
        check(thread.feed.posts[0].commentCount == 3, "comment creation does not double-count a concurrent feed refresh containing its committed comment")
        check(thread.comments == [child], "comment creation does not duplicate a concurrently loaded comment")
        check(thread.feed.posts[0].reactions == reactions.reactions && thread.feed.reactingPostIDs.contains(post.id), "comment creation preserves a pending reaction")

        for fails in [false, true] {
            let stale = FightPostThreadState(post: post)
            stale.comments = [orphan, child]
            stale.draft = "Old draft"
            stale.replyTo = child
            let load = Task { await stale.loadForTest() }
            let send = Task { await stale.sendForTest() }
            let remove = Task { await stale.deleteForTest(orphan) }
            let report = Task { await stale.reportForTest(child) }
            while FitFightAPI.commentLists.isEmpty || FitFightAPI.commentCreations.isEmpty || FitFightAPI.commentDeletions.isEmpty || FitFightAPI.commentReports.isEmpty {
                await Task.yield()
            }
            stale.session.authSession = TestSession(user: TestUser(id: UUID()))
            stale.feed.activate(userID: stale.session.authSession?.user.id)
            stale.feed.posts = [post.updating(commentCount: 8)]
            stale.feed.error = "New account error"
            stale.draft = "New draft"
            stale.nextCursor = "New cursor"
            stale.loading = true
            if fails {
                FitFightAPI.commentLists.removeFirst().resume(throwing: TestFailure.offline)
                FitFightAPI.commentCreations.removeFirst().resume(throwing: TestFailure.offline)
                FitFightAPI.commentDeletions.removeFirst().resume(throwing: TestFailure.offline)
                FitFightAPI.commentReports.removeFirst().resume(throwing: TestFailure.offline)
            } else {
                FitFightAPI.commentLists.removeFirst().resume(returning: .init(comments: [grandchild], nextCursor: "Old cursor"))
                FitFightAPI.commentCreations.removeFirst().resume(returning: .init(comment: grandchild, commentCount: 3))
                FitFightAPI.commentDeletions.removeFirst().resume(returning: .init(deleted: true, commentCount: 0))
                FitFightAPI.commentReports.removeFirst().resume()
            }
            await load.value
            await send.value
            await remove.value
            await report.value
            check(stale.comments == [orphan, child] && stale.nextCursor == "New cursor", "old-account comment \(fails ? "failures" : "responses") preserve the new thread")
            check(stale.draft == "New draft" && stale.replyTo == child && stale.loading, "old-account comment completions preserve the new account's draft, reply, and loading state")
            check(stale.feed.posts[0].commentCount == 8 && stale.feed.error == "New account error", "old-account comment \(fails ? "failures" : "responses") cannot overwrite shared feed state")
        }

        let tokenSwitch = FightPostThreadState(post: post)
        tokenSwitch.session.holdsToken = true
        tokenSwitch.draft = "A comment"
        let tokenLoad = Task { await tokenSwitch.loadForTest() }
        let tokenSend = Task { await tokenSwitch.sendForTest() }
        let tokenDelete = Task { await tokenSwitch.deleteForTest(child) }
        let tokenReport = Task { await tokenSwitch.reportForTest(child) }
        while tokenSwitch.session.tokenRequests.count < 4 { await Task.yield() }
        tokenSwitch.session.authSession = nil
        for continuation in tokenSwitch.session.tokenRequests { continuation.resume(returning: "old-token") }
        tokenSwitch.session.tokenRequests = []
        try? await Task.sleep(for: .milliseconds(20))
        let sentAfterSignOut = !FitFightAPI.commentLists.isEmpty || !FitFightAPI.commentCreations.isEmpty
            || !FitFightAPI.commentDeletions.isEmpty || !FitFightAPI.commentReports.isEmpty
        for continuation in FitFightAPI.commentLists { continuation.resume(throwing: TestFailure.offline) }
        for continuation in FitFightAPI.commentCreations { continuation.resume(throwing: TestFailure.offline) }
        for continuation in FitFightAPI.commentDeletions { continuation.resume(throwing: TestFailure.offline) }
        for continuation in FitFightAPI.commentReports { continuation.resume(throwing: TestFailure.offline) }
        await tokenLoad.value
        await tokenSend.value
        await tokenDelete.value
        await tokenReport.value
        check(!sentAfterSignOut, "comment operations stop after sign-out during token refresh")

        if failures != 0 { exit(1) }
    }
}

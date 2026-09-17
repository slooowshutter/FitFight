import Foundation

// Production methods are appended by scripts/test_native_state.py. Only their
// platform and network boundaries are replaced so requests can finish out of order.
struct TestUser { let id: UUID }
struct TestSession { let user: TestUser }
struct TestAuth { var currentUser: TestUser? }
struct TestClient { var auth: TestAuth }
enum TestFailure: Error { case offline }
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
    static var commentLists: [CheckedContinuation<FitFightFightPostCommentList, Error>] = []
    static var commentCreations: [CheckedContinuation<FitFightFightPostCommentResponse, Error>] = []
    static var commentDeletions: [CheckedContinuation<FitFightFightPostCommentDeletion, Error>] = []
    static var commentReports: [CheckedContinuation<Void, Error>] = []
    static var feedbackLists: [CheckedContinuation<FitFightFeedbackList, Error>] = []
    static var feedbackDetails: [CheckedContinuation<FitFightFeedbackDetail, Error>] = []
    static var feedbackDeletions: [CheckedContinuation<Void, Error>] = []

    func listFeedback(kind: String?, accessToken: String) async throws -> FitFightFeedbackList {
        try await withCheckedThrowingContinuation { Self.feedbackLists.append($0) }
    }
    func feedbackDetail(postID: UUID, accessToken: String) async throws -> FitFightFeedbackDetail {
        try await withCheckedThrowingContinuation { Self.feedbackDetails.append($0) }
    }
    func deleteFeedbackPost(postID: UUID, accessToken: String) async throws {
        try await withCheckedThrowingContinuation { Self.feedbackDeletions.append($0) }
    }

    func fightPostComments(
        postID: UUID,
        cursor: String?,
        accessToken: String,
        sort: FightPostCommentSort = .comments
    ) async throws -> FitFightFightPostCommentList {
        try await withCheckedThrowingContinuation { Self.commentLists.append($0) }
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
    var reactionRequests = 0
    var lists: [CheckedContinuation<FitFightFightPostList, Error>] = []
    var reactions: [CheckedContinuation<FitFightFightPostReactionList, Error>] = []
    var creations: [CheckedContinuation<FitFightFightPostBatch, Error>] = []
    var deletions: [CheckedContinuation<Void, Error>] = []
    var updates: [CheckedContinuation<FitFightFightPostResponse, Error>] = []

    func feed(cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        listRequests += 1
        return try await withCheckedThrowingContinuation { lists.append($0) }
    }

    func fightPosts(fightID: UUID, cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        try await feed(cursor: cursor, accessToken: accessToken)
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

@MainActor final class FeedStore {
    var posts: [FitFightFightPost] = []
    var nextCursor: String?
    var isLoading = false
    var isSaving = false
    var error: String?
    var reactingPostIDs: Set<UUID> = []
    let api = FitFightAPI()
    var listLoad = 0
    var lastFightID: UUID?
    var cachedUserID: UUID?
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
    var commentsLoad = 0
    var loading = false
    var loadingComments = false
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

        let requestA = FitFightFeedbackPost(
            id: UUID(), kind: "feature", title: "First request", body: "Delete this request",
            voteCount: 0, commentCount: 0, voted: false,
            authorId: UUID(), authorHandle: "test", mine: false, createdAt: Date()
        )
        var requestB = requestA
        requestB.id = UUID()
        requestB.kind = "bug"
        let requestComment = FitFightFeedbackComment(id: UUID(), body: "Keep this comment", authorHandle: "test", createdAt: Date())
        for detailFinishesFirst in [false, true] {
            let feedback = FeedbackStore()
            feedback.posts = [requestA, requestB]
            let initialDetail = Task { await feedback.loadDetail(session: session, postID: requestA.id) }
            while FitFightAPI.feedbackDetails.isEmpty { await Task.yield() }
            FitFightAPI.feedbackDetails.removeFirst().resume(returning: .init(post: requestA, comments: []))
            await initialDetail.value

            let deletion = Task { await feedback.delete(session: session, postID: requestA.id) }
            while FitFightAPI.feedbackDeletions.isEmpty { await Task.yield() }
            let nextDetail = Task { await feedback.loadDetail(session: session, postID: requestB.id) }
            while FitFightAPI.feedbackDetails.isEmpty { await Task.yield() }
            if detailFinishesFirst {
                FitFightAPI.feedbackDetails.removeFirst().resume(returning: .init(post: requestB, comments: [requestComment]))
                await nextDetail.value
                feedback.error = "New request error"
            }
            FitFightAPI.feedbackDeletions.removeFirst().resume()
            check(await deletion.value, "feedback deletion succeeds after navigating to another request")
            check(feedback.posts == [requestB], "feedback deletion removes only its own board row")
            if detailFinishesFirst {
                check(feedback.error == "New request error", "deletion preserves an error on the newly opened request")
            } else {
                check(feedback.isLoading, "deletion keeps the new request's pending loading state")
                FitFightAPI.feedbackDetails.removeFirst().resume(returning: .init(post: requestB, comments: [requestComment]))
                await nextDetail.value
            }
            check(feedback.detail == requestB && feedback.comments == [requestComment], "new request detail and comments survive either deletion completion order")
            check(feedback.canDelete && feedback.canLaunchFix && !feedback.isLoading, "new request admin actions load and its spinner settles")
        }

        for deletionFails in [false, true] {
            let feedback = FeedbackStore()
            feedback.posts = [requestA]
            let initialDetail = Task { await feedback.loadDetail(session: session, postID: requestA.id) }
            while FitFightAPI.feedbackDetails.isEmpty { await Task.yield() }
            FitFightAPI.feedbackDetails.removeFirst().resume(returning: .init(post: requestA, comments: []))
            await initialDetail.value
            let deletion = Task { await feedback.delete(session: session, postID: requestA.id) }
            let staleDetail = Task { await feedback.loadDetail(session: session, postID: requestA.id) }
            let listReload = Task { await feedback.load(session: session, kind: nil) }
            while FitFightAPI.feedbackDeletions.isEmpty || FitFightAPI.feedbackDetails.isEmpty || FitFightAPI.feedbackLists.isEmpty {
                await Task.yield()
            }
            if deletionFails {
                FitFightAPI.feedbackDeletions.removeFirst().resume(throwing: TestFailure.offline)
            } else {
                FitFightAPI.feedbackDeletions.removeFirst().resume()
            }
            check(await deletion.value == !deletionFails, "feedback deletion reports its actual result")
            if deletionFails {
                check(feedback.detail == requestA && feedback.error != nil, "failed deletion retains the request and shows its error")
            }
            FitFightAPI.feedbackDetails.removeFirst().resume(returning: .init(post: requestA, comments: [requestComment]))
            await staleDetail.value
            FitFightAPI.feedbackLists.removeFirst().resume(returning: .init(posts: [requestA, requestB]))
            await listReload.value
            check(feedback.posts == (deletionFails ? [requestA, requestB] : [requestB]), "list reload excludes a deleted request but still accepts other rows")
            check(feedback.detail == (deletionFails ? requestA : nil), "stale detail cannot restore a successfully deleted request")
            check(!feedback.isLoading && !feedback.isDeleting, "feedback loading and deletion flags settle after pending requests finish")
        }

        if failures != 0 { exit(1) }
    }
}

extension FitFightFeedbackDetail {
    init(post: FitFightFeedbackPost, comments: [FitFightFeedbackComment]) {
        self.post = post
        self.comments = comments
        canLaunchFix = true
        canDelete = true
    }
}

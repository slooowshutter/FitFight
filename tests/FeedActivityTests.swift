import Foundation

protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
struct User { let id: UUID }
struct Session { let user: User }
enum Failure: Error { case offline }

@MainActor final class SessionStore {
    var authSession: Session? = Session(user: User(id: UUID()))
    func freshAccessToken() async throws -> String { "test-token" }
}

@MainActor struct FitFightAPI {
    static var requests: [CheckedContinuation<FeedActivityList, Error>] = []
    func feedActivity(cursor: String?, accessToken: String) async throws -> FeedActivityList {
        try await withCheckedThrowingContinuation { Self.requests.append($0) }
    }
}

@MainActor final class AppModel {
    enum Tab { case fights, feed }
    var tab = Tab.fights
    var openPost: FeedPostLink?
    var openFightID: String?
    var dailyRecapID: String?
    static let pendingFightRouteKey = "fitfight.tests.activity.route"
    static let pendingDailyStatusKey = "fitfight.tests.activity.daily"
    func openFight(id: String) { openFightID = id; tab = .fights }
    func presentDailyStatusRecap(for id: String) async { dailyRecapID = id }
}

@main @MainActor struct FeedActivityTests {
    static func main() async throws {
        let fight = UUID(), post = UUID(), comment = UUID()
        let model = AppModel()
        let legacy = LegacyNotificationRoutes()
        LegacyNotificationRoutes.storePendingFightRoute("/fights/\(fight)?post=\(post)&comment=\(comment)")
        legacy.consumeForTest()
        precondition(legacy.openFightID == fight.uuidString, "Released builds 201 and 202 must keep opening the Fight from enriched push routes")
        defer {
            UserDefaults.standard.removeObject(forKey: AppModel.pendingFightRouteKey)
            UserDefaults.standard.removeObject(forKey: AppModel.pendingDailyStatusKey)
        }
        AppModel.storePendingFightRoute("/fights/\(fight)?post=\(post)&comment=\(comment)")
        model.consumeForTest()
        precondition(model.tab == .feed && model.openPost == FeedPostLink(id: post, commentID: comment), "A persisted push must open its exact post and comment without a cached fight")
        precondition(UserDefaults.standard.string(forKey: AppModel.pendingFightRouteKey) == nil)
        model.openPost = nil
        model.consumeForTest()
        precondition(model.openPost == nil, "A notification must not reopen after it is consumed")
        AppModel.storePendingFightRoute("/fights/\(fight)")
        model.consumeForTest()
        precondition(model.tab == .fights && model.openFightID == fight.uuidString, "Older pushes retain Fight navigation")
        AppModel.storePendingFightRoute("/fights/\(fight)?daily_status=1")
        precondition(UserDefaults.standard.bool(forKey: AppModel.pendingDailyStatusKey))
        model.consumeForTest(daily: true)
        for _ in 0..<10 { await Task.yield() }
        precondition(model.dailyRecapID == fight.uuidString)
        model.openFightID = nil
        AppModel.storePendingFightRoute("/fights/not-a-uuid?post=\(post)")
        model.consumeForTest()
        precondition(model.openPost == nil && model.openFightID == nil)

        let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let decoded = try FitFightAPI.decodeActivityForTest(fixture)
        precondition(decoded.events.count == 2 && decoded.events[0].occurredAt != nil)
        precondition(decoded.events[1].occurredAt == nil && decoded.events[1].subject?.handle == "sam")

        let session = SessionStore()
        let store = FeedActivityStore()
        let person = FeedActivityItem.Person(userId: UUID(), handle: "rad")
        let event = FeedActivityItem(id: "one", kind: "post_comment", occurredAt: Date(), actor: person, subject: nil, fightId: fight, fightName: "Goodwin", postId: post, commentId: comment, body: "Hello")
        let oldLoad = Task { await store.load(session: session) }
        while FitFightAPI.requests.count < 1 { await Task.yield() }
        let newLoad = Task { await store.load(session: session) }
        while FitFightAPI.requests.count < 2 { await Task.yield() }
        FitFightAPI.requests.removeLast().resume(returning: FeedActivityList(events: [event], nextCursor: "next"))
        await newLoad.value
        FitFightAPI.requests.removeFirst().resume(returning: FeedActivityList(events: [], nextCursor: nil))
        await oldLoad.value
        precondition(store.events.map(\.id) == ["one"] && store.nextCursor == "next", "A superseded refresh must not erase activity")
        let more = Task { await store.load(session: session, more: true) }
        while FitFightAPI.requests.isEmpty { await Task.yield() }
        FitFightAPI.requests.removeFirst().resume(returning: FeedActivityList(events: [event], nextCursor: nil))
        await more.value
        precondition(store.events.count == 1 && store.nextCursor == nil, "Pages must deduplicate overlapping activity")
        let switched = Task { await store.load(session: session) }
        while FitFightAPI.requests.isEmpty { await Task.yield() }
        session.authSession = Session(user: User(id: UUID()))
        store.events = []
        FitFightAPI.requests.removeFirst().resume(returning: FeedActivityList(events: [event], nextCursor: nil))
        await switched.value
        precondition(store.events.isEmpty, "An old account's response must not repopulate the new account")
        print("PASS: exact post/comment routes, cold persistence, legacy routes, daily recap, invalid routes, refresh ordering, pagination, account switch")
    }
}

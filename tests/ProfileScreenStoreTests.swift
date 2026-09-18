import Foundation

struct TestUser { let id: UUID }
struct TestSession { let user: TestUser }
@MainActor final class SessionStore {
    var authSession: TestSession? = TestSession(user: TestUser(id: UUID()))
    func freshAccessToken() async throws -> String { "test-token" }
}
@MainActor struct FitFightAPI {
    static var profiles: [CheckedContinuation<SharedProfile, Error>] = []
    static var histories: [CheckedContinuation<ProfileHistoryPage, Error>] = []
    static var sharedHistoryRequests: [Bool] = []
    func sharedProfile(userID: UUID, preview: String?, accessToken: String) async throws -> SharedProfile {
        try await withCheckedThrowingContinuation { Self.profiles.append($0) }
    }
    func profileHistory(userID: UUID, shared: Bool, cursor: UUID? = nil, accessToken: String) async throws -> ProfileHistoryPage {
        Self.sharedHistoryRequests.append(shared)
        return try await withCheckedThrowingContinuation { Self.histories.append($0) }
    }
}

@main struct ProfileScreenStoreTests {
    @MainActor static func until(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for suspended request")
    }

    @MainActor static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let decoder = JSONDecoder()
        let shared = try decoder.decode(SharedProfile.self, from: Data(contentsOf: fixtures.appendingPathComponent("shared-profile.json")))
        let privateProfile = try decoder.decode(SharedProfile.self, from: Data(contentsOf: fixtures.appendingPathComponent("shared-profile-private.json")))
        let history = try decoder.decode(ProfileHistoryPage.self, from: Data(contentsOf: fixtures.appendingPathComponent("profile-history.json")))
        precondition(shared.record?.played == 10 && shared.record?.winRate == 0.3)
        precondition(privateProfile.record == nil && privateProfile.activity == nil)
        precondition(history.results[0].fightId == nil && history.results[0].name == nil)
        let session = SessionStore()
        let store = ProfileScreenStore()

        let first = Task { await store.load(userID: shared.identity.userId, session: session, preview: "friend") }
        await until { FitFightAPI.profiles.count == 1 }
        let second = Task { await store.load(userID: privateProfile.identity.userId, session: session, preview: "stranger") }
        await until { FitFightAPI.profiles.count == 2 }
        FitFightAPI.profiles.removeLast().resume(returning: privateProfile)
        await second.value
        FitFightAPI.profiles.removeFirst().resume(returning: shared)
        await first.value
        precondition(store.profile == privateProfile, "Late private data cannot replace a newer response")

        let load = Task { await store.load(userID: shared.identity.userId, session: session) }
        await until { FitFightAPI.profiles.count == 1 }
        precondition(store.profile == nil && store.history.isEmpty)
        FitFightAPI.profiles.removeFirst().resume(returning: shared)
        await until { FitFightAPI.histories.count == 1 }
        precondition(FitFightAPI.sharedHistoryRequests.last == true, "Another person's Profile shows Fights together even when their full record is public")
        FitFightAPI.histories.removeFirst().resume(returning: history)
        await load.value
        precondition(store.history.count == 1 && store.nextCursor != nil)
        let more = Task { await store.loadMore(userID: shared.identity.userId, session: session) }
        await until { FitFightAPI.histories.count == 1 }
        precondition(FitFightAPI.sharedHistoryRequests.last == true, "Pagination keeps the shared Fight filter")
        FitFightAPI.histories.removeFirst().resume(throwing: URLError(.userAuthenticationRequired))
        await more.value
        precondition(store.profile == nil && store.history.isEmpty && store.error != nil)

        let own = Task { await store.load(userID: session.authSession!.user.id, session: session) }
        await until { FitFightAPI.profiles.count == 1 }
        FitFightAPI.profiles.removeFirst().resume(returning: shared)
        await until { FitFightAPI.histories.count == 1 }
        precondition(FitFightAPI.sharedHistoryRequests.last == false, "Your own Profile keeps your full result history")
        FitFightAPI.histories.removeFirst().resume(returning: history)
        await own.value

        let accountSwitch = Task { await store.load(userID: shared.identity.userId, session: session, preview: "friend") }
        await until { FitFightAPI.profiles.count == 1 }
        session.authSession = TestSession(user: TestUser(id: UUID()))
        store.clear()
        FitFightAPI.profiles.removeFirst().resume(returning: shared)
        await accountSwitch.value
        precondition(store.profile == nil && !store.loading)
        print("Profile state: DTOs, redaction, reversed responses, revocation, account switch passed")
    }
}

import Foundation

enum TestFailure: Error { case offline }
enum FitFightAPIError: Error { case http(status: Int, code: String?, message: String?) }
@MainActor final class SessionStore {
    var profile: FitFightProfile?
    init(profile: FitFightProfile) { self.profile = profile }
    func freshAccessToken() async throws -> String { "fixture-token" }
}

@MainActor struct FitFightAPI {
    static var fixtures = URL(fileURLWithPath: "/tmp")
    static var keys: [UUID] = []
    static var failure: Error?
    static var held = false
    static var continuation: CheckedContinuation<FitFightAIRequest, Error>?

    func aiLibrary(accessToken: String) async throws -> [FitFightAILibraryEntry] { [] }
    func aiAllowance(accessToken: String) async throws -> FitFightAIAllowance {
        try JSONDecoder().decode(FitFightAIAllowance.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("ai-allowance.json")))
    }
    func startAvatarGeneration(description: String, idempotencyKey: UUID, accessToken: String) async throws -> FitFightAIRequest {
        try await start(idempotencyKey)
    }
    func startFitnessGeneration(avatarRequestID: UUID, identityDetails: String, idempotencyKey: UUID, accessToken: String) async throws -> FitFightAIRequest {
        try await start(idempotencyKey)
    }
    func startGroupPhotoGeneration(characters: [FitFightAICharacter], scene: String, idempotencyKey: UUID, accessToken: String) async throws -> FitFightAIRequest {
        try await start(idempotencyKey)
    }
    private func start(_ key: UUID) async throws -> FitFightAIRequest {
        Self.keys.append(key)
        if Self.held { return try await withCheckedThrowingContinuation { Self.continuation = $0 } }
        return try await aiRequest(requestID: UUID(), accessToken: "fixture-token")
    }
    func aiRequest(requestID: UUID, accessToken: String) async throws -> FitFightAIRequest {
        if let failure = Self.failure { throw failure }
        return try JSONDecoder().decode(FitFightAIRequest.self, from: Data(contentsOf: Self.fixtures.appendingPathComponent("ai-run-completed.json")))
    }

}

@main struct AICompanionStateTests {
    @MainActor static func main() async throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        FitFightAPI.fixtures = fixtures
        let decoder = JSONDecoder()
        let profile = try decoder.decode(FitFightProfile.self, from: Data(contentsOf: fixtures.appendingPathComponent("profile.json")))
        let session = SessionStore(profile: profile)
        let storageKey = AICompanionStore.pendingPrefix + profile.userId.uuidString
        UserDefaults.standard.removeObject(forKey: storageKey)
        defer { UserDefaults.standard.removeObject(forKey: storageKey) }

        // A lost start response must survive a fresh screen instance with the exact paid key.
        let first = AICompanionStore()
        await first.open(session: session)
        FitFightAPI.failure = TestFailure.offline
        await first.begin(workflow: .avatar, description: "Fox", characters: [], session: session)
        let original = try decoder.decode(AICompanionAction.self, from: UserDefaults.standard.data(forKey: storageKey)!)
        precondition(original.key == FitFightAPI.keys[0] && original.requestID == nil)
        let reopened = AICompanionStore()
        await reopened.open(session: session)
        let uncertain = try decoder.decode(FitFightAIError.self, from: Data(contentsOf: fixtures.appendingPathComponent("ai-run-unconfirmed.json")))
        FitFightAPI.failure = uncertain
        await reopened.resume(session: session)
        precondition(FitFightAPI.keys == [original.key, original.key])
        precondition(reopened.action?.requestID == uncertain.requestID)
        FitFightAPI.failure = FitFightAIError(code: "ai_unavailable", message: nil, requestID: uncertain.requestID, retryAfterSeconds: nil)
        await reopened.resume(session: session)
        precondition(reopened.action?.key == original.key, "Disabled starts must not discard an admitted action")

        // Completing a recovered run only refreshes the library; it never starts another generation.
        FitFightAPI.failure = nil
        await reopened.resume(session: session)
        precondition(reopened.action == nil && UserDefaults.standard.data(forKey: storageKey) == nil)
        precondition(FitFightAPI.keys.count == 2)
        let saved = reopened

        // A definite admission rejection can be edited; a corrupt draft cannot risk another charge.
        FitFightAPI.failure = FitFightAIError(code: "ai_insufficient_credits", message: nil, requestID: nil, retryAfterSeconds: nil)
        await saved.begin(workflow: .avatar, description: "Fox", characters: [], session: session)
        precondition(saved.action == nil)
        UserDefaults.standard.set(Data("invalid".utf8), forKey: storageKey)
        let corrupt = AICompanionStore()
        await corrupt.open(session: session)
        await corrupt.open(session: session)
        let countBefore = FitFightAPI.keys.count
        await corrupt.begin(workflow: .avatar, description: "Fox", characters: [], session: session)
        precondition(corrupt.recoveryBlocked && FitFightAPI.keys.count == countBefore)
        UserDefaults.standard.removeObject(forKey: storageKey)

        // Signing out clears visible data; delayed starts cannot recreate deleted local data.
        let switched = AICompanionStore()
        await switched.open(session: session)
        FitFightAPI.failure = nil
        FitFightAPI.held = true
        let task = Task { await switched.begin(workflow: .avatar, description: "Fox", characters: [], session: session) }
        while FitFightAPI.continuation == nil { await Task.yield() }
        session.profile = nil
        await switched.open(session: session)
        UserDefaults.standard.removeObject(forKey: storageKey)
        let completed = try decoder.decode(FitFightAIRequest.self, from: Data(contentsOf: fixtures.appendingPathComponent("ai-run-completed.json")))
        FitFightAPI.continuation?.resume(returning: completed)
        await task.value
        precondition(switched.library.isEmpty)
        precondition(switched.action == nil && UserDefaults.standard.data(forKey: storageKey) == nil)

        session.profile = profile
        FitFightAPI.continuation = nil
        let cancelled = AICompanionStore()
        await cancelled.open(session: session)
        let cancelledTask = Task { await cancelled.begin(workflow: .avatar, description: "Fox", characters: [], session: session) }
        while FitFightAPI.continuation == nil { await Task.yield() }
        let persistedKey = cancelled.action?.key
        cancelledTask.cancel()
        FitFightAPI.continuation?.resume(returning: completed)
        await cancelledTask.value
        let afterCancellation = try decoder.decode(AICompanionAction.self, from: UserDefaults.standard.data(forKey: storageKey)!)
        precondition(afterCancellation.key == persistedKey && afterCancellation.requestID == nil)
        print("AI companion recovery and account isolation passed")
    }
}

import Foundation

private struct User { let id: UUID }
private struct AuthSession { let user: User }
private enum FitFightAPIError: Error { var errorDescription: String? { nil } }
private enum Failure: Error { case offline }

@MainActor private final class SessionStore {
    var authSession: AuthSession? = AuthSession(user: User(id: UUID()))
    func freshAccessToken() async throws -> String { "test-token" }
}

@MainActor private final class FitFightAPI {
    let isConfigured = true
    var requests = 0
    var pending: [(suggested: Bool, continuation: CheckedContinuation<[FitFightJoinableFight], Error>)] = []

    func listJoinableFights(accessToken: String) async throws -> [FitFightJoinableFight] {
        requests += 1
        return try await withCheckedThrowingContinuation { pending.append((false, $0)) }
    }

    func listSuggestedFights(accessToken: String) async throws -> [FitFightJoinableFight] {
        requests += 1
        return try await withCheckedThrowingContinuation { pending.append((true, $0)) }
    }
}

@MainActor private final class AppModel {
    var session: SessionStore?
    let api = FitFightAPI()
    var joinableFights: [FitFightJoinableFight] = []
    var suggestedFights: [FitFightJoinableFight] = []
    var isLoadingDiscovery = false
    var discoveryError: String?
    var discoveryUserID: UUID?
    var discoveryLoadedAt: Date?
    var discoveryTask: Task<Void, Never>?
    var discoveryGeneration = 0

    func invalidateForTest() { invalidateFightDiscovery() }

    // DISCOVERY_METHOD
}

@main private struct FightDiscoveryTests {
    @MainActor static func main() async {
        let model = AppModel()
        let session = SessionStore()
        let first = FitFightJoinableFight(
            fightId: UUID(), seriesId: UUID(), name: "First fight", joinCode: "K7M2",
            ownerHandle: "walker", startsAt: "2026-09-15T00:00:00Z",
            endsAt: "2026-09-22T00:00:00Z", memberCount: 2,
            recurring: false, alreadyMember: false
        )
        let task = Task { await model.loadFightDiscovery(session: session) }
        while model.api.pending.count < 2 { await Task.yield() }
        let overlapping = Task { await model.loadFightDiscovery(session: session) }
        try? await Task.sleep(for: .milliseconds(20))
        precondition(model.api.requests == 2, "Launch and tab loads must share two parallel requests")
        model.api.pending.removeFirst().continuation.resume(returning: [first])
        model.api.pending.removeFirst().continuation.resume(returning: [first])
        await task.value
        await overlapping.value
        precondition(model.joinableFights == [first] && model.suggestedFights == [first])
        await model.loadFightDiscovery(session: session)
        precondition(model.api.requests == 2, "A warm tab must reuse the cached lists")

        let failedRefresh = Task { await model.loadFightDiscovery(session: session, force: true) }
        while model.api.pending.count < 2 { await Task.yield() }
        precondition(model.joinableFights == [first], "Background refresh must keep cached rows visible")
        model.api.pending.removeFirst().continuation.resume(throwing: Failure.offline)
        model.api.pending.removeFirst().continuation.resume(returning: [first])
        await failedRefresh.value
        precondition(model.discoveryError != nil && model.joinableFights == [first], "Offline refresh must retain data and expose the error")
        precondition(model.discoveryLoadedAt == nil, "A partial failure must allow the next caller to retry immediately")

        let previousAccount = Task { await model.loadFightDiscovery(session: session, force: true) }
        while model.api.pending.count < 2 { await Task.yield() }
        session.authSession = AuthSession(user: User(id: UUID()))
        let nextAccount = Task { await model.loadFightDiscovery(session: session) }
        while model.api.pending.count < 4 { await Task.yield() }
        precondition(model.joinableFights.isEmpty && model.suggestedFights.isEmpty, "Account change must clear the prior account's cache")
        model.api.pending.removeFirst().continuation.resume(returning: [first])
        model.api.pending.removeFirst().continuation.resume(returning: [first])
        await previousAccount.value
        precondition(model.joinableFights.isEmpty && model.isLoadingDiscovery, "Old response must not publish or end the new account's load")
        model.api.pending.removeFirst().continuation.resume(returning: [])
        model.api.pending.removeFirst().continuation.resume(returning: [])
        await nextAccount.value
        precondition(model.discoveryError == nil && !model.isLoadingDiscovery)
        session.authSession = nil
        await model.loadFightDiscovery(session: session)
        precondition(model.discoveryLoadedAt == nil && model.discoveryUserID == nil)
        var partialFailures = 0
        let invalidated = AppModel()
        let invalidatedSession = SessionStore()
        let staleLoad = Task { await invalidated.loadFightDiscovery(session: invalidatedSession) }
        while invalidated.api.pending.count < 2 { await Task.yield() }
        invalidated.invalidateForTest()
        let reloaded = Task { await invalidated.loadFightDiscovery(session: invalidatedSession) }
        while invalidated.api.pending.count < 4 { await Task.yield() }
        invalidated.api.pending.removeFirst().continuation.resume(returning: [first])
        invalidated.api.pending.removeFirst().continuation.resume(returning: [first])
        await staleLoad.value
        let staleRejected = invalidated.discoveryLoadedAt == nil && invalidated.joinableFights.isEmpty
            && invalidated.suggestedFights.isEmpty && invalidated.isLoadingDiscovery
        print("\(staleRejected ? "PASS" : "FAIL"): a mutation during discovery prevents stale rows from becoming fresh")
        if !staleRejected { partialFailures += 1 }
        invalidated.api.pending.removeFirst().continuation.resume(returning: [])
        invalidated.api.pending.removeFirst().continuation.resume(returning: [])
        await reloaded.value
        precondition(invalidated.api.requests == 4 && invalidated.discoveryLoadedAt != nil && !invalidated.isLoadingDiscovery,
                     "The next caller must fetch fresh results without waiting for the invalidated request")
        for successfulSuggested in [false, true] {
            let cold = AppModel()
            let coldSession = SessionStore()
            let loading = Task { await cold.loadFightDiscovery(session: coldSession) }
            while cold.api.pending.count < 2 { await Task.yield() }
            let successIndex = cold.api.pending.firstIndex { $0.suggested == successfulSuggested }!
            cold.api.pending.remove(at: successIndex).continuation.resume(returning: [first])
            try? await Task.sleep(for: .milliseconds(20))
            let successfulRows = successfulSuggested ? cold.suggestedFights : cold.joinableFights
            let appearedBeforeOtherFinished = successfulRows == [first]
            cold.api.pending.removeFirst().continuation.resume(throwing: Failure.offline)
            await loading.value
            let retainedRows = successfulSuggested ? cold.suggestedFights : cold.joinableFights
            let passed = appearedBeforeOtherFinished && retainedRows == [first]
                && cold.discoveryLoadedAt == nil && cold.discoveryError != nil && !cold.isLoadingDiscovery
            print("\(passed ? "PASS" : "FAIL"): \(successfulSuggested ? "Suggested" : "Joinable") appears immediately and survives the other endpoint failing")
            if !passed { partialFailures += 1 }
        }
        if partialFailures != 0 { exit(1) }
        print("Fight discovery checks passed: parallel prefetch, shared requests, warm cache, offline retention, account isolation")
    }
}

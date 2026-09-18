import Foundation

struct TestUser { let id: UUID }
struct TestSession { let user: TestUser }
enum TestFailure: Error { case offline }
enum SyncTrigger { case manual }
enum FFTab { case fights, you }
enum FightStatus { case live, invited, pending, finished }
struct Fight {
    let id: String
    let seriesId: String?
    var status: FightStatus
    let windowStart: Date
    var score: Int
}

@MainActor final class SessionStore {
    var authSession: TestSession? = TestSession(user: TestUser(id: UUID()))
    func freshAccessToken() async throws -> String { "test-token" }
    func finishSuggestedOnboarding() {}
}

@MainActor final class HealthKitSyncTrace {
    init(trigger: SyncTrigger) {}
}

@MainActor final class HealthKitStepsStore {
    static let shared = HealthKitStepsStore()
    var pending: [CheckedContinuation<Void, Never>] = []
    var coalesced: [Bool] = []
    func syncToBackend(session: SessionStore, trigger: SyncTrigger, trace: HealthKitSyncTrace, coalesceInFlight: Bool) async {
        coalesced.append(coalesceInFlight)
        await withCheckedContinuation { pending.append($0) }
    }
    func completeAttempt(_ trace: HealthKitSyncTrace, session: SessionStore, userID: UUID?) {}
}

@MainActor struct FitFightAPI {
    static var joins: [CheckedContinuation<Void, Error>] = []
    static var offers: [FitFightJoinableFight] = []
    static var offerLoads = 0
    func joinFight(fightID: UUID, accessToken: String) async throws {
        try await withCheckedThrowingContinuation { Self.joins.append($0) }
    }
    func listSuggestedFights(accessToken: String) async throws -> [FitFightJoinableFight] {
        Self.offerLoads += 1
        return Self.offers
    }
}

@MainActor final class AppModel {
    var session: SessionStore?
    var fights: [Fight] = []
    var pendingJoinable: Fight?
    var snapshotLoads = 0
    var discoveryInvalidations = 0
    func refreshFromServer() async { snapshotLoads += 1 }
    func refreshFromServer(session: SessionStore) async { snapshotLoads += 1 }
    func invalidateFightDiscovery() { discoveryInvalidations += 1 }
    // TAB_STATE
    // APP_METHODS
}

@MainActor final class SuggestedOnboardingProbe {
    let session: SessionStore
    let model: AppModel
    var onFinished: (() -> Void)?
    var fights: [FitFightJoinableFight] = []
    var loading = false
    var joining: UUID?
    var error: String?
    init(session: SessionStore, model: AppModel) {
        self.session = session
        self.model = model
    }
    func joinForTest(_ fight: FitFightJoinableFight) async { await join(fight) }
    // ONBOARDING_METHODS
}

@MainActor final class ProfileNavigationProbe {
    let model: AppModel
    let initialFight: Fight
    init(model: AppModel, fight: Fight) {
        self.model = model
        self.initialFight = fight
    }
    func dismiss() {}
    func tapHistory(fightID: UUID) {
        // HISTORY_TAP
    }
    func destination(id: String) -> Fight? {
        // DESTINATION_LOOKUP
    }
    var displayed: Fight { fight }
    // DETAIL_FIGHT
}

@main struct ProfileInteractionTests {
    @MainActor static func until(_ condition: () -> Bool) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        preconditionFailure("Timed out waiting for an interaction boundary")
    }

    @MainActor static func main() async {
        var failures = 0
        func check(_ success: Bool, _ message: String) {
            print("\(success ? "PASS" : "FAIL"): \(message)")
            if !success { failures += 1 }
        }
        let session = SessionStore()
        let model = AppModel()
        model.session = session
        let view = SuggestedOnboardingProbe(session: session, model: model)
        let offer = FitFightJoinableFight(
            fightId: UUID(), seriesId: UUID(), name: "Suggested", joinCode: "K7M2", ownerHandle: "walker",
            startsAt: "2026-09-18T00:00:00Z", endsAt: "2026-09-25T00:00:00Z",
            memberCount: 2, recurring: true, alreadyMember: false
        )
        FitFightAPI.offers = [offer]
        let steps = HealthKitStepsStore.shared
        var completed = false
        let join = Task { await view.joinForTest(offer); completed = true }
        await until { FitFightAPI.joins.count == 1 }
        check(steps.pending.isEmpty, "Steps are not synced before membership is accepted")
        await view.joinForTest(offer)
        check(FitFightAPI.joins.count == 1, "Repeated Join taps do not submit another membership")
        FitFightAPI.joins.removeFirst().resume()
        await until { completed || !steps.pending.isEmpty }
        check(!completed && FitFightAPI.offerLoads == 0, "Onboarding waits for the new Fight's Steps before showing Joined")
        check(steps.coalesced == [false], "The new Fight gets its own sync instead of reusing an earlier window set")
        if !steps.pending.isEmpty { steps.pending.removeFirst().resume() }
        await join.value
        check(model.snapshotLoads == 1 && model.discoveryInvalidations == 1 && FitFightAPI.offerLoads == 1,
              "A successful onboarding join syncs, refreshes standings, and reloads offers")
        check(view.joining == nil && view.error == nil, "Join settles after the refresh")

        let snapshotsBeforeFailure = model.snapshotLoads
        let failed = Task { await view.joinForTest(offer) }
        await until { FitFightAPI.joins.count == 1 }
        FitFightAPI.joins.removeFirst().resume(throwing: TestFailure.offline)
        await failed.value
        check(steps.pending.isEmpty && model.snapshotLoads == snapshotsBeforeFailure && view.error != nil, "A rejected join reports the error without syncing")

        let previousAccount = Task { await view.joinForTest(offer) }
        await until { FitFightAPI.joins.count == 1 }
        let loads = FitFightAPI.offerLoads
        session.authSession = TestSession(user: TestUser(id: UUID()))
        FitFightAPI.joins.removeFirst().resume()
        await previousAccount.value
        check(FitFightAPI.offerLoads == loads && steps.pending.isEmpty, "An old account's join response cannot start a new account's sync")

        let switchingDuringSync = Task { await view.joinForTest(offer) }
        await until { FitFightAPI.joins.count == 1 }
        FitFightAPI.joins.removeFirst().resume()
        await until { !steps.pending.isEmpty }
        session.authSession = TestSession(user: TestUser(id: UUID()))
        steps.pending.removeFirst().resume()
        await switchingDuringSync.value
        check(FitFightAPI.offerLoads == loads, "An account change during Steps sync cannot reload the previous onboarding screen")

        let series = UUID().uuidString
        let pastID = UUID()
        let previous = Fight(id: pastID.uuidString, seriesId: series, status: .finished, windowStart: .distantPast, score: 51000)
        let current = Fight(id: UUID().uuidString, seriesId: series, status: .live, windowStart: Date(), score: 1000)
        for status in [FightStatus.finished, .pending] {
            var selected = previous
            selected.status = status
            model.fights = [selected, current]
            model.tab = .you
            model.openFightID = nil
            let profile = ProfileNavigationProbe(model: model, fight: selected)
            profile.tapHistory(fightID: pastID)
            await until { model.openFightID != nil }
            let destination = profile.destination(id: model.openFightID!)!
            let detail = ProfileNavigationProbe(model: model, fight: destination)
            check(model.tab == .fights && detail.displayed.id == selected.id && detail.displayed.score == selected.score,
                  "A Profile history tap opens the selected \(status) round and its own score")
            if status == .pending {
                model.fights[0].score = 52000
                model.fights[0].status = .finished
                check(detail.displayed.id == selected.id && detail.displayed.score == 52000 && detail.displayed.status == .finished,
                      "Final sync updates the selected pending round without switching to the current round")
            } else {
                model.fights[1].score = 2000
                check(detail.displayed.id == selected.id && detail.displayed.score == selected.score,
                      "Live updates leave the selected finished round's result unchanged")
            }
            model.openFightID = nil
            model.openFight(id: selected.id)
            await until { model.openFightID != nil }
            check(model.openFightID == current.id, "Feed links still resolve to the current round")
        }
        if failures > 0 { exit(1) }
        print("Profile interactions: onboarding sync, duplicate taps, failure, account switch, and exact round navigation passed")
    }
}

import Foundation

struct TestUser { let id: UUID }
struct TestSession { let user: TestUser }
struct TestAuth { var currentUser: TestUser? = nil }
struct TestClient { var auth = TestAuth() }
struct TestAvatar { let url: URL }
struct TestProfile { let userId: UUID; var avatar: TestAvatar? = nil }
struct Person: Codable { var photoURL: URL? = nil }
struct Standing: Codable { var person = Person() }
struct Fight: Codable { let score: Int; var standings: [Standing] = []; var days: [Int] = [] }
struct FightRow { let id = UUID(); let score: Int; var seriesId: UUID? = nil }
struct MemberRow { let fightId: UUID; let userId: UUID }
struct SeriesRow { let id: UUID }
struct TestSnapshot {
    let fights: [FightRow]
    var profiles: [TestProfile] = []
    var members: [MemberRow] = []
    var series: [SeriesRow] = []
    var stepDays: [Int] = []
}
enum Failure: Error { case offline }
enum CompanionPreview { static let isEnabled = false }
enum SyncTrigger { case foreground }
enum Stage { case session }

@MainActor final class HealthKitSyncTrace {
    var failed = false
    init(trigger: SyncTrigger) {}
    func measure<T>(_ stage: Stage, work: () async throws -> T) async rethrows -> T { try await work() }
    func fail(_ code: String) { failed = true }
}
@MainActor final class HealthKitStepsStore {
    static let shared = HealthKitStepsStore()
    var reports: [Bool] = []
    func completeAttempt(_ trace: HealthKitSyncTrace, session: SessionStore, userID: UUID) {
        reports.append(trace.failed)
    }
    static func errorCode(for error: Error) -> String { "test" }
}
@MainActor final class SessionStore {
    var authSession: TestSession? = TestSession(user: TestUser(id: UUID()))
    var client = TestClient()
    var profile: TestProfile? = nil
    func freshAccessToken() async throws -> String { "test-token" }
}
@MainActor final class FitFightAPI {
    var pending: [CheckedContinuation<TestSnapshot, Error>] = []
    var maintenance: [Bool] = []
    func fightsSnapshot(accessToken: String, trace: HealthKitSyncTrace, performMaintenance: Bool) async throws -> TestSnapshot {
        maintenance.append(performMaintenance)
        return try await withCheckedThrowingContinuation { pending.append($0) }
    }
}
@MainActor final class RemoteImageLoader {
    enum Kind { case avatar }
    static let shared = RemoteImageLoader()
    func prefetch(_ urls: [URL], kind: Kind) {}
}
@MainActor final class AppModel {
    var session: SessionStore?
    let api = FitFightAPI()
    var snapshotGeneration = 0
    var cachedUserID: UUID?
    var you = Person()
    var fights: [Fight] = []
    static let fightsCachePrefix = "fitfight.live-test."
    static func person(from profile: TestProfile, isYou: Bool) -> Person { Person() }
    static func mapFight(_ row: FightRow, members: [MemberRow], mine: MemberRow?, profiles: [UUID: TestProfile],
                         series: SeriesRow?, userId: UUID, formatScore: (Double) -> String) -> Fight? {
        Fight(score: row.score)
    }
    static func dayCards(from members: [MemberRow], standings: [Standing]) -> [Int] { [] }
    func formatScore(_ value: Double) -> String { String(value) }

    // PRODUCTION_METHODS
}

@main struct FightSnapshotStateTests {
    @MainActor static func main() async {
        let model = AppModel()
        let session = SessionStore()
        let user = session.authSession!
        defer { UserDefaults.standard.removeObject(forKey: AppModel.fightsCachePrefix + user.user.id.uuidString) }
        let slow = Task { await model.refreshFromServer(session: session) }
        while model.api.pending.count < 1 { await Task.yield() }
        let fresh = Task { await model.refreshFromServer(session: session, performMaintenance: false) }
        while model.api.pending.count < 2 { await Task.yield() }
        model.api.pending.removeLast().resume(returning: TestSnapshot(fights: [FightRow(score: 30000)]))
        await fresh.value
        model.api.pending.removeFirst().resume(returning: TestSnapshot(fights: [FightRow(score: 8000)]))
        await slow.value
        precondition(model.fights.first?.score == 30000, "An older response must never overwrite newer standings")
        precondition(model.api.maintenance == [true, false], "Live events must use the read-only API")
        precondition(HealthKitStepsStore.shared.reports == [false], "A superseded snapshot is not a failed HealthKit sync")

        let failed = Task { await model.refreshFromServer(session: session, performMaintenance: false) }
        while model.api.pending.isEmpty { await Task.yield() }
        model.api.pending.removeFirst().resume(throwing: Failure.offline)
        await failed.value
        precondition(model.fights.first?.score == 30000, "Offline must keep the last confirmed snapshot")
        precondition(HealthKitStepsStore.shared.reports == [false], "A peer refresh must not report a local HealthKit failure")

        let previousAccount = Task { await model.refreshFromServer(session: session) }
        while model.api.pending.isEmpty { await Task.yield() }
        session.authSession = TestSession(user: TestUser(id: UUID()))
        model.restoreCachedFights(session: session)
        model.api.pending.removeFirst().resume(returning: TestSnapshot(fights: [FightRow(score: 8000)]))
        await previousAccount.value
        precondition(model.fights.isEmpty, "A different account cannot receive an old account response")

        session.authSession = user
        model.restoreCachedFights(session: session)
        let beforeSignout = Task { await model.refreshFromServer(session: session) }
        while model.api.pending.isEmpty { await Task.yield() }
        session.authSession = nil
        model.restoreCachedFights(session: session)
        session.authSession = user
        model.restoreCachedFights(session: session)
        model.api.pending.removeFirst().resume(returning: TestSnapshot(fights: [FightRow(score: 1)]))
        await beforeSignout.value
        precondition(model.fights.first?.score == 30000, "Signing back into the same account cannot revive a stale request")
        print("Fight snapshots: response ordering, read-only routing, offline, account change, sign-out passed")
    }
}

import Foundation

// PRODUCTION_MODELS

struct TestUser { let id: UUID }
struct TestSession { let user: TestUser }
struct TestAuth { var currentUser: TestUser? = nil }
struct TestClient { var auth = TestAuth() }
enum Failure: Error { case offline }
enum CompanionPreview { static let isEnabled = false }
enum ScreenshotExport { static let isEnabled = false }
enum SyncTrigger { case foreground }
enum Stage { case session }

@MainActor final class HealthKitSyncTrace {
    init(trigger: SyncTrigger) {}
    func measure<T>(_ stage: Stage, work: () async throws -> T) async rethrows -> T { try await work() }
    func fail(_ code: String) {}
}

@MainActor final class HealthKitStepsStore {
    static let shared = HealthKitStepsStore()
    func completeAttempt(_ trace: HealthKitSyncTrace, session: SessionStore, userID: UUID) {}
    static func errorCode(for error: Error) -> String { "offline" }
}

@MainActor final class SessionStore {
    var authSession: TestSession? = TestSession(user: TestUser(id: UUID()))
    var client = TestClient()
    var profile: FitFightProfile? = nil
    func freshAccessToken() async throws -> String { "test-token" }
}

@MainActor final class FitFightAPI {
    var snapshot: FitFightSnapshot?
    var requests = 0

    func fightsSnapshot(accessToken: String, trace: HealthKitSyncTrace, performMaintenance: Bool) async throws -> FitFightSnapshot {
        requests += 1
        guard let snapshot else { throw Failure.offline }
        return snapshot
    }
}

@MainActor final class RemoteImageLoader {
    enum Kind { case avatar }
    static let shared = RemoteImageLoader()
    func prefetch(_ urls: [URL], kind: Kind) {}
}

@MainActor final class PushNotificationService {
    func registerIfAuthorized() async {}
}

@MainActor final class AppModel {
    var session: SessionStore?
    let api = FitFightAPI()
    var snapshotGeneration = 0
    var cachedUserID: UUID?
    var you = Person(id: "you", name: "@you", handle: "@you", initials: "Y", isYou: true)
    var fights: [Fight] = []
    var pendingJoinable: Fight?
    static var fightsCachePrefix: String { "fitfight.localization-test.\(AppLocalization.languageCode)." }

    // PRODUCTION_METHODS
}

@MainActor final class LanguageChangeHarness {
    let model = AppModel()
    let session = SessionStore()
    let push = PushNotificationService()
    var changeTask: Task<Void, Never>?

    func languageChanged() {
        // PRODUCTION_LANGUAGE_CHANGE
    }
}

@main struct FightLocalizationTests {
    @MainActor static func main() async throws {
        let harness = LanguageChangeHarness()
        let model = harness.model
        let session = harness.session
        let userID = session.authSession!.user.id
        let opponentID = UUID()
        defer {
            for language in ["en", "fr"] {
                UserDefaults.standard.removeObject(forKey: "fitfight.localization-test.\(language).\(userID.uuidString)")
            }
        }

        var rows: [[String: Any]] = []
        var members: [[String: Any]] = []
        for state in ["final", "awaiting_final_sync", "live", "invited"] {
            let id = UUID().uuidString
            rows.append([
                "id": id, "owner_id": opponentID.uuidString, "name": "Pending",
                "state": state == "invited" ? "live" : state,
                "starts_at": "2026-09-15T12:00:00Z",
                "ends_at": state == "live" || state == "invited" ? "2099-09-18T12:00:00Z" : "2026-09-16T12:00:00Z",
                "action_text": "The loser says Leading by, then Ended.",
            ])
            for (idValue, score, rank) in [(userID, 4000, 1), (opponentID, 3000, 2)] {
                members.append([
                    "fight_id": id, "user_id": idValue.uuidString,
                    "state": state == "invited" && idValue == userID ? "invited" : "accepted",
                    "current_value": score, "rank": rank, "final_steps_complete": false,
                ])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: [
            "fights": rows, "members": members, "series": [], "step_days": [],
            "profiles": [
                ["user_id": userID.uuidString, "handle": "you", "display_name": "You"],
                ["user_id": opponentID.uuidString, "handle": "leading_by", "display_name": "Leading by"],
            ],
        ])
        AppLocalization.apply(.en)
        model.api.snapshot = try JSONDecoder().decode(FitFightSnapshot.self, from: data)
        await model.refreshFromServer(session: session, performMaintenance: false)
        precondition(model.fights.count == 4)
        precondition(model.fights[0].endedLabel!.hasPrefix("Ended "))
        precondition(model.fights[1].listSubtitle.hasPrefix("Pending"))
        precondition(model.fights[2].kickerPrefix == "Leading by")
        let original = model.fights
        var joinPreview = model.fights[3]
        joinPreview.pendingJoin = true
        model.pendingJoinable = joinPreview

        model.api.snapshot = nil
        AppLocalization.apply(.fr)
        harness.languageChanged()
        await harness.changeTask?.value
        precondition(model.fights[0].endedLabel!.hasPrefix("Terminé le "),
                     "Ended must switch to French even when every Fight request fails")
        precondition(model.fights[1].listSubtitle.hasPrefix("En attente"),
                     "Pending must switch without a successful snapshot")
        precondition(model.fights[2].kickerPrefix == "En tête de")
        precondition(model.fights[2].kickerEmphasis.contains("pas"))
        precondition(model.fights[3].invitePitch == "@leading_by vous a défié")
        precondition(model.pendingJoinable?.invitePitch == "@leading_by vous a défié")
        precondition(model.pendingJoinable?.listSubtitle == "@leading_by · \(joinPreview.of)")
        for (before, after) in zip(original, model.fights) {
            precondition(after.name == before.name && after.listTitle == before.listTitle,
                         "French UI must not translate a Fight named Pending")
            precondition(after.actionText == before.actionText && after.standings == before.standings)
        }
        precondition(model.pendingJoinable?.name == joinPreview.name)
        precondition(model.pendingJoinable?.actionText == joinPreview.actionText)
        precondition(model.api.requests == 1, "A language change must not need a Fight request")

        await model.refreshFromServer(session: session, performMaintenance: false)
        precondition(model.fights[0].endedLabel!.hasPrefix("Terminé le "))
        let restored = AppModel()
        restored.restoreCachedFights(session: session)
        precondition(restored.fights == model.fights, "Offline relaunch must restore the relocalized Fight cache")

        AppLocalization.apply(.en)
        harness.languageChanged()
        await harness.changeTask?.value
        precondition(model.fights[0].endedLabel!.hasPrefix("Ended "))
        precondition(model.fights[1].listSubtitle.hasPrefix("Pending"))
        precondition(model.fights[2].kickerPrefix == "Leading by")
        for (before, after) in zip(original, model.fights) {
            precondition(after.name == before.name && after.listTitle == before.listTitle,
                         "Fight names that match translated UI words must remain exactly as entered")
            precondition(after.actionText == before.actionText, "Never translate user-written stakes")
            precondition(after.standings == before.standings && after.id == before.id)
            precondition(after.windowStart == before.windowStart && after.windowEnd == before.windowEnd)
        }
        print("Fight localization: offline language changes, user text, confirmed scores, and cached relaunch passed")
    }
}

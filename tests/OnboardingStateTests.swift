import Foundation

struct TestProfile {
    var userId: UUID
    var looksGenerated = false
    var handleSetAt: String?
    var companionId: String?
}
struct TestUser { let id: UUID }
struct TestSession { let user: TestUser }
struct TestPublisher { func send() {} }

@MainActor final class OnboardingSession {
    let defaults: UserDefaults
    var authSession: TestSession?
    var profile: TestProfile?
    var screenshotSignedIn = false
    var isSignedIn: Bool { authSession != nil }
    let objectWillChange = TestPublisher()
    init(defaults: UserDefaults) { self.defaults = defaults }
    // SESSION_KEYS
    // SESSION_METHODS
}

@main struct OnboardingStateTests {
    @MainActor static func main() throws {
        let suite = "fitfight-onboarding-tests-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = UUID()
        let second = UUID()
        let session = OnboardingSession(defaults: defaults)
        precondition(session.firstFightOnboarding == nil)
        session.authSession = TestSession(user: TestUser(id: first))
        session.profile = TestProfile(userId: first, looksGenerated: true)
        defaults.set(true, forKey: "ff.handle.chosen")
        precondition(session.needsOnboarding)
        precondition(session.firstFightOnboarding?.page == .username)
        print("PASS: new accounts choose a username even after another account used this phone")

        session.profile?.looksGenerated = false
        session.profile?.handleSetAt = "2026-09-23"
        precondition(session.firstFightOnboarding == nil)
        let progress = FirstFightOnboarding(page: .healthResult)
        session.saveFirstFightOnboarding(progress, userID: first)
        let restored = OnboardingSession(defaults: defaults)
        restored.authSession = session.authSession
        restored.profile = session.profile
        precondition(restored.firstFightOnboarding == progress)
        precondition(progress.page.step == 4 && FirstFightOnboarding.Page.health.step == 4)
        print("PASS: relaunch restores the same Health step for the same account")

        session.authSession = TestSession(user: TestUser(id: second))
        precondition(session.firstFightOnboarding == nil)
        session.profile = TestProfile(userId: second, handleSetAt: "2026-09-20")
        precondition(session.firstFightOnboarding == nil)
        session.saveFirstFightOnboarding(FirstFightOnboarding(page: .celebration), userID: first)
        precondition(restored.firstFightOnboarding == progress)
        precondition(session.firstFightOnboarding == nil)
        session.finishFirstFightOnboarding(userID: first)
        precondition(restored.firstFightOnboarding == progress)
        print("PASS: account switching isolates saved progress and rejects stale writes or completion")

        var joined = FirstFightOnboarding(page: .reminders)
        precondition(joined.pageAfterReminders == nil)
        joined.joinedFightID = UUID()
        joined.joinedFightName = "The long way home"
        precondition(joined.pageAfterReminders == .celebration)
        joined.page = .firstFight
        joined.page = .reminders
        precondition(joined.pageAfterReminders == .celebration)
        precondition(FirstFightOnboarding.Page.celebration.step == nil)
        precondition(FirstFightOnboarding.Page.reminders.step == 6)
        let encoded = try JSONEncoder().encode(joined)
        let decoded = try JSONDecoder().decode(FirstFightOnboarding.self, from: encoded)
        precondition(decoded == joined)
        print("PASS: Explore ends after reminders; confirmed membership survives Back and celebrates after reminders")

        session.saveFirstFightOnboarding(joined, userID: second)
        session.finishFirstFightOnboarding(userID: second)
        precondition(session.firstFightOnboarding == nil)
        precondition(restored.firstFightOnboarding == progress)
        session.authSession = nil
        precondition(session.firstFightOnboarding == nil)
        print("PASS: completing one account leaves another account's unfinished setup intact")

        session.authSession = TestSession(user: TestUser(id: second))
        defaults.set(true, forKey: "ff.onboarding.needsHealth")
        precondition(session.firstFightOnboarding?.page == .companion)
        session.profile?.companionId = "goat"
        precondition(session.firstFightOnboarding?.page == .health)
        defaults.removeObject(forKey: "ff.onboarding.needsHealth")
        defaults.set(true, forKey: "ff.onboarding.needsRequests")
        precondition(session.firstFightOnboarding?.page == .firstFight)
        session.finishFirstFightOnboarding(userID: second)
        precondition(session.firstFightOnboarding == nil)
        print("PASS: interrupted older onboarding migrates; completed accounts stay completed")
    }
}

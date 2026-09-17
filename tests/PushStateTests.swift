
import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
enum UNAuthorizationStatus { case authorized, notDetermined }
protocol UNUserNotificationCenterDelegate {}
struct UNNotificationPresentationOptions: OptionSet {
    let rawValue: Int
    static let banner = Self(rawValue: 1)
    static let sound = Self(rawValue: 2)
}
struct UNNotificationContent { var userInfo: [String: Any] = [:] }
struct UNNotificationRequest { var content = UNNotificationContent() }
struct UNNotification { var request = UNNotificationRequest() }
struct UNNotificationResponse { var notification = UNNotification() }
@MainActor enum AppModel {
    static var pendingRoute: String?
    static func storePendingFightRoute(_ route: String) { pendingRoute = route }
}
struct PermissionOptions: OptionSet { let rawValue: Int; static let alert = Self(rawValue: 1); static let sound = Self(rawValue: 2) }
@MainActor final class UNUserNotificationCenter {
    static let shared = UNUserNotificationCenter()
    static func current() -> UNUserNotificationCenter { shared }
    var cleared = 0
    struct Settings { let authorizationStatus = UNAuthorizationStatus.authorized }
    func notificationSettings() async -> Settings { Settings() }
    func requestAuthorization(options: PermissionOptions) async throws -> Bool { true }
    func removeAllDeliveredNotifications() { cleared += 1 }
}
@MainActor final class UIApplication {
    static let shared = UIApplication()
    var registers = 0
    var unregisters = 0
    func registerForRemoteNotifications() { registers += 1 }
    func unregisterForRemoteNotifications() { unregisters += 1 }
}
struct Fight { enum Status { case live }; var status: Status; var windowEnd: Date }
struct User { var id: UUID }
struct Session { var user: User; var accessToken: String }
@MainActor final class SessionStore {
    var authSession: Session?
    var isSignedIn: Bool { authSession != nil }
    func freshAccessToken() async throws -> String { authSession!.accessToken }
}
@MainActor final class APIRecorder {
    static let shared = APIRecorder()
    var events: [String] = []
    var hold = false
    var continuation: CheckedContinuation<Void, Never>?
    var failRevoke = false
}
@MainActor struct FitFightAPI {
    let isConfigured = true
    struct DeliveryStatus { let apnsConfigured = true }
    func notificationDeliveryStatus() async throws -> DeliveryStatus { DeliveryStatus() }
    func registerDeviceInstallation(token: String, apnsEnvironment: String, locale: String, permissionStatus: String, accessToken: String) async throws {
        let log = APIRecorder.shared
        log.events.append("register-start:\(accessToken)")
        if log.hold { await withCheckedContinuation { log.continuation = $0 } }
        log.events.append("register-end:\(accessToken)")
    }
    func revokeDeviceInstallation(token: String, accessToken: String) async throws {
        APIRecorder.shared.events.append("revoke:\(accessToken)")
        if APIRecorder.shared.failRevoke { throw URLError(.notConnectedToInternet) }
    }
}
import Foundation

// PUSH_SERVICE

@MainActor enum CompanionPreview { static let isEnabled = false }
@MainActor enum CrashReporting { static func reset() {} }
struct FitFightProfile: Codable { let userId: UUID }
enum AuthEvent { case initialSession, tokenRefreshed, signedOut }
@MainActor final class BootstrapAuth {
    let authStateChanges: AsyncStream<(AuthEvent, Session?)>
    let continuation: AsyncStream<(AuthEvent, Session?)>.Continuation
    init() {
        (authStateChanges, continuation) = AsyncStream.makeStream()
    }
}
@MainActor struct BootstrapClient { let auth = BootstrapAuth() }
@MainActor final class SessionBootstrap {
    // SESSION_RESTORE_PROPERTY
    var authSession: Session?
    var profile: FitFightProfile?
    var profileUnavailable = false
    var holdProfile = false
    var profileLoadCount = 0
    var profileContinuation: CheckedContinuation<Void, Never>?
    private static let profileCachePrefix = "fitfight.profile."
    let client = BootstrapClient()
    func loadProfile() async {
        profileLoadCount += 1
        if holdProfile {
            await withCheckedContinuation { profileContinuation = $0 }
        }
    }
    // SESSION_BOOTSTRAP_INITIALIZER
    // SESSION_LISTENER
}

@main @MainActor struct PushSignoutTests {
    static func main() async {
        let session = SessionStore()
        let userA = User(id: UUID()), userB = User(id: UUID())
        session.authSession = Session(user: userA, accessToken: "A")
        let push = PushNotificationService()
        var notifications = 0
        push.configure(session: session, onNotification: { notifications += 1 })
        await push.refreshServerStatus()
        await push.refreshAuthorizationStatus()
        await push.registerIfAuthorized()
        precondition(UIApplication.shared.registers == 1)
        await push.handleDeviceToken(Data([0xab]))

        let recorder = APIRecorder.shared
        recorder.hold = true
        let registration = Task { await push.handleDeviceToken(Data([0xab])) }
        while recorder.continuation == nil { await Task.yield() }
        await push.revokeLocalRegistration()
        precondition(UIApplication.shared.unregisters == 1, "Signout must stop APNs before waiting for the backend")
        precondition(UNUserNotificationCenter.shared.cleared == 1)
        let signedOutPresentation = await push.userNotificationCenter(.current(), willPresent: UNNotification())
        precondition(signedOutPresentation.isEmpty, "A late foreground notification must stay hidden during signout")
        precondition(notifications == 0, "Signed-out notifications must not refresh content")
        session.authSession = nil
        await push.registerIfAuthorized()
        precondition(UIApplication.shared.registers == 1, "Signed-out state must not register with APNs")

        session.authSession = Session(user: userB, accessToken: "B")
        let relogin = Task { await push.registerIfAuthorized() }
        await Task.yield()
        precondition(UIApplication.shared.registers == 1, "Do not resume APNs before the previous account is revoked")
        recorder.hold = false
        recorder.continuation!.resume()
        await registration.value
        await relogin.value
        await push.handleDeviceToken(Data([0xab]))
        precondition(recorder.events == ["register-start:A", "register-end:A", "register-start:A", "register-end:A", "revoke:A", "register-start:B", "register-end:B"], "Registration and revocation must remain in account order: \(recorder.events)")
        precondition(UIApplication.shared.registers == 2)
        let signedInPresentation = await push.userNotificationCenter(.current(), willPresent: UNNotification())
        precondition(signedInPresentation == [.banner, .sound])
        precondition(notifications == 1, "A foreground notification refreshes the visible feed")
        let route = "/fights/\(UUID())?post=\(UUID())"
        await push.userNotificationCenter(.current(), didReceive: UNNotificationResponse(
            notification: UNNotification(request: UNNotificationRequest(content: UNNotificationContent(userInfo: ["fitfight": ["route": route]])))
        ))
        precondition(AppModel.pendingRoute == route && notifications == 2, "A tap while already foregrounded must persist and consume its post route")

        recorder.failRevoke = true
        await push.revokeLocalRegistration()
        session.authSession = nil
        for _ in 0..<100 { await Task.yield() }
        precondition(UIApplication.shared.unregisters == 2)
        precondition(UNUserNotificationCenter.shared.cleared == 2)
        precondition(recorder.events.last == "revoke:B", "Offline signout must still attempt server revocation")
        let bootstrap = SessionBootstrap()
        precondition(bootstrap.isRestoringSession && bootstrap.authSession == nil)
        for _ in 0..<10 { await Task.yield() }
        precondition(bootstrap.isRestoringSession, "Do not show Welcome while Auth restoration is unresolved")
        bootstrap.client.auth.continuation.yield((.initialSession, Session(user: userA, accessToken: "A")))
        while bootstrap.isRestoringSession { await Task.yield() }
        precondition(bootstrap.authSession?.user.id == userA.id, "The restored user must be assigned before startup ends")
        let refreshed = SessionBootstrap()
        refreshed.holdProfile = true
        let cacheKey = "fitfight.profile.\(userA.id.uuidString)"
        UserDefaults.standard.set(try! JSONEncoder().encode(FitFightProfile(userId: userA.id)), forKey: cacheKey)
        defer { UserDefaults.standard.removeObject(forKey: cacheKey) }
        // An expired saved token produces a refresh event before the initial session.
        refreshed.client.auth.continuation.yield((.tokenRefreshed, Session(user: userA, accessToken: "refreshed")))
        refreshed.client.auth.continuation.yield((.initialSession, Session(user: userA, accessToken: "refreshed")))
        while refreshed.profileContinuation == nil { await Task.yield() }
        precondition(refreshed.authSession?.user.id == userA.id && refreshed.profile?.userId == userA.id,
                     "The saved session and cached profile must be restored before profile loading")
        precondition(!refreshed.isRestoringSession,
                     "A refreshed saved session must leave startup loading before the profile request finishes")
        refreshed.holdProfile = false
        refreshed.profileContinuation?.resume()
        while refreshed.profileLoadCount < 2 { await Task.yield() }
        precondition(!refreshed.isRestoringSession, "The buffered initial session must keep the restored app usable")
        let signedOut = SessionBootstrap()
        signedOut.client.auth.continuation.yield((.initialSession, nil))
        while signedOut.isRestoringSession { await Task.yield() }
        precondition(signedOut.authSession == nil, "A resolved empty session must allow Welcome")
        precondition(!SessionBootstrap(listenForSession: false).isRestoringSession, "Fixtures do not wait for Auth")
        print("PASS: auth restore, refreshed-token startup with suspended profile loading, signed-out startup, fixtures")
        print("PASS: immediate local unregistration, cleared notifications, serial in-flight revoke, account switch, offline signout")
    }
}

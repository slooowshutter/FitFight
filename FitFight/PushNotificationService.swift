import Foundation
import UserNotifications
import UIKit

@MainActor
final class PushNotificationService: NSObject, ObservableObject {
    static let shared = PushNotificationService()

    @Published private(set) var apnsConfigured = false
    @Published private(set) var permissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var showPrePrompt = false

    private let api = FitFightAPI()
    private var session: SessionStore?
    private var askedThisSession = false
    private var deviceToken: String?
    private var installationTask: Task<Void, Never>?
    private var isSignedOut = false
    private static let declinedPrePromptKey = "ff.push.declinedPrePrompt"

    func configure(session: SessionStore) {
        self.session = session
    }

    var canPromptForPermission: Bool {
        permissionStatus == .notDetermined && !askedThisSession
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        permissionStatus = settings.authorizationStatus
    }

    func refreshServerStatus() async {
        guard api.isConfigured else {
            apnsConfigured = false
            return
        }
        do {
            let status = try await api.notificationDeliveryStatus()
            apnsConfigured = status.apnsConfigured
        } catch {
            apnsConfigured = false
        }
    }

    func considerPromptIfNeeded(fights: [Fight]) async {
        await refreshAuthorizationStatus()
        guard canPromptForPermission, !hasHandledPrePrompt else {
            return
        }
        let now = Date()
        let hasUpcomingLiveFight = fights.contains { fight in
            guard fight.status == .live else { return false }
            return fight.windowEnd > now
        }
        guard hasUpcomingLiveFight else { return }
        showPrePrompt = true
        markPrePromptHandled()
    }

    func declinePrePrompt() {
        askedThisSession = true
        showPrePrompt = false
        markPrePromptHandled()
    }

    func markPromptHandledThisSession() {
        askedThisSession = true
        showPrePrompt = false
        markPrePromptHandled()
    }

    func requestSystemPermission() async {
        askedThisSession = true
        showPrePrompt = false
        markPrePromptHandled()
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
        await refreshAuthorizationStatus()
        if granted {
            await registerIfAuthorized()
        }
    }

    func registerIfAuthorized() async {
        guard permissionStatus == .authorized, let userID = session?.authSession?.user.id else { return }
        isSignedOut = false
        await installationTask?.value
        guard !isSignedOut, session?.authSession?.user.id == userID else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        self.deviceToken = token
        guard apnsConfigured, permissionStatus == .authorized, !isSignedOut,
              let session, let userID = session.authSession?.user.id else { return }
        let locale = Locale.current.language.languageCode?.identifier == "fr" ? "fr" : "en"
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let previous = installationTask
        let work = Task { @MainActor in
            await previous?.value
            guard !self.isSignedOut, session.authSession?.user.id == userID else { return }
            do {
                let access = try await session.freshAccessToken()
                guard !self.isSignedOut, session.authSession?.user.id == userID else { return }
                try await self.api.registerDeviceInstallation(
                    token: token,
                    apnsEnvironment: environment,
                    locale: locale,
                    permissionStatus: "authorized",
                    accessToken: access
                )
            } catch {
                // Push registration is best-effort; fights still work without it.
            }
        }
        installationTask = work
        await work.value
    }

    func handleRegistrationFailure() {
        // Missing push capability or simulator — no user-facing error.
    }

    private var hasHandledPrePrompt: Bool {
        UserDefaults.standard.bool(forKey: Self.declinedPrePromptKey)
    }

    private func markPrePromptHandled() {
        UserDefaults.standard.set(true, forKey: Self.declinedPrePromptKey)
    }

    func revokeLocalRegistration() async {
        isSignedOut = true
        UIApplication.shared.unregisterForRemoteNotifications()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        guard let deviceToken, let access = session?.authSession?.accessToken else { return }
        let previous = installationTask
        installationTask = Task { @MainActor in
            // A registration already sent to the server must finish before revocation.
            await previous?.value
            do {
                try await self.api.revokeDeviceInstallation(token: deviceToken, accessToken: access)
            } catch {
                // Local unregistration keeps signed-out devices quiet even while offline.
            }
        }
    }
}

extension PushNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run {
            self.session?.isSignedIn == true && !self.isSignedOut ? [.banner, .sound] : []
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = response.notification.request.content.userInfo["fitfight_route"] as? String
            ?? (response.notification.request.content.userInfo["fitfight"] as? [String: Any])?["route"] as? String
        guard let route else { return }
        await MainActor.run {
            AppModel.storePendingFightRoute(route)
        }
    }
}

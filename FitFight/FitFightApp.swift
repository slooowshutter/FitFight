import SwiftUI
import UIKit
import UserNotifications

extension AppUpdateChecker {
    static let shared = AppUpdateChecker(
        version: AppVersion.marketing,
        build: AppVersion.build,
        releaseURL: APIConfig.publicOrigin.appendingPathComponent("api/app-release")
    )
}

@MainActor
final class FitFightAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        CrashReporting.start()
        guard !CompanionPreview.isEnabled else { return true }
        HealthKitStepsStore.shared.installObserverAtLaunch()
        UNUserNotificationCenter.current().delegate = PushNotificationService.shared
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard !CompanionPreview.isEnabled else { return }
        Task { await PushNotificationService.shared.handleDeviceToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        guard !CompanionPreview.isEnabled else { return }
        PushNotificationService.shared.handleRegistrationFailure()
    }

    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        guard !CompanionPreview.isEnabled else { completionHandler(); return }
        HealthKitTUSUploader.registerBackgroundEvents(
            identifier: identifier,
            completion: completionHandler
        )
    }
}

@main
struct FitFightApp: App {
    @UIApplicationDelegateAdaptor(FitFightAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var themeStore: ThemeStore
    @StateObject private var model: AppModel
    @StateObject private var companions = CompanionStore()
    @StateObject private var appUpdate = AppUpdateChecker.shared
    @StateObject private var session: SessionStore
    @StateObject private var steps: HealthKitStepsStore
    @StateObject private var feed = FeedStore()
    @StateObject private var push = PushNotificationService.shared

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            let session = SessionStore(companionPreview: ())
            let steps = HealthKitStepsStore()
            steps.setCompanionPreviewStatus(.steps(count: 8_432))
            let state = CompanionPreview.DisplayState(rawValue: ProcessInfo.processInfo.environment["FF_COMPANION_STATE"] ?? "") ?? .populated
            let model = CompanionPreview.model(state: state)
            model.showCompanionPreviewState(state)
            let feed = FeedStore()
            feed.posts = CompanionPreview.posts()
            let mode: Mode = ProcessInfo.processInfo.environment["FF_COMPANION_THEME"] == "day" ? .day : .night
            _themeStore = StateObject(wrappedValue: ThemeStore(transient: mode))
            _model = StateObject(wrappedValue: model)
            _session = StateObject(wrappedValue: session)
            _steps = StateObject(wrappedValue: steps)
            _feed = StateObject(wrappedValue: feed)
            return
        }
        #endif
        _themeStore = StateObject(wrappedValue: ThemeStore())
        _model = StateObject(wrappedValue: AppModel())
        let session = SessionStore()
        let steps = HealthKitStepsStore.shared
        steps.configure(session: session)
        _session = StateObject(wrappedValue: session)
        _steps = StateObject(wrappedValue: steps)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .environmentObject(model)
                .environmentObject(companions)
                .environmentObject(session)
                .environmentObject(steps)
                .environmentObject(feed)
                .environmentObject(appUpdate)
                .environmentObject(push)
                .fitFightTheme(themeStore.theme)
                .task {
                    guard !CompanionPreview.isEnabled else {
                        #if DEBUG && targetEnvironment(simulator)
                        if ProcessInfo.processInfo.environment["FF_COMPANION_EXPORT"] == "1" {
                            ScreenshotExport.exportCompanion()
                        }
                        #endif
                        return
                    }
                    steps.onLocalAggregates = { sync in
                        model.applyLocalHealthKitScores(sync)
                    }
                    steps.onBackendSync = {
                        await model.refreshFromServer(session: session)
                    }
                    push.configure(session: session)
                    await push.refreshServerStatus()
                    await push.refreshAuthorizationStatus()
                    push.registerIfAuthorized()
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                    #if DEBUG
                    await session.devAdoptSessionIfNeeded()
                    #endif
                }
                .task(id: session.authSession?.user.id) {
                    guard !CompanionPreview.isEnabled else { return }
                    CrashReporting.identify(userId: session.authSession?.user.id)
                }
                .task(id: appUpdate.status == .current ? session.authSession?.user.id : nil) {
                    guard !CompanionPreview.isEnabled else { return }
                    model.pendingReferralError = nil
                    steps.activate(userId: appUpdate.status == .current ? session.authSession?.user.id : nil)
                    guard appUpdate.status == .current else { return }
                    model.restoreCachedFights(session: session)
                    await model.refreshFights(session: session, steps: steps)
                    if !session.needsOnboarding,
                       !session.needsHealthOnboarding,
                       !session.needsNotificationOnboarding,
                       !session.needsRequestsOnboarding {
                        await push.considerPromptIfNeeded(fights: model.fights)
                    }
                }
                .task(id: appUpdate.status == .current ? session.profile?.userId : nil) {
                    guard !CompanionPreview.isEnabled else { return }
                    guard appUpdate.status == .current else { return }
                    await model.consumePendingLinks(session: session)
                }
                .onOpenURL { url in
                    guard !CompanionPreview.isEnabled else { return }
                    Task { await model.handleOpenURL(url, session: session) }
                }
                .onChange(of: session.needsOnboarding) { _, needsOnboarding in
                    guard !CompanionPreview.isEnabled else { return }
                    guard !needsOnboarding, session.profile != nil else { return }
                    Task { await model.consumePendingLinks(session: session) }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard !CompanionPreview.isEnabled else { return }
                    guard phase == .active, session.authSession != nil else { return }
                    Task {
                        guard await AppUpdateChecker.shared.permitsRequests() else { return }
                        await model.refreshFights(session: session, steps: steps)
                    }
                }
        }
    }
}

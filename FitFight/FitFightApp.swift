import GoogleSignIn
import SwiftUI
import UIKit
import UserNotifications

extension AppUpdateChecker {
    static let shared = AppUpdateChecker(
        version: AppVersion.marketing,
        build: AppVersion.build,
        releaseURL: APIConfig.publicOrigin.appendingPathComponent("api/app-release"),
        isTestFlight: AppVersion.backend == "staging"
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
    @StateObject private var specialPurchases = SpecialPurchases()
    @StateObject private var customCharacterPurchases = CustomCharacterPurchases()
    @StateObject private var preferences = AccountPreferencesStore()
    @StateObject private var appUpdate = AppUpdateChecker.shared
    @StateObject private var session: SessionStore
    @StateObject private var steps: HealthKitStepsStore
    @StateObject private var feed = FeedStore()
    @StateObject private var fightLiveUpdates = FightLiveUpdates()
    @StateObject private var push = PushNotificationService.shared
    /// Control Center, alerts, and permission sheets only make the app inactive; the
    /// foreground refresh waits for a real return from the background.
    @State private var returnedFromBackground = false

    init() {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            let session = SessionStore(companionPreview: ())
            let steps = HealthKitStepsStore()
            steps.setCompanionPreviewStatus(.steps(count: 8_432))
            let state = CompanionPreview.DisplayState(rawValue: ProcessInfo.processInfo.environment["FF_COMPANION_STATE"] ?? "") ?? .populated
            let model = CompanionPreview.model(state: state)
            model.showCompanionPreviewState(state)
            let companions = CompanionStore()
            if ProcessInfo.processInfo.environment["FF_COMPANION_PICKER"] == "1" {
                model.tab = .you
                companions.selection = .limitedPangolin
                companions.showingPicker = true
            }
            if ScreenshotExport.isEnabled {
                switch ProcessInfo.processInfo.environment["FF_SHOT"] {
                case "fight": model.openFightID = CompanionPreview.duelID
                case "invitation": model.openFightID = CompanionPreview.invitationID
                case "new": model.tab = .newFight
                case "feed": model.tab = .feed
                case "you": model.tab = .you
                default: break
                }
            }
            let feed = FeedStore()
            feed.posts = CompanionPreview.posts()
            let mode: Mode = ProcessInfo.processInfo.environment["FF_COMPANION_THEME"] == "day" ? .day : .night
            _themeStore = StateObject(wrappedValue: ThemeStore(transient: mode))
            _model = StateObject(wrappedValue: model)
            _session = StateObject(wrappedValue: session)
            _steps = StateObject(wrappedValue: steps)
            _feed = StateObject(wrappedValue: feed)
            _companions = StateObject(wrappedValue: companions)
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
                .environmentObject(specialPurchases)
                .environmentObject(customCharacterPurchases)
                .environmentObject(preferences)
                .environment(\.locale, AppLocalization.locale)
                .environmentObject(session)
                .environmentObject(steps)
                .environmentObject(feed)
                .environmentObject(appUpdate)
                .environmentObject(push)
                .fitFightTheme(themeStore.theme)
                .task(id: session.profile?.userId) {
                    guard !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
                    await specialPurchases.observe(session: session)
                }
                .task(id: session.profile?.userId) {
                    guard !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
                    await customCharacterPurchases.observe(session: session)
                }
                .onChange(of: session.authSession?.user.id, initial: true) { _, userID in
                    guard !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
                    preferences.activate(userID: userID)
                }
                .onChange(of: preferences.value.appearance, initial: true) { _, appearance in
                    guard !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
                    themeStore.apply(appearance)
                }
                .onChange(of: preferences.value.language) { _, _ in
                    guard !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
                    model.relocalizeFights()
                    Task {
                        await push.registerIfAuthorized()
                    }
                }
                .task(id: scenePhase != .background ? session.authSession?.user.id : nil) {
                    guard scenePhase != .background, !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
                    await preferences.refresh(session: session)
                }
                .task {
                    guard !CompanionPreview.isEnabled else {
                        #if DEBUG && targetEnvironment(simulator)
                        if ProcessInfo.processInfo.environment["FF_COMPANION_EXPORT"] == "1" {
                            ScreenshotExport.exportCompanion()
                        }
                        #endif
                        return
                    }
                    steps.onBackendSync = {
                        await model.refreshFromServer(session: session)
                    }
                    push.configure(session: session) {
                        model.feedRevision += 1
                        Task { await model.consumePendingLinks(session: session) }
                    }
                    await push.refreshServerStatus()
                    await push.refreshAuthorizationStatus()
                    await push.registerIfAuthorized()
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                    #if DEBUG
                    await session.devAdoptSessionIfNeeded()
                    #endif
                }
                .task(id: scenePhase != .background && appUpdate.allowsUse ? session.authSession?.user.id : nil) {
                    guard !CompanionPreview.isEnabled, !ScreenshotExport.isEnabled else { return }
                    let userID = scenePhase != .background && appUpdate.allowsUse ? session.authSession?.user.id : nil
                    await fightLiveUpdates.activate(client: session.client, userID: userID) {
                        guard session.authSession?.user.id == userID, appUpdate.allowsUse else { return }
                        await model.refreshFromServer(session: session, performMaintenance: false)
                    } refreshFeed: {
                        guard session.authSession?.user.id == userID, appUpdate.allowsUse else { return }
                        model.feedRevision += 1
                    }
                }
                .task(id: session.authSession?.user.id) {
                    guard !CompanionPreview.isEnabled else { return }
                    feed.activate(userID: session.authSession?.user.id)
                    guard let userId = session.authSession?.user.id else {
                        model.openPost = nil
                        model.showingActivity = false
                        model.showingPreferences = false
                        return
                    }
                    CrashReporting.identify(userId: userId)
                    await push.refreshAuthorizationStatus()
                    await push.registerIfAuthorized()
                }
                .task(id: appUpdate.allowsUse ? session.authSession?.user.id : nil) {
                    guard !CompanionPreview.isEnabled else { return }
                    model.pendingReferralError = nil
                    steps.activate(userId: appUpdate.allowsUse ? session.authSession?.user.id : nil)
                    guard appUpdate.allowsUse else { return }
                    model.restoreCachedFights(session: session)
                    await model.refreshFights(session: session, steps: steps)
                    if session.firstFightOnboarding == nil,
                       !session.needsOnboarding,
                       !session.needsHealthOnboarding,
                       !session.needsNotificationOnboarding,
                       !session.needsRequestsOnboarding {
                        await push.considerPromptIfNeeded(fights: model.fights)
                    }
                }
                .task(id: appUpdate.allowsUse ? session.profile?.userId : nil) {
                    guard !CompanionPreview.isEnabled else { return }
                    guard appUpdate.allowsUse else { return }
                    await model.consumePendingLinks(session: session)
                }
                .task(id: appUpdate.allowsUse ? session.authSession?.user.id : nil) {
                    guard !CompanionPreview.isEnabled, appUpdate.allowsUse else { return }
                    await model.loadFightDiscovery(session: session, force: true)
                }
                .onOpenURL { url in
                    guard !CompanionPreview.isEnabled else { return }
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    Task { await model.handleOpenURL(url, session: session) }
                }
                .onChange(of: session.needsOnboarding) { _, needsOnboarding in
                    guard !CompanionPreview.isEnabled else { return }
                    guard !needsOnboarding, session.profile != nil else { return }
                    Task { await model.consumePendingLinks(session: session) }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard !CompanionPreview.isEnabled else { return }
                    if phase == .background { returnedFromBackground = true }
                    guard phase == .active, returnedFromBackground, session.authSession != nil else { return }
                    returnedFromBackground = false
                    model.feedRevision += 1
                    Task {
                        guard await AppUpdateChecker.shared.permitsRequests() else { return }
                        async let discovery: Void = model.loadFightDiscovery(session: session, force: true)
                        await model.refreshFights(session: session, steps: steps)
                        await model.consumePendingLinks(session: session)
                        await discovery
                    }
                }
        }
    }
}

import SwiftUI
import UIKit

final class FitFightAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
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
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var model = AppModel()
    @StateObject private var newFightLayouts = NewFightLayoutStore()
    @StateObject private var newFightDraft = NewFightDraft()
    @StateObject private var session: SessionStore
    @StateObject private var steps: HealthKitStepsStore

    init() {
        let session = SessionStore()
        let steps = HealthKitStepsStore()
        steps.configure(session: session)
        _session = StateObject(wrappedValue: session)
        _steps = StateObject(wrappedValue: steps)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .environmentObject(model)
                .environmentObject(newFightLayouts)
                .environmentObject(newFightDraft)
                .environmentObject(session)
                .environmentObject(steps)
                .fitFightTheme(themeStore.theme)
                .task {
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                    #if DEBUG
                    await session.devAdoptSessionIfNeeded()
                    #endif
                }
                .task(id: session.authSession?.user.id) {
                    steps.activate(userId: session.authSession?.user.id)
                    model.restoreCachedFights(session: session)
                    await model.refreshFights(session: session, steps: steps)
                }
                .onChange(of: session.authSession?.user.id) { _, _ in
                    newFightDraft.resetAfterStart()
                }
                .onChange(of: steps.status) { _, status in
                    guard case .steps = status else { return }
                    guard session.authSession != nil else { return }
                    guard !model.isRefreshingFights else { return }
                    Task {
                        await steps.syncToBackend(session: session)
                        await model.refreshFromServer(session: session)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active, session.authSession != nil else { return }
                    Task {
                        await model.refreshFights(session: session, steps: steps)
                    }
                }
        }
    }
}

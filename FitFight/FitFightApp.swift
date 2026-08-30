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
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var model = AppModel()
    @StateObject private var session: SessionStore
    @StateObject private var friends: FriendshipStore
    @StateObject private var steps: HealthKitStepsStore

    init() {
        let session = SessionStore()
        let steps = HealthKitStepsStore()
        steps.configure(session: session)
        _session = StateObject(wrappedValue: session)
        _friends = StateObject(wrappedValue: FriendshipStore(client: session.client))
        _steps = StateObject(wrappedValue: steps)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(friends)
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
                    await steps.refresh(requestAccess: false)
                    if session.authSession != nil {
                        await steps.syncToBackend(session: session)
                    }
                    await model.refreshFromServer(session: session)
                }
                .onChange(of: steps.status) { _, status in
                    guard case .steps = status else { return }
                    guard session.authSession != nil else { return }
                    Task {
                        await steps.syncToBackend(session: session)
                        await model.refreshFromServer(session: session)
                    }
                }
        }
    }
}

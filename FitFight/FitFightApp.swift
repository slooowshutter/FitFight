import SwiftUI

@main
struct FitFightApp: App {
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var designStore = DesignStore()
    @StateObject private var model = AppModel()
    @StateObject private var session: SessionStore
    @StateObject private var friends: FriendshipStore
    @StateObject private var steps = HealthKitStepsStore()

    init() {
        let session = SessionStore()
        _session = StateObject(wrappedValue: session)
        _friends = StateObject(wrappedValue: FriendshipStore(client: session.client))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .environmentObject(designStore)
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(friends)
                .environmentObject(steps)
                .fitFightTheme(designStore.variant.theme(themeStore.theme))
                .task {
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                }
                .task(id: session.authSession?.user.id) {
                    await model.refreshFromServer(session: session)
                    await steps.refresh(requestAccess: false)
                    if let token = session.authSession?.accessToken {
                        await steps.syncToServer(api: FitFightAPI(), accessToken: token)
                    }
                }
                .onChange(of: steps.status) { _, status in
                    guard case .steps = status else { return }
                    guard let token = session.authSession?.accessToken else { return }
                    Task {
                        await steps.syncToServer(api: FitFightAPI(), accessToken: token)
                    }
                }
        }
    }
}

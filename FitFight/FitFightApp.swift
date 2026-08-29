import SwiftUI

@main
struct FitFightApp: App {
    @StateObject private var themeStore = ThemeStore()
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
                    if let userId = session.authSession?.user.id {
                        await steps.syncToSupabase(client: session.client, userId: userId)
                    }
                    await model.refreshFromServer(session: session)
                }
                .onChange(of: steps.status) { _, status in
                    guard case .steps = status else { return }
                    guard let userId = session.authSession?.user.id else { return }
                    Task {
                        await steps.syncToSupabase(client: session.client, userId: userId)
                        await model.refreshFromServer(session: session)
                    }
                }
        }
    }
}

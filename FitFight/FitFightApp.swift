import SwiftUI

@main
struct FitFightApp: App {
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var model = AppModel()
    @StateObject private var session: SessionStore
    @StateObject private var friends: FriendshipStore
    @StateObject private var steps = HealthKitStepsStore()
    @Environment(\.scenePhase) private var scenePhase

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
                }
                .task(id: session.authSession?.user.id) {
                    guard session.authSession?.user.id != nil else { return }
                    await syncHealthAndFights()
                }
                .onChange(of: session.authSession?.user.id) { old, new in
                    guard old != nil, old != new else { return }
                    steps.clearAccountCache()
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await syncHealthAndFights() }
                }
                .onChange(of: steps.status) { _, status in
                    guard status != .idle, status != .reading else { return }
                    guard let userId = session.authSession?.user.id else { return }
                    Task {
                        await steps.syncToSupabase(client: session.client, userId: userId)
                        await model.refreshFromServer(session: session)
                    }
                }
        }
    }

    private func syncHealthAndFights() async {
        await steps.refresh(requestAccess: false)
        if let userId = session.authSession?.user.id {
            await steps.syncToSupabase(client: session.client, userId: userId)
            if steps.history.isEmpty {
                await steps.loadServerHistory(client: session.client, userId: userId)
            }
        }
        await model.refreshFromServer(session: session)
    }
}

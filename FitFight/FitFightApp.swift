import SwiftUI

@main
struct FitFightApp: App {
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var designStore = DesignStore()
    @StateObject private var model = AppModel()
    @StateObject private var session = SessionStore()
    @StateObject private var steps = HealthKitStepsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .environmentObject(designStore)
                .environmentObject(model)
                .environmentObject(session)
                .environmentObject(steps)
                .fitFightTheme(designStore.variant.theme(themeStore.theme))
                .task {
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                }
        }
    }
}

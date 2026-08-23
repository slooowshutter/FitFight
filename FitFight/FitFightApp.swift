import SwiftUI

@main
struct FitFightApp: App {
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var designStore = DesignStore()
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .environmentObject(designStore)
                .environmentObject(model)
                .fitFightTheme(designStore.variant.theme(themeStore.theme))
                .task {
                    if ScreenshotExport.isEnabled {
                        ScreenshotExport.exportAll()
                    }
                }
        }
    }
}

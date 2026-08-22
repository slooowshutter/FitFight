import SwiftUI

@main
struct FitFightApp: App {
    @StateObject private var themeStore = ThemeStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(themeStore)
                .fitFightTheme(themeStore.current)
        }
    }
}

import SwiftUI

@main
struct FitFightApp: App {
    @State private var languageSettings = LanguageSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(languageSettings)
                .environment(\.locale, languageSettings.locale)
                .environment(\.layoutDirection, languageSettings.layoutDirection)
        }
    }
}

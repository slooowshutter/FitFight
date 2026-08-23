import SwiftUI

/// In-app language. Default `.system` follows the iPhone (and iOS per-app language).
///
/// iOS picks the app language from **preferred languages**, not from country or GPS
/// (Apple QA1828). Explicit English/French override the UI via SwiftUI `\.locale`
/// — not the unsupported `AppleLanguages` UserDefaults key.
@Observable
final class LanguageSettings {
    private static let storageKey = "fitfight.appLanguage"

    var selection: AppLanguage {
        didSet {
            UserDefaults.standard.set(selection.rawValue, forKey: Self.storageKey)
        }
    }

    init(selection: AppLanguage? = nil) {
        self.selection = selection ?? Self.load()
    }

    var locale: Locale {
        selection.locale ?? .autoupdatingCurrent
    }

    var layoutDirection: LayoutDirection {
        locale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }

    private static func load() -> AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english = "en"
    case french = "fr"

    var id: String { rawValue }

    /// Always in that language, so you can find it if the rest of the UI is wrong.
    var nativeDisplayName: String {
        switch self {
        case .system: return ""
        case .english: return "English"
        case .french: return "Français"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: return nil
        case .english: return Locale(identifier: "en")
        case .french: return Locale(identifier: "fr")
        }
    }
}

import Foundation
import Observation

enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case en
    case fr

    var id: String { rawValue }
    var languageCode: String {
        if self != .system { return rawValue }
        return Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true ? "fr" : "en"
    }
    var label: String {
        switch self {
        case .system: return String(appLocalized: "Follow iPhone")
        case .en: return "English"
        case .fr: return "Français"
        }
    }
}

// SwiftUI tracks this read even when a view resolves its text through String(appLocalized:).
@Observable
private final class AppLanguageSelection {
    var language: AppLanguage = .system
}

enum AppLocalization {
    private static let lock = NSLock()
    private static let selection = AppLanguageSelection()

    static func apply(_ language: AppLanguage) {
        lock.lock()
        defer { lock.unlock() }
        selection.language = language
    }

    static var languageCode: String {
        lock.lock()
        let language = selection.language
        lock.unlock()
        return language.languageCode
    }

    static var locale: Locale {
        lock.lock()
        let language = selection.language
        lock.unlock()
        guard language != .system else { return .autoupdatingCurrent }
        var components = Locale.Components(locale: .current)
        components.languageComponents = Locale.Language.Components(
            languageCode: Locale.LanguageCode(language.rawValue),
            region: components.languageComponents.region
        )
        return Locale(components: components)
    }

    static var bundle: Bundle {
        guard let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return .main }
        return bundle
    }
}

extension String {
    // Foundation's locale argument formats interpolations; the bundle selects the translation.
    init(appLocalized value: String.LocalizationValue) {
        self.init(localized: value, bundle: AppLocalization.bundle, locale: AppLocalization.locale)
    }

    init(appLocalized key: StaticString, defaultValue: String.LocalizationValue) {
        self.init(localized: key, defaultValue: defaultValue,
                  bundle: AppLocalization.bundle, locale: AppLocalization.locale)
    }
}

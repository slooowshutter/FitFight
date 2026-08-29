import Foundation

/// Authenticated backend for private uploads and domain commands.
/// Empty `FFAPIBaseURL` / `BuildEnv.apiBaseURL` means backend features are disabled.
enum APIConfig {
    static var baseURL: URL? {
        let raw = firstNonEmpty(BuildEnv.apiBaseURL, bundleString("FFAPIBaseURL"))
        guard let raw else { return nil }
        return URL(string: raw)
    }

    private static func bundleString(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    private static func firstNonEmpty(_ values: String...) -> String? {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}

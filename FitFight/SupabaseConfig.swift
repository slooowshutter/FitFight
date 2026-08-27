import Foundation

/// Hosted project URL and the iOS publishable key.
/// The publishable key is client configuration, not a secret. Never put `sb_secret_...` here.
///
/// CI may overwrite `BuildEnv` before a TestFlight archive. Non-empty values win;
/// otherwise Info.plist (`FFSupabaseURL`, `FFSupabasePublishableKey`); otherwise production.
enum SupabaseConfig {
    private static let productionURL = URL(string: "https://pvqntpteehdvhqyctwum.supabase.co")!
    private static let productionPublishableKey = "sb_publishable_6wP1KNFvJwIE_hX1U2aTfg_u3sk40Li"
    static let stagingURL = URL(string: "https://zstzbfocunthczzubggz.supabase.co")!

    static let projectURL: URL = {
        if let raw = firstNonEmpty(BuildEnv.supabaseURL, bundleString("FFSupabaseURL")),
           let url = URL(string: raw) {
            return url
        }
        return productionURL
    }()

    static let publishableKey = firstNonEmpty(
        BuildEnv.supabasePublishableKey,
        bundleString("FFSupabasePublishableKey")
    ) ?? productionPublishableKey

    static var isConfigured: Bool {
        publishableKey.hasPrefix("sb_publishable_")
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

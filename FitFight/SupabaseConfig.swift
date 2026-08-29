import Foundation

/// Hosted project URL and the iOS publishable key.
/// The publishable key is client configuration, not a secret. Never put `sb_secret_...` here.
///
/// CI may overwrite `BuildEnv` before a TestFlight archive. Non-empty values win;
/// otherwise Info.plist (`FFSupabaseURL`, `FFSupabasePublishableKey`); otherwise the
/// configuration-specific default below.
enum SupabaseConfig {
    private static let productionURL = URL(string: "https://pvqntpteehdvhqyctwum.supabase.co")!
    private static let productionPublishableKey = "sb_publishable_6wP1KNFvJwIE_hX1U2aTfg_u3sk40Li"
    /// Persistent `develop` branch (not a preview). New host after 27 Aug 2026.
    static let stagingURL = URL(string: "https://zstzbfocunthczzubggz.supabase.co")!
    static let stagingPublishableKey = "sb_publishable_7lCDQ1YbMJVUyKZ6Ezq1LA_I-0rZGig"

    /// A local build has no `BuildEnv` — CI writes that file only before an archive.
    /// The fallback used to be production, which meant every simulator run was talking
    /// to live data. Debug now falls back to develop instead; only a Release build with
    /// no injected value can reach production.
    private static var fallbackURL: URL {
        #if DEBUG
        return stagingURL
        #else
        return productionURL
        #endif
    }

    private static var fallbackPublishableKey: String {
        #if DEBUG
        return stagingPublishableKey
        #else
        return productionPublishableKey
        #endif
    }

    static let projectURL: URL = {
        if let raw = firstNonEmpty(BuildEnv.supabaseURL, bundleString("FFSupabaseURL")),
           let url = URL(string: raw) {
            return url
        }
        return fallbackURL
    }()

    static let publishableKey = firstNonEmpty(
        BuildEnv.supabasePublishableKey,
        bundleString("FFSupabasePublishableKey")
    ) ?? fallbackPublishableKey

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

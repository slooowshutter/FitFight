import Foundation

/// Hosted project URL and the iOS publishable key.
/// The publishable key is client configuration, not a secret. Never put `sb_secret_...` here.
enum SupabaseConfig {
    static let projectURL = URL(string: "https://pvqntpteehdvhqyctwum.supabase.co")!

    static let publishableKey = "sb_publishable_6wP1KNFvJwIE_hX1U2aTfg_u3sk40Li"

    static var isConfigured: Bool {
        publishableKey.hasPrefix("sb_publishable_")
    }
}

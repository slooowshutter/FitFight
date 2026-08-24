import Foundation

/// Hosted project URL and the iOS publishable key.
/// The publishable key is client configuration, not a secret. Never put `sb_secret_...` here.
enum SupabaseConfig {
    static let projectURL = URL(string: "https://pvqntpteehdvhqyctwum.supabase.co")!

    /// Paste the `sb_publishable_...` key from Supabase → Project Settings → API Keys.
    static let publishableKey = ""

    static var isConfigured: Bool {
        publishableKey.hasPrefix("sb_publishable_")
    }
}

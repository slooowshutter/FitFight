/// Written by TestFlight or App Store CI before archive.
/// Empty strings mean `SupabaseConfig` / `APIConfig` use their fallbacks
/// and crash reporting stays off. Do not put `sb_secret_...` or PostHog
/// project tokens here.
enum BuildEnv {
    static let supabaseURL = ""
    static let supabasePublishableKey = ""
    static let apiBaseURL = ""
    static let posthogProjectAPIKey = ""
    static let posthogHost = ""
}

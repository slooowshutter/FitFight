import Foundation

enum AppVersion {
    static var label: String {
        "\(marketing) (\(build)) · \(backend)"
    }

    /// Which hosted database this binary talks to. TestFlight that is not `main`
    /// should say `staging` (Supabase develop). `prod` means the production fallback.
    static var backend: String {
        let host = SupabaseConfig.projectURL.host ?? ""
        if host.contains("pvqntpteehdvhqyctwum") {
            return "prod"
        }
        if host.contains("jldjgftoxmluiswpebbd") {
            return "staging"
        }
        return "staging"
    }

    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
}

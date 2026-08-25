import Foundation

enum AppVersion {
    static var label: String {
        let date = shippedOn
        if date.isEmpty {
            return "\(marketing) · build \(build) · \(backend)"
        }
        return "\(marketing) · build \(build) · \(backend) · \(date)"
    }

    /// Date of the newest Changelog row for this marketing version.
    static var shippedOn: String {
        guard let note = Changelog.current else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM"
        return formatter.string(from: note.date)
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

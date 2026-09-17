import Foundation
import StoreKit

enum AppDistribution {
    case appStore, testFlight, development, unknown

    var label: String {
        switch self {
        case .appStore: return "App Store"
        case .testFlight: return "TestFlight"
        case .development: return String(appLocalized: "Development build")
        case .unknown: return String(appLocalized: "Couldn’t verify the installation source")
        }
    }
}

enum AppVersion {
    static func distribution() async -> AppDistribution {
        #if DEBUG || targetEnvironment(simulator)
        return .development
        #else
        do {
            guard case .verified(let transaction) = try await AppTransaction.shared else { return .unknown }
            switch transaction.environment {
            case .production: return .appStore
            case .sandbox: return .testFlight
            case .xcode: return .development
            default: return .unknown
            }
        } catch {
            return .unknown
        }
        #endif
    }

    static var label: String {
        let date = shippedOn
        if date.isEmpty {
            return String(
                appLocalized: "version.label",
                defaultValue: "\(marketing) · build \(build) · \(backend)"
            )
        }
        return String(
            appLocalized: "version.label.with-date",
            defaultValue: "\(marketing) · build \(build) · \(backend) · \(date)"
        )
    }

    /// Date of the newest Changelog row for this marketing version.
    static var shippedOn: String {
        guard let note = Changelog.current else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = AppLocalization.locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: note.date)
    }

    /// Which hosted database this binary talks to. Staging TestFlight uses Supabase
    /// develop; an App Store candidate must show `prod`.
    static var backend: String {
        let host = SupabaseConfig.projectURL.host ?? ""
        if host.contains("pvqntpteehdvhqyctwum") {
            return "prod"
        }
        if host.contains("zstzbfocunthczzubggz") {
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

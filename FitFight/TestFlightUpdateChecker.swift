import Combine
import Foundation
import UIKit

/// Compares this binary's build number to the latest TestFlight upload.
/// The phone cannot query TestFlight; CI publishes a public JSON pointer after each upload.
@MainActor
final class TestFlightUpdateChecker: ObservableObject {
    @Published private(set) var newerBuild: Int?

    private let defaults: UserDefaults
    private var lastAttempt: Date?

    private static let dismissedKey = "fitfight.dismissedTestFlightBuild"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    static func shouldOffer(currentBuild: Int, latestBuild: Int, dismissedBuild: Int) -> Bool {
        latestBuild > currentBuild && latestBuild > dismissedBuild
    }

    func check() async {
        guard !ScreenshotExport.isEnabled else { return }
        guard AppVersion.backend == "staging" else { return }
        guard let url = latestURL else { return }
        if let lastAttempt, Date().timeIntervalSince(lastAttempt) < 60 { return }
        lastAttempt = Date()

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("FitFight", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return }
        guard let latest = try? JSONDecoder().decode(Latest.self, from: data) else { return }

        let current = Int(AppVersion.build) ?? 0
        let dismissed = defaults.integer(forKey: Self.dismissedKey)
        if Self.shouldOffer(
            currentBuild: current,
            latestBuild: latest.build,
            dismissedBuild: dismissed
        ) {
            newerBuild = latest.build
        } else {
            newerBuild = nil
        }
    }

    func dismiss() {
        if let newerBuild {
            defaults.set(newerBuild, forKey: Self.dismissedKey)
        }
        newerBuild = nil
    }

    func openTestFlight() {
        guard let url = URL(string: "itms-beta://") else { return }
        UIApplication.shared.open(url)
    }

    private var latestURL: URL? {
        let raw = BuildEnv.latestTestFlightURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    private struct Latest: Decodable {
        var build: Int
    }
}

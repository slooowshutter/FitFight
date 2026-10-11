import Foundation
import PostHog

@MainActor
enum Analytics {
    private static let defaultHost = "https://us.i.posthog.com"
    private static var started = false

    static func start() {
        guard !started else { return }
        guard !ScreenshotExport.isEnabled, !CompanionPreview.isEnabled else { return }

        let token = BuildEnv.posthogProjectAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard token.hasPrefix("phc_") else { return }

        let hostRaw = BuildEnv.posthogHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let config = PostHogConfig(
            projectToken: token,
            host: hostRaw.isEmpty ? defaultHost : hostRaw
        )
        config.errorTrackingConfig.autoCapture = true
        config.sessionReplay = true
        // SwiftUI needs screenshot mode. The default masks keep every text and image hidden,
        // so step counts and other Health numbers never leave the phone in a replay.
        config.sessionReplayConfig.screenshotMode = true
        // Request URLs carry join codes and fight IDs.
        config.sessionReplayConfig.captureNetworkTelemetry = false
        config.captureApplicationLifecycleEvents = true
        // UIKit screen names are SwiftUI hosting controllers; ContentView names the tabs instead.
        config.captureScreenViews = false
        config.captureElementInteractions = true
        // Tap text would leak what replay masks: step counts, usernames, typed Fight names.
        config.captureAutocaptureElementText = false
        config.surveys = true
        PostHogSDK.shared.setup(config)
        // Staging (TestFlight) and prod (App Store) share one PostHog project; filter on this.
        PostHogSDK.shared.register(["environment": AppVersion.backend])
        started = true
    }

    static func identify(userId: UUID) {
        guard started else { return }
        PostHogSDK.shared.identify(userId.uuidString)
    }

    /// Makes people findable by username in PostHog replays and persons.
    static func describe(_ profile: FitFightProfile) {
        guard started else { return }
        PostHogSDK.shared.setPersonProperties(userPropertiesToSet: [
            "username": profile.handle,
            "environment": AppVersion.backend,
            "app_version": "\(AppVersion.marketing) (\(AppVersion.build))",
        ])
    }

    static func reset() {
        guard started else { return }
        PostHogSDK.shared.reset()
    }
}

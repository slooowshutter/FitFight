import Foundation
import PostHog

@MainActor
enum CrashReporting {
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
        config.sessionReplay = false
        config.captureApplicationLifecycleEvents = false
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.surveys = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.enableSwizzling = false
        config.rageClickConfig.enabled = false
        config.flushAt = 1
        // Crash-only: never send screens, sessions, Health, or product events.
        config.setBeforeSend { event in
            switch event.event {
            case "$exception", "$identify":
                return event
            default:
                return nil
            }
        }
        PostHogSDK.shared.setup(config)
        started = true
    }

    static func identify(userId: UUID) {
        guard started else { return }
        PostHogSDK.shared.identify(userId.uuidString)
    }

    static func reset() {
        guard started else { return }
        PostHogSDK.shared.reset()
    }
}

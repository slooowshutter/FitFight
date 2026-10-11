import Foundation
import PostHog

@MainActor
enum Analytics {
    private static let defaultHost = "https://us.i.posthog.com"
    private static var started = false
    nonisolated static let enabledKey = "fitfight.analytics.enabled"

    /// Profile → Settings → Share usage analytics. Crash reports are sent either way.
    nonisolated static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

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
        config.sessionReplay = isEnabled
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
        config.surveys = isEnabled
        config.setBeforeSend { event in
            isEnabled || ["$exception", "$identify"].contains(event.event) ? event : nil
        }
        PostHogSDK.shared.setup(config)
        started = true
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        guard started else { return }
        if enabled {
            PostHogSDK.shared.startSessionRecording()
        } else {
            PostHogSDK.shared.stopSessionRecording()
        }
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

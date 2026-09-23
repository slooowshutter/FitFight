import SwiftUI

/// First-run notification ask, after Apple Health. Pre-prompt before iPhone’s sheet.
struct NotificationOnboardingView: View {
    var skipsIfAlreadyDetermined: Bool = true
    var onFinished: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var push: PushNotificationService

    @State private var isAsking = false

    var body: some View {
        OnboardingPage(
            title: "Challenge reminders",
            message: "FitFight will send challenge reminders. Lock-screen alerts never include step counts.",
            actionTitle: String(appLocalized: "Continue"),
            working: isAsking,
            showsSpinner: isAsking,
            onSkip: finish
        ) {
            Task { await allow() }
        }
        .task {
            await push.refreshAuthorizationStatus()
            guard skipsIfAlreadyDetermined else { return }
            if push.permissionStatus != .notDetermined {
                if push.permissionStatus == .authorized {
                    await push.registerIfAuthorized()
                }
                finish()
            }
        }
    }

    private func allow() async {
        isAsking = true
        defer { isAsking = false }
        await push.requestSystemPermission()
        finish()
    }

    private func finish() {
        push.markPromptHandledThisSession()
        session.finishNotificationOnboarding()
        onFinished?()
    }
}

import SwiftUI

/// Introduces Feedback before the optional suggested Fights.
struct RequestsOnboardingView: View {
    var onFinished: (() -> Void)? = nil

    @EnvironmentObject private var session: SessionStore

    var body: some View {
        OnboardingPage(
            title: "Bugs & requests",
            message: "You can go to the Feedback tab to submit a feature you want or a bug you see. Those will be fixed rapidly.",
            actionTitle: String(appLocalized: "OK")
        ) {
            session.finishRequestsOnboarding()
            onFinished?()
        }
    }
}

/// A first-run page: title, message, the primary action, and an optional Not now.
struct OnboardingPage: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let actionTitle: String
    var working = false
    var showsSpinner = false
    var onSkip: (() -> Void)? = nil
    let action: () -> Void

    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text(title)
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text(message)
                .ffType(.body)
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(3)
                .padding(.top, 10)
            FFScreenCTA(title: actionTitle, enabled: !working, busy: showsSpinner, action: action)
                .padding(.top, 28)
            if let onSkip {
                Button(action: onSkip) {
                    Text("Not now")
                        .ffType(.label)
                        .foregroundStyle(theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 16)
                }
                .buttonStyle(FFHapticPlainStyle())
                .disabled(working)
            }
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
    }
}

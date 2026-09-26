import SwiftUI

/// Replays Health, Fight offers and reminders without changing completed onboarding progress.
struct OnboardingPreviewView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(String(appLocalized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)
            OnboardingView(isReplay: true) { dismiss() }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

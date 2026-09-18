import SwiftUI

/// Replays the onboarding sequence without resetting the account.
struct OnboardingPreviewView: View {
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var showingNotifications = false
    @State private var showingRequests = false
    @State private var showingSuggestions = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(String(localized: "Close")) { dismiss() }
                    .ffType(.label)
                    .foregroundStyle(theme.mossText)
            }
            .padding(.horizontal, theme.space.screenPadding)
            .padding(.vertical, 12)

            if showingSuggestions {
                SuggestedFightsOnboardingView { dismiss() }
            } else if showingRequests {
                RequestsOnboardingView {
                    showingSuggestions = true
                }
            } else if showingNotifications {
                NotificationOnboardingView(skipsIfAlreadyDetermined: false) {
                    showingRequests = true
                }
            } else {
                HealthOnboardingView {
                    showingNotifications = true
                }
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

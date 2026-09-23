import SwiftUI

struct NotificationOnboardingView: View {
    let animal: StockCompanion
    @Binding var busy: Bool
    let onFinished: () -> Void
    @EnvironmentObject private var push: PushNotificationService
    @Environment(\.ffTheme) private var theme

    var body: some View {
        OnboardingPage {
            OnboardingHeading(title: String(appLocalized: "onboarding.reminders.title", defaultValue: "A nudge when\nit matters."))
            FFCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "bell").foregroundStyle(theme.emberText)
                        Text("FitFight").font(.ff(14, 800))
                        Spacer()
                        Text(String(appLocalized: "now")).ffType(.caption).foregroundStyle(theme.textSecondary)
                    }
                    Text(String(appLocalized: "Your Fight is finishing soon")).font(.ff(16, 800))
                    Text(String(appLocalized: "Open FitFight to sync your latest steps."))
                        .ffType(.body).foregroundStyle(theme.textSecondary)
                }
            }
            .modifier(OnboardingEntrance(order: 1))
            OnboardingSpeech(animal: animal, text: String(appLocalized: "Make that last walk count."))
        } actions: {
            FFScreenCTA(title: String(appLocalized: "Turn on reminders"), enabled: !busy, busy: busy) {
                Task {
                    guard !busy else { return }
                    busy = true
                    defer { busy = false }
                    await push.requestSystemPermission()
                    guard !Task.isCancelled else { return }
                    push.markPromptHandledThisSession()
                    onFinished()
                }
            }
            OnboardingSkip(title: String(appLocalized: "Not now")) {
                push.markPromptHandledThisSession()
                onFinished()
            }
            .disabled(busy)
        }
        .task {
            await push.refreshAuthorizationStatus()
            await push.registerIfAuthorized()
        }
    }
}

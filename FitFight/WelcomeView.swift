import SwiftUI

/// Account creation precedes companion choice; returning accounts go straight to their existing destination.
struct WelcomeView: View {
    @Environment(\.ffTheme) private var theme
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(step: 1)
            OnboardingPage {
                GeometryReader { geometry in
                    ZStack(alignment: .bottom) {
                        OnboardingAnimal(animal: .goat)
                            .frame(width: geometry.size.width * 0.59, height: 236)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        OnboardingAnimal(animal: .fox, delay: 0.12)
                            .frame(width: geometry.size.width * 0.59, height: 236)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Text(String(appLocalized: "Taking the long way?"))
                            .font(.ff(14, 800))
                            .foregroundStyle(theme.emberText)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .background(theme.card, in: Capsule())
                            .overlay { Capsule().strokeBorder(theme.line, lineWidth: 1) }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                }
                .frame(height: 257)
                OnboardingHeading(
                    title: String(appLocalized: "onboarding.welcome.title", defaultValue: "A little rivalry.\nA few more steps."),
                    subtitle: String(appLocalized: "Friendly competition for your everyday walks.")
                )
            } actions: {
                SignInControls()
                if session.isBusy {
                    Text(String(appLocalized: "Signing in…"))
                        .ffType(.caption).foregroundStyle(theme.textSecondary)
                }
            }
        }
        .background(theme.bg.ignoresSafeArea())
    }
}

#Preview {
    WelcomeView()
        .environmentObject(SessionStore(preview: ()))
        .fitFightTheme(ThemeCatalog.theme(.night))
}

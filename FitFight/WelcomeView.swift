import SwiftUI

/// Shown instead of the tabs until the User signs in with Apple.
struct WelcomeView: View {
    @Environment(\.ffTheme) private var theme
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Image(systemName: "trophy.fill")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(theme.mossText)
                .frame(width: 64, height: 64)
                .background(theme.mossFill.opacity(0.20), in: Circle())
                .padding(.bottom, 24)
            Text("FitFight")
                .ffType(.title)
                .foregroundStyle(theme.text)
            Text("Challenge your friends. Winner takes the glory.")
                .font(.ff(17, 700))
                .foregroundStyle(theme.textSecondary)
                .padding(.top, 10)
            Text("Sign in with Apple to get in. First time here, that creates your account.")
                .ffType(.body)
                .foregroundStyle(theme.textFaint)
                .lineSpacing(3)
                .padding(.top, 16)
            AppleSignInControl()
                .padding(.top, 28)
            if session.isBusy {
                Text("Signing in…")
                    .ffType(.micro)
                    .foregroundStyle(theme.textFaint)
                    .padding(.top, 10)
            }
            Spacer(minLength: 24)
        }
        .padding(.horizontal, theme.space.screenPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(theme.bg)
    }
}

#Preview {
    WelcomeView()
        .environmentObject(SessionStore(preview: ()))
        .fitFightTheme(ThemeCatalog.theme(.night))
}

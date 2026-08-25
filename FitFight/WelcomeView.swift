import SwiftUI

/// Shown instead of the tabs until the User signs in with Apple.
struct WelcomeView: View {
    @Environment(\.ffTheme) private var theme
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text("FitFight")
                .font(theme.font(.display))
                .foregroundStyle(theme.text)
            Text("Challenge your friends. Winner takes the glory.")
                .font(.ff(17))
                .foregroundStyle(theme.muted)
                .padding(.top, 10)
            Text("Sign in with Apple to get in. First time here, that creates your account.")
                .font(.ff(13))
                .foregroundStyle(theme.faint)
                .padding(.top, 16)
            AppleSignInControl()
                .padding(.top, 28)
            if session.isBusy {
                Text("Signing in…")
                    .font(.ff(11))
                    .foregroundStyle(theme.faint)
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
        .fitFightTheme(ThemeCatalog.theme(base: .dark, accent: .blue))
}

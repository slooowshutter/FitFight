import GoogleSignInSwift
import SwiftUI
import UIKit

struct SignInControls: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppleSignInControl()
            GoogleSignInButton(
                scheme: theme.mode == .day ? .light : .dark,
                style: .wide,
                state: session.isBusy ? .disabled : .normal
            ) {
                guard var presenter = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .filter({ $0.activationState == .foregroundActive })
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)?.rootViewController else {
                    session.authError = String(appLocalized: "Couldn’t sign in. Try again.")
                    return
                }
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                Task { await session.signInWithGoogle(presenting: presenter) }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .disabled(session.isBusy)
            .accessibilityLabel(String(appLocalized: "Sign in with Google"))

            if let authError = session.authError {
                Text(authError)
                    .font(.ff(11))
                    .foregroundStyle(theme.emberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

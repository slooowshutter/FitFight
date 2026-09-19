import SwiftUI
import UIKit

struct SignInControls: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AppleSignInControl()
            Button {
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
            } label: {
                HStack(spacing: 12) {
                    // Preserve Google's supplied 20pt logo; clip only the icon asset's button surround.
                    Image("GoogleSignInIcon")
                        .resizable()
                        .frame(width: 44, height: 44)
                        .frame(width: 20, height: 20)
                        .clipped()
                        .accessibilityHidden(true)
                    Text("Sign in with Google")
                        .font(.custom("GoogleSans-TextMedium", fixedSize: 17))
                        .foregroundStyle(theme.googleInk)
                }
                .padding(.horizontal, 16)
                .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                .background(theme.googleFill, in: RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(theme.googleBorder, lineWidth: 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(session.isBusy)
            .opacity(session.isBusy ? 0.5 : 1)
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

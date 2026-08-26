import AuthenticationServices
import SwiftUI

struct AppleSignInControl: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                Task { await handle(result) }
            }
            .signInWithAppleButtonStyle(theme.baseID == .light ? .black : .white)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .disabled(session.isBusy)
            .accessibilityLabel("Sign in with Apple")

            if let authError = session.authError {
                Text(authError)
                    .font(.ff(11))
                    .foregroundStyle(theme.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure:
            session.authError = "Couldn’t sign in. Try again."
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                session.authError = "Couldn’t sign in. Try again."
                return
            }
            await session.signInWithApple(idToken: idToken, fullName: formattedName(credential.fullName))
        }
    }

    private func formattedName(_ name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }
}

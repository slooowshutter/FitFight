import AuthenticationServices
import CryptoKit
import Foundation
import SwiftUI

struct AppleSignInControl: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.ffTheme) private var theme
    @State private var signInNonce: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SignInWithAppleButton(.signIn) { request in
                let nonce = Self.randomNonce()
                signInNonce = nonce
                request.nonce = Self.sha256(nonce)
                request.requestedScopes = [.email, .fullName]
            } onCompletion: { result in
                let nonce = signInNonce
                signInNonce = nil
                Task { await handle(result, nonce: nonce) }
            }
            .signInWithAppleButtonStyle(theme.mode == .day ? .black : .white)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
            .disabled(session.isBusy)
            .accessibilityLabel("Sign in with Apple")

            if let authError = session.authError {
                Text(authError)
                    .font(.ff(11))
                    .foregroundStyle(theme.emberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>, nonce: String?) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled {
                return
            }
            session.authError = "Apple sign-in didn’t finish. Try again."
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8),
                let codeData = credential.authorizationCode,
                let authorizationCode = String(data: codeData, encoding: .utf8),
                let nonce
            else {
                session.authError = "Couldn’t sign in. Try again."
                return
            }
            await session.signInWithApple(
                idToken: idToken,
                authorizationCode: authorizationCode,
                nonce: nonce,
                fullName: formattedName(credential.fullName)
            )
        }
    }

    private func formattedName(_ name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let formatted = PersonNameComponentsFormatter.localizedString(from: name, style: .default)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    private static func randomNonce() -> String {
        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<32).map { _ in
            characters[Int.random(in: characters.indices, using: &generator)]
        })
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

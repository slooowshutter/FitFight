import CryptoKit
import Foundation

final class UIViewController {}
struct GIDConfiguration {
    let clientID: String
    let serverClientID: String
}
struct Token { let tokenString: String }
struct GoogleUser {
    let idToken: Token?
    let accessToken: Token
}
struct GoogleResult { let user: GoogleUser }
let kGIDSignInErrorDomain = "com.google.GIDSignIn"
struct GIDSignInError {
    enum Code: Int { case canceled = -5 }
}

@MainActor
final class GIDSignIn {
    static let sharedInstance = GIDSignIn()
    var configuration: GIDConfiguration?
    var continuation: CheckedContinuation<GoogleResult, Error>?
    var nonce: String?
    var calls = 0
    var signOuts = 0

    func signIn(
        withPresenting: UIViewController, hint: String?, additionalScopes: [String]?, nonce: String
    ) async throws -> GoogleResult {
        precondition(hint == nil && additionalScopes == nil, "Only basic identity scopes are needed")
        self.nonce = nonce
        calls += 1
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func finish(token: String? = "google-id-token", error: Error? = nil) {
        let pending = continuation!
        continuation = nil
        if let error {
            pending.resume(throwing: error)
        } else {
            pending.resume(returning: GoogleResult(user: GoogleUser(
                idToken: token.map { Token(tokenString: $0) },
                accessToken: Token(tokenString: "google-access-token")
            )))
        }
    }

    func signOut() { signOuts += 1 }
}

@MainActor
enum CompanionPreview {
    static var isEnabled = false
    static let writeUnavailable = "Preview cannot sign in"
}
@MainActor
enum SupabaseConfig {
    static var projectURL = URL(string: "https://zstzbfocunthczzubggz.supabase.co")!
}
@MainActor
final class AppUpdateChecker {
    static let shared = AppUpdateChecker()
    var allowsUse = true
    func permitsRequests() async -> Bool { allowsUse }
}
extension String {
    init(appLocalized value: String) { self = value }
}
enum Provider { case google }
struct Credentials {
    let provider: Provider
    let idToken: String
    let accessToken: String
    let nonce: String
}
@MainActor
final class Auth {
    var credentials: Credentials?
    var error: Error?
    func signInWithIdToken(credentials: Credentials) async throws {
        self.credentials = credentials
        if let error { throw error }
    }
}
@MainActor
final class Client { let auth = Auth() }

@MainActor
final class SessionStore {
    let client = Client()
    var authError: String?
    var isBusy = false
    var profileLoads = 0
    var googleLinks = 0
    func loadProfile() async { profileLoads += 1 }
    func linkGoogleIdentity(idToken: String, accessToken: String, nonce: String) async throws {
        googleLinks += 1
        precondition(idToken == "google-id-token")
        precondition(accessToken == "google-access-token")
        precondition(nonce.count == 32)
    }
    // GOOGLE_SIGN_IN_METHOD
}

@main
struct GoogleSignInTests {
    @MainActor
    static func main() async {
        let staging = GoogleSignInConfig.configuration(for: SupabaseConfig.projectURL)!
        precondition(staging.clientID == "428975685987-6j9128tgf2k67pkf5tlsdbs58md0b38u.apps.googleusercontent.com")
        precondition(staging.serverClientID == "428975685987-i4dlh5lj59foo21p40pvmmnea5glipac.apps.googleusercontent.com")
        let production = GoogleSignInConfig.configuration(for: URL(string: "https://pvqntpteehdvhqyctwum.supabase.co")!)!
        precondition(production.clientID == "1060235196761-nuoouoc4envuhkpo4kpdfpdg8u20tlq4.apps.googleusercontent.com")
        precondition(production.serverClientID == "1060235196761-uo86cnhqd7rp1oms7islaq4u4vd71vek.apps.googleusercontent.com")
        precondition(GoogleSignInConfig.configuration(for: URL(string: "https://unknown.supabase.co")!) == nil)

        let google = GIDSignIn.sharedInstance
        let store = SessionStore()
        let presenter = UIViewController()
        let first = Task { await store.signInWithGoogle(presenting: presenter) }
        while google.continuation == nil { await Task.yield() }
        precondition(store.isBusy, "Controls stay disabled while Google is presenting")
        await store.signInWithGoogle(presenting: presenter)
        precondition(google.calls == 1, "Repeated taps must not open a second authorization")
        precondition(google.configuration?.clientID == staging.clientID)
        google.finish()
        await first.value
        let credentials = store.client.auth.credentials!
        let expectedNonce = SHA256.hash(data: Data(credentials.nonce.utf8))
            .map { String(format: "%02x", $0) }.joined()
        precondition(google.nonce == expectedNonce, "Google gets the hash; Supabase gets the raw nonce")
        precondition(credentials.nonce.count == 32)
        precondition(credentials.provider == .google)
        precondition(credentials.idToken == "google-id-token")
        precondition(credentials.accessToken == "google-access-token")
        precondition(store.profileLoads == 1 && store.googleLinks == 1 && !store.isBusy && store.authError == nil)

        let cancelled = Task { await store.signInWithGoogle(presenting: presenter) }
        while google.continuation == nil { await Task.yield() }
        precondition(google.nonce != expectedNonce, "Every attempt must use a fresh nonce")
        google.finish(error: NSError(domain: kGIDSignInErrorDomain, code: -5))
        await cancelled.value
        precondition(store.authError == nil && !store.isBusy && store.profileLoads == 1)

        let missing = SessionStore()
        let missingTask = Task { await missing.signInWithGoogle(presenting: presenter) }
        while google.continuation == nil { await Task.yield() }
        google.finish(token: nil)
        await missingTask.value
        precondition(missing.client.auth.credentials == nil && missing.profileLoads == 0)
        precondition(missing.authError != nil && !missing.isBusy)

        let failed = SessionStore()
        failed.client.auth.error = NSError(domain: "Auth", code: 400, userInfo: [
            NSLocalizedDescriptionKey: "provider is not enabled",
        ])
        let failedTask = Task { await failed.signInWithGoogle(presenting: presenter) }
        while google.continuation == nil { await Task.yield() }
        google.finish()
        await failedTask.value
        precondition(failed.profileLoads == 0 && !failed.isBusy)
        precondition(failed.authError == "This sign-in provider is off on this database.")
        precondition(google.signOuts == 3, "Cancellation, missing token, and rejected exchange clear Google state")

        let calls = google.calls
        AppUpdateChecker.shared.allowsUse = false
        await store.signInWithGoogle(presenting: presenter)
        precondition(!store.isBusy && google.calls == calls, "Update gate blocks the provider")
        AppUpdateChecker.shared.allowsUse = true
        CompanionPreview.isEnabled = true
        await store.signInWithGoogle(presenting: presenter)
        precondition(google.calls == calls, "Fixtures cannot open Google")
        CompanionPreview.isEnabled = false
        SupabaseConfig.projectURL = URL(string: "https://unknown.supabase.co")!
        await store.signInWithGoogle(presenting: presenter)
        precondition(!store.isBusy && google.calls == calls && store.authError != nil)
        print("Google sign-in passed: environment, callbacks, nonce, exchange, cancellation, failures, busy state, update gate")
    }
}

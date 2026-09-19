import Combine
import CryptoKit
import Foundation
import GoogleSignIn
import Supabase
import UIKit

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var authSession: Session?
    @Published private(set) var isRestoringSession = true
    @Published private(set) var profile: FitFightProfile?
    @Published var authError: String?
    @Published private(set) var isBusy = false
    /// A missing account or failed profile load must not leave onboarding waiting forever.
    @Published private(set) var profileUnavailable = false
    private var screenshotSignedIn = false

    // Construct Auth only when needed; a fixture session never opens Keychain or refreshes tokens.
    lazy var client = SupabaseClient(
        supabaseURL: SupabaseConfig.projectURL,
        supabaseKey: SupabaseConfig.publishableKey.isEmpty
            ? "sb_publishable_missing"
            : SupabaseConfig.publishableKey
    )
    private let api = FitFightAPI()
    private static let handleChosenKey = "ff.handle.chosen"
    private static let needsHealthKey = "ff.onboarding.needsHealth"
    private static let needsNotificationKey = "ff.onboarding.needsNotifications"
    private static let needsRequestsKey = "ff.onboarding.needsRequests"
    private static let needsSuggestedPrefix = "ff.onboarding.needsSuggested."
    private static let profileCachePrefix = "fitfight.profile."
    private static let adminHandle = "marc"

    var isSignedIn: Bool { authSession != nil || screenshotSignedIn }

    var needsOnboarding: Bool {
        guard isSignedIn, let profile else { return false }
        if UserDefaults.standard.bool(forKey: Self.handleChosenKey) { return false }
        if let setAt = profile.handleSetAt, !setAt.isEmpty { return false }
        return profile.looksGenerated
    }

    var needsHealthOnboarding: Bool {
        !screenshotSignedIn && !needsOnboarding && UserDefaults.standard.bool(forKey: Self.needsHealthKey)
    }

    var needsNotificationOnboarding: Bool {
        !screenshotSignedIn && !needsOnboarding && !needsHealthOnboarding
            && UserDefaults.standard.bool(forKey: Self.needsNotificationKey)
    }

    var needsRequestsOnboarding: Bool {
        !screenshotSignedIn && !needsOnboarding && !needsHealthOnboarding && !needsNotificationOnboarding
            && UserDefaults.standard.bool(forKey: Self.needsRequestsKey)
    }

    var needsSuggestedOnboarding: Bool {
        guard !screenshotSignedIn, let userID = authSession?.user.id else { return false }
        return !needsOnboarding && !needsHealthOnboarding && !needsNotificationOnboarding && !needsRequestsOnboarding
            && UserDefaults.standard.bool(forKey: Self.needsSuggestedPrefix + userID.uuidString)
    }

    func finishSuggestedOnboarding() {
        guard let userID = authSession?.user.id else { return }
        UserDefaults.standard.removeObject(forKey: Self.needsSuggestedPrefix + userID.uuidString)
        objectWillChange.send()
    }

    var needsCompanionSelection: Bool {
        guard isSignedIn, profile != nil else { return false }
        if screenshotSignedIn || CompanionPreview.isEnabled || ScreenshotExport.isEnabled { return false }
        guard !needsOnboarding, !needsHealthOnboarding, !needsNotificationOnboarding, !needsRequestsOnboarding, !needsSuggestedOnboarding else {
            return false
        }
        return profile?.companionId == nil && !CompanionStore.hasPendingChoice(for: profile?.userId)
    }

    var isFitFightAdmin: Bool {
        guard !screenshotSignedIn else { return false }
        guard let handle = profile?.handle else { return false }
        return handle.caseInsensitiveCompare(Self.adminHandle) == .orderedSame
    }

    func finishHealthOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.needsHealthKey)
        objectWillChange.send()
    }

    func finishNotificationOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.needsNotificationKey)
        objectWillChange.send()
    }

    func finishRequestsOnboarding() {
        UserDefaults.standard.set(false, forKey: Self.needsRequestsKey)
        objectWillChange.send()
    }

    func freshAccessToken() async throws -> String {
        guard !screenshotSignedIn else { throw CompanionPreview.WriteUnavailable() }
        let userID = authSession?.user.id ?? client.auth.currentUser?.id
        let session = try await client.auth.session
        try Task.checkCancellation()
        guard session.user.id == userID, client.auth.currentUser?.id == userID,
              (authSession?.user.id ?? client.auth.currentUser?.id) == userID else {
            throw CancellationError()
        }
        authSession = session
        return session.accessToken
    }

    init(listenForSession: Bool = true) {
        guard listenForSession, !CompanionPreview.isEnabled else {
            isRestoringSession = false
            return
        }
        Task { await listen() }
    }

    /// Screenshot / preview: no Keychain listener.
    convenience init(preview: Void) {
        self.init(listenForSession: false)
    }

    /// App Store screenshot fixture: signed in without touching Keychain or hosted data.
    convenience init(screenshot: Void) {
        self.init(listenForSession: false)
        screenshotSignedIn = true
        profile = FitFightProfile(
            userId: UUID(uuidString: "00CBEF0E-6851-4AAB-B47A-88B0D7946738")!,
            handle: "maya_moves",
            displayName: "Maya",
            handleSetAt: "2026-09-02T00:00:00Z",
            referralCode: nil,
            avatar: nil
        )
    }

    #if DEBUG && targetEnvironment(simulator)
    convenience init(companionPreview: Void) {
        self.init(screenshot: ())
        profile = FitFightProfile(
            userId: UUID(uuidString: CompanionPreview.people[0].id)!,
            handle: "marc", displayName: "Marc", handleSetAt: "2026-09-13T00:00:00Z",
            referralCode: nil, avatar: nil
        )
    }
    #endif

    func signInWithApple(
        idToken: String,
        authorizationCode: String,
        nonce: String,
        fullName: String?
    ) async {
        guard !CompanionPreview.isEnabled else { authError = CompanionPreview.writeUnavailable; return }
        guard !isBusy else { return }
        authError = nil
        isBusy = true
        defer { isBusy = false }
        guard await AppUpdateChecker.shared.permitsRequests() else { return }
        do {
            let signedIn = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .apple,
                    idToken: idToken,
                    nonce: nonce
                )
            )
            if let fullName, !fullName.isEmpty {
                try? await client.auth.update(
                    user: UserAttributes(
                        data: ["full_name": .string(fullName)]
                    )
                )
                if client.auth.currentUser?.id == signedIn.user.id {
                    _ = try? await api.updateProfile(displayName: fullName, accessToken: signedIn.accessToken)
                }
            }
            try? await api.storeAppleAuthorizationCode(
                authorizationCode,
                accessToken: signedIn.accessToken
            )
            await loadProfile()
        } catch {
            authError = Self.signInFailureMessage(error)
        }
    }

    func signInWithGoogle(presenting viewController: UIViewController) async {
        guard !CompanionPreview.isEnabled else { authError = CompanionPreview.writeUnavailable; return }
        guard !isBusy else { return }
        authError = nil
        isBusy = true
        defer { isBusy = false }
        guard await AppUpdateChecker.shared.permitsRequests() else { return }
        guard let configuration = GoogleSignInConfig.configuration(for: SupabaseConfig.projectURL) else {
            authError = String(appLocalized: "Google sign-in is not configured for this build.")
            return
        }

        let characters = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        let nonce = String((0..<32).map { _ in
            characters[Int.random(in: characters.indices, using: &generator)]
        })
        // Supabase checks the raw nonce against the SHA-256 nonce in Google's ID token.
        let hashedNonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }.joined()
        GIDSignIn.sharedInstance.configuration = configuration
        do {
            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: nil,
                nonce: hashedNonce
            )
            guard let idToken = result.user.idToken?.tokenString, !idToken.isEmpty else {
                GIDSignIn.sharedInstance.signOut()
                authError = String(appLocalized: "Couldn’t sign in. Try again.")
                return
            }
            _ = try await client.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString,
                    nonce: nonce
                )
            )
            await loadProfile()
        } catch {
            GIDSignIn.sharedInstance.signOut()
            let googleError = error as NSError
            if googleError.domain == kGIDSignInErrorDomain,
               googleError.code == GIDSignInError.Code.canceled.rawValue {
                return
            }
            authError = Self.signInFailureMessage(error)
        }
    }

    #if DEBUG
    /// Adopts a session the run script minted. Same flow as the Next.js middleware:
    /// the script calls `admin/generate_link` with the secret key to mint a one-time
    /// token, exchanges it at `/auth/v1/verify`, and passes the resulting tokens here.
    /// The secret key never enters the app — only the finished session does.
    func devAdoptSessionIfNeeded() async {
        #if targetEnvironment(simulator)
        guard !isSignedIn else { return }
        let env = ProcessInfo.processInfo.environment
        guard let access = env["FF_DEV_ACCESS_TOKEN"], !access.isEmpty,
              let refresh = env["FF_DEV_REFRESH_TOKEN"], !refresh.isEmpty
        else { return }
        do {
            _ = try await client.auth.setSession(accessToken: access, refreshToken: refresh)
            await loadProfile()
        } catch {
            authError = String(
                appLocalized: "session.dev-rejected",
                defaultValue: "Dev session rejected: \(error.localizedDescription)"
            )
        }
        #endif
    }

    #endif

    func signOut() async {
        guard !screenshotSignedIn else { authError = CompanionPreview.writeUnavailable; return }
        authError = nil
        await PushNotificationService.shared.revokeLocalRegistration()
        try? await client.auth.signOut()
        GIDSignIn.sharedInstance.signOut()
        authSession = nil
        profile = nil
        profileUnavailable = false
        CrashReporting.reset()
        UserDefaults.standard.removeObject(forKey: Self.handleChosenKey)
        UserDefaults.standard.removeObject(forKey: Self.needsHealthKey)
        UserDefaults.standard.removeObject(forKey: Self.needsNotificationKey)
        UserDefaults.standard.removeObject(forKey: Self.needsRequestsKey)
    }

    static func signInFailureMessage(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid api key") || text.contains("another supabase project") {
            return String(appLocalized: "This build’s key doesn’t match the staging database.")
        }
        if text.contains("provider is not enabled")
            || text.contains("unsupported provider")
            || text.contains("provider not enabled") {
            return String(appLocalized: "This sign-in provider is off on this database.")
        }
        if text.contains("nscurlerror")
            || text.contains("nsurlerrordomain")
            || text.contains("could not connect")
            || text.contains("hostname could not be found")
            || text.contains("not known") {
            return String(appLocalized: "Can’t reach the staging database.")
        }
        return String(appLocalized: "Couldn’t sign in. Try again.")
    }

    static func isValidHandle(_ raw: String) -> Bool {
        let handle = strippedHandle(raw)
        return handle.range(of: "^[a-z0-9_]{2,30}$", options: .regularExpression) != nil
    }

    static func strippedHandle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    func setHandle(_ raw: String, avatarMediaId: UUID? = nil) async throws {
        guard !screenshotSignedIn else { throw CompanionPreview.WriteUnavailable() }
        guard await AppUpdateChecker.shared.permitsRequests() else {
            throw FitFightAPIError.http(
                status: 426,
                code: "update_required",
                message: nil
            )
        }
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            throw HandleError.notSignedIn
        }
        let handle = Self.strippedHandle(raw)
        guard Self.isValidHandle(handle) else {
            throw HandleError.invalid
        }
        do {
            let token = try await freshAccessToken()
            let updated = try await api.updateProfile(
                handle: handle,
                avatarMediaId: avatarMediaId,
                timeZone: TimeZone.current.identifier,
                accessToken: token
            )
            UserDefaults.standard.set(true, forKey: Self.handleChosenKey)
            UserDefaults.standard.set(true, forKey: Self.needsHealthKey)
            UserDefaults.standard.set(true, forKey: Self.needsNotificationKey)
            UserDefaults.standard.set(true, forKey: Self.needsRequestsKey)
            try Task.checkCancellation()
            guard authSession?.user.id == userId, client.auth.currentUser?.id == userId else {
                throw CancellationError()
            }
            UserDefaults.standard.set(true, forKey: Self.needsSuggestedPrefix + userId.uuidString)
            profile = updated
            if let data = try? JSONEncoder().encode(updated) {
                UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if case FitFightAPIError.http(_, let code, _) = error {
                if code == "handle_taken" { throw HandleError.taken }
                if code == "validation" { throw HandleError.invalid }
                if code == "profile_missing" {
                    markProfileMissing(for: userId)
                    throw HandleError.notSignedIn
                }
            }
            throw HandleError.failed
        }
    }

    func updateIdentity(displayName: String, handle: String, timeZone: TimeZone) async throws {
        guard let userId = authSession?.user.id else { throw HandleError.notSignedIn }
        let token = try await freshAccessToken()
        let updated = try await api.updateProfile(handle: handle, displayName: displayName, timeZone: timeZone.identifier, accessToken: token)
        try Task.checkCancellation()
        guard authSession?.user.id == userId else { throw CancellationError() }
        profile = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
        }
    }

    func setAvatar(_ media: FitFightMedia) async throws {
        guard !screenshotSignedIn else { throw CompanionPreview.WriteUnavailable() }
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            throw HandleError.notSignedIn
        }
        let token = try await freshAccessToken()
        let updated = try await api.updateProfile(avatarMediaId: media.id, accessToken: token)
        try Task.checkCancellation()
        guard authSession?.user.id == userId else { throw CancellationError() }
        profile = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
        }
    }

    func companionPrompts() async throws -> [String] {
        let token = try await freshAccessToken()
        return try await api.companionPrompts(accessToken: token)
    }

    func setCompanion(id: String, prompt: String?) async throws {
        guard !screenshotSignedIn else { throw CompanionPreview.WriteUnavailable() }
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            throw HandleError.notSignedIn
        }
        let token = try await freshAccessToken()
        let updated = try await api.updateProfile(
            companionId: id,
            companionPrompt: prompt,
            accessToken: token
        )
        try Task.checkCancellation()
        guard authSession?.user.id == userId else { throw CancellationError() }
        profile = updated
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
        }
    }

    @discardableResult
    func deleteAccount() async -> Bool {
        guard !screenshotSignedIn else { authError = CompanionPreview.writeUnavailable; return false }
        authError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            let userID = authSession?.user.id ?? client.auth.currentUser?.id
            let renewedSession = try await client.auth.refreshSession()
            try Task.checkCancellation()
            guard renewedSession.user.id == userID, client.auth.currentUser?.id == userID,
                  (authSession?.user.id ?? client.auth.currentUser?.id) == userID else {
                throw CancellationError()
            }
            authSession = renewedSession
            let deletion = try await api.deleteAccount(accessToken: renewedSession.accessToken)
            if GIDSignIn.sharedInstance.currentUser != nil {
                try? await GIDSignIn.sharedInstance.disconnect()
                GIDSignIn.sharedInstance.signOut()
            }
            try? await client.auth.signOut()
            authSession = nil
            profile = nil
            profileUnavailable = false
            CrashReporting.reset()
            UserDefaults.standard.removeObject(forKey: Self.handleChosenKey)
            UserDefaults.standard.removeObject(forKey: Self.needsHealthKey)
            UserDefaults.standard.removeObject(forKey: Self.needsNotificationKey)
            UserDefaults.standard.removeObject(forKey: Self.needsRequestsKey)
            if let userID {
                UserDefaults.standard.removeObject(forKey: Self.profileCachePrefix + userID.uuidString)
                CompanionStore.deleteLocalLibrary(for: userID)
            }
            if !deletion.appleAuthorizationRevoked,
               renewedSession.user.identities?.contains(where: { $0.provider == "apple" }) == true {
                authError = String(appLocalized: "Account deleted. To disconnect Apple too, open iPhone Settings, tap your name, then Sign in with Apple → FitFight → Stop Using Apple ID.")
            }
            return true
        } catch {
            authError = String(appLocalized: "Couldn’t delete account. Try again.")
            return false
        }
    }

    private func listen() async {
        for await (event, session) in client.auth.authStateChanges {
            // A token refresh can restore a saved session before the initial-session event.
            if event == .initialSession || session != nil { isRestoringSession = false }
            if let session {
                if event == .tokenRefreshed, authSession?.user.id == session.user.id,
                   profile?.userId == session.user.id {
                    authSession = session
                    continue
                }
                if let previousId = authSession?.user.id, previousId != session.user.id {
                    CrashReporting.reset()
                }
                profileUnavailable = false
                if let data = UserDefaults.standard.data(
                    forKey: Self.profileCachePrefix + session.user.id.uuidString
                ),
                    let cached = try? JSONDecoder().decode(FitFightProfile.self, from: data),
                    cached.userId == session.user.id
                {
                    profile = cached
                } else {
                    profile = nil
                }
                authSession = session
                await loadProfile()
            } else {
                // A nil initial session is signed out; reset crash identity only after a real session is dropped.
                if authSession != nil {
                    CrashReporting.reset()
                }
                authSession = nil
                profile = nil
            }
        }
    }

    func loadProfile() async {
        guard !screenshotSignedIn else { return }
        guard await AppUpdateChecker.shared.permitsRequests() else { return }
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            profile = nil
            return
        }
        profileUnavailable = false
        for attempt in 0..<3 {
            do {
                let token = try await freshAccessToken()
                let row = try await api.profile(accessToken: token)
                try Task.checkCancellation()
                guard authSession?.user.id == userId, client.auth.currentUser?.id == userId else { return }
                profile = row
                if let data = try? JSONEncoder().encode(row) {
                    UserDefaults.standard.set(data, forKey: Self.profileCachePrefix + userId.uuidString)
                }
                return
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                      authSession?.user.id == userId, client.auth.currentUser?.id == userId else { return }
                if case FitFightAPIError.http(_, let code, _) = error, code == "profile_missing" {
                    markProfileMissing(for: userId)
                    return
                }
                if attempt == 2 {
                    if profile?.userId != userId {
                        profile = nil
                        profileUnavailable = true
                    }
                } else {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
    }

    private func markProfileMissing(for userId: UUID) {
        guard (authSession?.user.id ?? client.auth.currentUser?.id) == userId else { return }
        profile = nil
        profileUnavailable = true
        UserDefaults.standard.removeObject(forKey: Self.profileCachePrefix + userId.uuidString)
    }
}

enum HandleError: LocalizedError {
    case notSignedIn
    case invalid
    case taken
    case failed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return String(appLocalized: "Sign in first.")
        case .invalid: return String(appLocalized: "Use 2–30 letters, numbers, or underscore.")
        case .taken: return String(appLocalized: "That username is taken.")
        case .failed: return String(appLocalized: "Couldn’t save that username.")
        }
    }
}

import Combine
import Foundation
import Supabase

struct FitFightProfile: Decodable, Equatable {
    let userId: UUID
    let handle: String
    let displayName: String
    let handleSetAt: String?

    var atHandle: String { "@\(handle)" }

    var looksGenerated: Bool {
        handle.hasPrefix("user_") && handle.count == 17
    }

    var initials: String {
        let parts = displayName.split(separator: " ").filter { !$0.isEmpty }
        if parts.count >= 2 {
            return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
        }
        if let first = parts.first, !first.isEmpty {
            return String(first.prefix(2)).uppercased()
        }
        return String(handle.prefix(2)).uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case handle
        case displayName = "display_name"
        case handleSetAt = "handle_set_at"
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var authSession: Session?
    @Published private(set) var profile: FitFightProfile?
    @Published var authError: String?
    @Published private(set) var isBusy = false

    let client: SupabaseClient
    private static let handleChosenKey = "ff.handle.chosen"

    var isSignedIn: Bool { authSession != nil }

    var needsOnboarding: Bool {
        guard isSignedIn, let profile else { return false }
        if UserDefaults.standard.bool(forKey: Self.handleChosenKey) { return false }
        if let setAt = profile.handleSetAt, !setAt.isEmpty { return false }
        return profile.looksGenerated
    }

    init(listenForSession: Bool = true) {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.publishableKey.isEmpty
                ? "sb_publishable_missing"
                : SupabaseConfig.publishableKey
        )
        guard listenForSession else { return }
        Task { await listen() }
    }

    /// Screenshot / preview: no Keychain listener.
    convenience init(preview: Void) {
        self.init(listenForSession: false)
    }

    func signInWithApple(idToken: String, fullName: String?) async {
        authError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            _ = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken)
            )
            if let fullName, !fullName.isEmpty {
                try? await client.auth.update(
                    user: UserAttributes(
                        data: ["full_name": .string(fullName)]
                    )
                )
                if let userId = client.auth.currentUser?.id {
                    try? await client.from("profiles")
                        .update(["display_name": fullName])
                        .eq("user_id", value: userId)
                        .execute()
                }
            }
            await loadProfile()
        } catch {
            authError = Self.signInFailureMessage(error)
        }
    }

    func signOut() async {
        await signOut(message: nil)
    }

    func retryLoadProfile() async {
        authError = nil
        isBusy = true
        defer { isBusy = false }
        await loadProfile()
    }

    static func signInFailureMessage(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid api key") || text.contains("another supabase project") {
            return "This build’s key doesn’t match the staging database."
        }
        if text.contains("provider is not enabled")
            || text.contains("unsupported provider")
            || text.contains("provider not enabled") {
            return "Apple Sign In is off on this database."
        }
        if text.contains("nscurlerror")
            || text.contains("nsurlerrordomain")
            || text.contains("could not connect")
            || text.contains("hostname could not be found")
            || text.contains("not known") {
            return "Can’t reach the staging database."
        }
        return "Couldn’t sign in. Try again."
    }

    static func profileFailureMessage(_ error: Error) -> String {
        let text = error.localizedDescription.lowercased()
        if text.contains("invalid jwt")
            || text.contains("invalid api key")
            || text.contains("another supabase project") {
            return "This build talks to a new database. Sign in again."
        }
        if text.contains("nscurlerror")
            || text.contains("nsurlerrordomain")
            || text.contains("could not connect")
            || text.contains("hostname could not be found")
            || text.contains("not known") {
            return "Can’t reach the staging database."
        }
        return "Couldn’t load your account. Try again."
    }

    static func isInvalidSession(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("invalid jwt")
            || text.contains("jwt expired")
            || text.contains("invalid api key")
            || text.contains("another supabase project")
            || text.contains("session_not_found")
    }

    static func isMissingRow(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return text.contains("pgrst116")
            || text.contains("0 rows")
            || text.contains("the result contains 0 rows")
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

    func setHandle(_ raw: String) async throws {
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            throw HandleError.notSignedIn
        }
        let handle = Self.strippedHandle(raw)
        guard Self.isValidHandle(handle) else {
            throw HandleError.invalid
        }
        do {
            try await client.from("profiles")
                .update(ProfileHandleUpdate(handle: handle, handleSetAt: ISO8601DateFormatter().string(from: Date())))
                .eq("user_id", value: userId)
                .execute()
        } catch {
            let text = error.localizedDescription.lowercased()
            if text.contains("23505") || text.contains("duplicate") || text.contains("unique") {
                throw HandleError.taken
            }
            throw HandleError.failed
        }
        UserDefaults.standard.set(true, forKey: Self.handleChosenKey)
        await loadProfile()
    }

    func deleteAccount() async {
        authError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.rpc("delete_own_account").execute()
            await signOut()
        } catch {
            authError = "Couldn’t delete account. Try again."
        }
    }

    private func signOut(message: String?) async {
        try? await client.auth.signOut()
        authSession = nil
        profile = nil
        UserDefaults.standard.removeObject(forKey: Self.handleChosenKey)
        authError = message
    }

    private func listen() async {
        for await (_, session) in client.auth.authStateChanges {
            authSession = session
            if session != nil {
                await loadProfile()
            } else {
                profile = nil
            }
        }
    }

    private func loadProfile() async {
        guard let userId = authSession?.user.id ?? client.auth.currentUser?.id else {
            profile = nil
            return
        }
        if let token = authSession?.accessToken,
           let ref = Self.jwtProjectRef(token) {
            let host = SupabaseConfig.projectURL.host ?? ""
            if !host.contains(ref) {
                await signOut(message: "This build talks to a new database. Sign in again.")
                return
            }
        }

        if let row = await fetchProfile(userId: userId) {
            applyProfile(row, expectedUserId: userId)
            return
        }

        do {
            try await client.rpc("ensure_own_profile").execute()
        } catch {
            if Self.isInvalidSession(error) {
                await signOut(message: Self.profileFailureMessage(error))
                return
            }
        }

        if let row = await fetchProfile(userId: userId) {
            applyProfile(row, expectedUserId: userId)
            return
        }

        guard authSession?.user.id == userId || client.auth.currentUser?.id == userId else {
            return
        }
        profile = nil
        authError = "Couldn’t load your account. Try again."
    }

    private func applyProfile(_ row: FitFightProfile, expectedUserId: UUID) {
        guard authSession?.user.id == expectedUserId || client.auth.currentUser?.id == expectedUserId else {
            return
        }
        profile = row
        authError = nil
    }

    private func fetchProfile(userId: UUID) async -> FitFightProfile? {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let row: FitFightProfile = try await client.from("profiles")
                    .select("user_id, handle, display_name, handle_set_at")
                    .eq("user_id", value: userId)
                    .single()
                    .execute()
                    .value
                return row
            } catch {
                lastError = error
                if Self.isInvalidSession(error) || Self.isMissingRow(error) {
                    break
                }
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        if let fallback = try? await client.from("profiles")
            .select("user_id, handle, display_name")
            .eq("user_id", value: userId)
            .single()
            .execute()
            .value as FitFightProfile? {
            return fallback
        }
        if let lastError, Self.isInvalidSession(lastError) {
            return nil
        }
        return nil
    }

    /// `ref` claim on a Supabase access token is the project id in the host.
    static func jwtProjectRef(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let pad = (4 - base64.count % 4) % 4
        if pad > 0 {
            base64 += String(repeating: "=", count: pad)
        }
        guard
            let data = Data(base64Encoded: base64),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        if let ref = json["ref"] as? String, !ref.isEmpty {
            return ref
        }
        if let iss = json["iss"] as? String, let host = URL(string: iss)?.host {
            let project = host.split(separator: ".").first.map(String.init)
            return project
        }
        return nil
    }
}

private struct ProfileHandleUpdate: Encodable {
    let handle: String
    let handleSetAt: String

    enum CodingKeys: String, CodingKey {
        case handle
        case handleSetAt = "handle_set_at"
    }
}

enum HandleError: LocalizedError {
    case notSignedIn
    case invalid
    case taken
    case failed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "Sign in first."
        case .invalid: return "Use 2–30 letters, numbers, or underscore."
        case .taken: return "That username is taken."
        case .failed: return "Couldn’t save that username."
        }
    }
}

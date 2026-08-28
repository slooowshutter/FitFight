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
    /// Ignore auth events while we are wiping a leftover / dead session.
    private var ignoreIncomingSession = false

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
        let text = errorBlob(error)
        if text.contains("invalid api key") || text.contains("another supabase project") {
            return "This build’s key doesn’t match the staging database."
        }
        if text.contains("provider is not enabled")
            || text.contains("unsupported provider")
            || text.contains("provider not enabled") {
            return "Apple Sign In is off on this database."
        }
        if Self.isUnreachable(text) {
            return "Can’t reach the staging database."
        }
        return "Couldn’t sign in. Try again."
    }

    static func profileFailureMessage(_ error: Error) -> String {
        let text = errorBlob(error)
        if text.contains("invalid jwt")
            || text.contains("invalid api key")
            || text.contains("another supabase project") {
            return "This build talks to a new database. Sign in again."
        }
        if Self.isUnreachable(text) {
            return "Can’t reach the staging database."
        }
        return "Couldn’t load your account. Try again."
    }

    static func isInvalidSession(_ error: Error) -> Bool {
        let text = errorBlob(error)
        return text.contains("invalid jwt")
            || text.contains("jwt expired")
            || text.contains("invalid api key")
            || text.contains("another supabase project")
            || text.contains("session_not_found")
            || text.contains("pgrst301")
            || text.contains("unauthorized")
    }

    static func isMissingRow(_ error: Error) -> Bool {
        let text = errorBlob(error)
        return text.contains("pgrst116")
            || text.contains("0 rows")
            || text.contains("the result contains 0 rows")
    }

    static func jwtMatchesHost(token: String, host: String) -> Bool? {
        guard let ref = jwtProjectRef(token) else { return nil }
        return host.contains(ref)
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
            let text = Self.errorBlob(error)
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

    /// Drop the Keychain session first so the welcome screen appears even if
    /// the host rejects this JWT (leftover from the dead staging project).
    private func signOut(message: String?) async {
        ignoreIncomingSession = true
        isBusy = false
        authSession = nil
        profile = nil
        UserDefaults.standard.removeObject(forKey: Self.handleChosenKey)
        authError = message
        try? await client.auth.signOut(scope: .local)
        ignoreIncomingSession = false
    }

    private func listen() async {
        for await (_, session) in client.auth.authStateChanges {
            if ignoreIncomingSession { continue }
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
        if let token = authSession?.accessToken {
            let host = SupabaseConfig.projectURL.host ?? ""
            if Self.jwtMatchesHost(token: token, host: host) == false {
                await signOut(message: "This build talks to a new database. Sign in again.")
                return
            }
        }

        let first = await fetchProfile(userId: userId)
        if let row = first.row {
            applyProfile(row, expectedUserId: userId)
            return
        }
        if let error = first.error, Self.isInvalidSession(error) {
            await signOut(message: Self.profileFailureMessage(error))
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

        let second = await fetchProfile(userId: userId)
        if let row = second.row {
            applyProfile(row, expectedUserId: userId)
            return
        }
        if let error = second.error, Self.isInvalidSession(error) {
            await signOut(message: Self.profileFailureMessage(error))
            return
        }

        guard authSession?.user.id == userId || client.auth.currentUser?.id == userId else {
            return
        }
        profile = nil
        if let error = second.error ?? first.error {
            authError = Self.profileFailureMessage(error)
        } else {
            authError = "Couldn’t load your account. Try again."
        }
    }

    private func applyProfile(_ row: FitFightProfile, expectedUserId: UUID) {
        guard !ignoreIncomingSession else { return }
        guard authSession?.user.id == expectedUserId || client.auth.currentUser?.id == expectedUserId else {
            return
        }
        profile = row
        authError = nil
    }

    private func fetchProfile(userId: UUID) async -> (row: FitFightProfile?, error: Error?) {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let row: FitFightProfile = try await client.from("profiles")
                    .select("user_id, handle, display_name, handle_set_at")
                    .eq("user_id", value: userId)
                    .single()
                    .execute()
                    .value
                return (row, nil)
            } catch {
                if Self.isInvalidSession(error) || Self.isMissingRow(error) {
                    return (nil, error)
                }
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
        }
        do {
            let fallback: FitFightProfile = try await client.from("profiles")
                .select("user_id, handle, display_name")
                .eq("user_id", value: userId)
                .single()
                .execute()
                .value
            return (fallback, nil)
        } catch {
            lastError = lastError ?? error
            return (nil, lastError)
        }
    }

    /// `ref` claim on a Supabase access token is the project id in the host.
    static func jwtProjectRef(_ token: String) -> String? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
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
            return host.split(separator: ".").first.map(String.init)
        }
        return nil
    }

    static func errorBlob(_ error: Error, depth: Int = 0) -> String {
        guard depth < 4 else { return error.localizedDescription.lowercased() }
        var chunks = [
            String(describing: type(of: error)),
            String(describing: error),
            error.localizedDescription
        ]
        let ns = error as NSError
        chunks.append(ns.domain)
        chunks.append(String(ns.code))
        for value in ns.userInfo.values {
            if let nested = value as? Error {
                chunks.append(errorBlob(nested, depth: depth + 1))
            } else {
                chunks.append(String(describing: value))
            }
        }
        return chunks.joined(separator: " ").lowercased()
    }

    private static func isUnreachable(_ text: String) -> Bool {
        text.contains("nscurlerror")
            || text.contains("nsurlerrordomain")
            || text.contains("could not connect")
            || text.contains("hostname could not be found")
            || text.contains("not known")
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

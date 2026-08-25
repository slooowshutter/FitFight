import Combine
import Foundation
import Supabase

struct FitFightProfile: Decodable, Equatable {
    let userId: UUID
    let handle: String
    let displayName: String

    var atHandle: String { "@\(handle)" }

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
    }
}

@MainActor
final class SessionStore: ObservableObject {
    @Published private(set) var authSession: Session?
    @Published private(set) var profile: FitFightProfile?
    @Published var authError: String?
    @Published private(set) var isBusy = false

    let client: SupabaseClient

    var isSignedIn: Bool { authSession != nil }

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
            authError = "Couldn’t sign in. Try again."
        }
    }

    func signOut() async {
        authError = nil
        try? await client.auth.signOut()
        authSession = nil
        profile = nil
    }

    func deleteAccount() async {
        authError = nil
        isBusy = true
        defer { isBusy = false }
        do {
            try await client.rpc("delete_own_account").execute()
            try? await client.auth.signOut()
            authSession = nil
            profile = nil
        } catch {
            authError = "Couldn’t delete account. Try again."
        }
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
        for attempt in 0..<3 {
            do {
                let row: FitFightProfile = try await client.from("profiles")
                    .select("user_id, handle, display_name")
                    .eq("user_id", value: userId)
                    .single()
                    .execute()
                    .value
                profile = row
                return
            } catch {
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                } else {
                    profile = nil
                }
            }
        }
    }
}

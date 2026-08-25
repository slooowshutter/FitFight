import Combine
import Foundation
import Supabase

struct FriendshipRow: Decodable, Equatable {
    let requesterId: UUID
    let addresseeId: UUID
    let state: String

    enum CodingKeys: String, CodingKey {
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case state
    }

    func otherId(than userId: UUID) -> UUID {
        requesterId == userId ? addresseeId : requesterId
    }
}

struct FriendshipInsert: Encodable {
    let requesterId: UUID
    let addresseeId: UUID
    let state: String

    enum CodingKeys: String, CodingKey {
        case requesterId = "requester_id"
        case addresseeId = "addressee_id"
        case state
    }
}

@MainActor
final class FriendshipStore: ObservableObject {
    @Published private(set) var friends: [FitFightProfile] = []
    @Published private(set) var incoming: [FitFightProfile] = []

    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    static func strippedHandle(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased()
    }

    func searchProfiles(handle raw: String) async throws -> [FitFightProfile] {
        let handle = Self.strippedHandle(raw)
        guard handle.count >= 2 else { return [] }

        let exact: [FitFightProfile] = try await client.from("profiles")
            .select("user_id, handle, display_name")
            .eq("handle", value: handle)
            .limit(8)
            .execute()
            .value
        if !exact.isEmpty { return exact }

        return try await client.from("profiles")
            .select("user_id, handle, display_name")
            .ilike("handle", pattern: "%\(handle)%")
            .limit(8)
            .execute()
            .value
    }

    func requestFriendship(handle raw: String, requesterId: UUID) async throws {
        let matches = try await searchProfiles(handle: raw)
        guard let addressee = matches.first else {
            throw FriendshipError.notFound
        }
        guard addressee.userId != requesterId else {
            throw FriendshipError.selfRequest
        }
        do {
            try await client.from("friendships")
                .insert(
                    FriendshipInsert(
                        requesterId: requesterId,
                        addresseeId: addressee.userId,
                        state: "accepted"
                    )
                )
                .execute()
            return
        } catch {
            if await hasAcceptedPair(requesterId, addressee.userId) {
                return
            }
            try? await accept(requesterId: addressee.userId, addresseeId: requesterId)
            guard await hasAcceptedPair(requesterId, addressee.userId) else {
                throw FriendshipError.failed
            }
        }
    }

    private func hasAcceptedPair(_ a: UUID, _ b: UUID) async -> Bool {
        let rows: [FriendshipRow]
        do {
            rows = try await client.from("friendships")
                .select("requester_id, addressee_id, state")
                .or("requester_id.eq.\(a.uuidString),addressee_id.eq.\(a.uuidString)")
                .execute()
                .value
        } catch {
            return false
        }
        return rows.contains {
            $0.state == "accepted" && $0.otherId(than: a) == b
        }
    }

    func accept(requesterId: UUID, addresseeId: UUID) async throws {
        try await updateState("accepted", requesterId: requesterId, addresseeId: addresseeId)
    }

    func decline(requesterId: UUID, addresseeId: UUID) async throws {
        try await updateState("declined", requesterId: requesterId, addresseeId: addresseeId)
    }

    func load(userId: UUID) async throws {
        let rows: [FriendshipRow] = try await client.from("friendships")
            .select("requester_id, addressee_id, state")
            .or("requester_id.eq.\(userId.uuidString),addressee_id.eq.\(userId.uuidString)")
            .execute()
            .value

        let accepted = rows.filter { $0.state == "accepted" }
        let pendingIn = rows.filter { $0.state == "pending" && $0.addresseeId == userId }
        let ids = Set((accepted + pendingIn).map { $0.otherId(than: userId) })
        let profiles = try await profiles(ids: Array(ids))
        let byId = Dictionary(uniqueKeysWithValues: profiles.map { ($0.userId, $0) })

        friends = accepted.compactMap { byId[$0.otherId(than: userId)] }
        incoming = pendingIn.compactMap { byId[$0.requesterId] }
    }

    private func updateState(_ state: String, requesterId: UUID, addresseeId: UUID) async throws {
        try await client.from("friendships")
            .update(["state": state])
            .eq("requester_id", value: requesterId)
            .eq("addressee_id", value: addresseeId)
            .execute()
    }

    private func profiles(ids: [UUID]) async throws -> [FitFightProfile] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("profiles")
            .select("user_id, handle, display_name")
            .in("user_id", values: ids.map(\.uuidString))
            .execute()
            .value
    }
}

enum FriendshipError: LocalizedError {
    case notFound
    case selfRequest
    case failed

    var errorDescription: String? {
        switch self {
        case .notFound: return "No one with that handle."
        case .selfRequest: return "That’s you."
        case .failed: return "Couldn’t add that friend."
        }
    }
}

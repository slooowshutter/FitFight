import Foundation

enum FitFightAPIError: LocalizedError {
    case notConfigured
    case http(status: Int, body: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "FitFight API is not configured. Set FFAPIBaseURL."
        case .http(let status, let body):
            if body.isEmpty { return "Request failed (\(status))." }
            return body
        case .decoding:
            return "Couldn’t read the server response."
        }
    }
}

struct FitFightDataSource: Codable, Equatable {
    var id: UUID
    var provider: String
    var sourceLabel: String
    var contributingSourceLabels: [String]?
}

struct FitFightHealthKitArchiveAck: Codable, Equatable {
    var samples: Int
    var deletions: Int
    var mergedDays: Int
    var sourceDays: Int
    var sourceId: UUID
    var recalculatedFightIds: [UUID]?
}

struct FitFightCreateFight: Encodable, Equatable {
    var name: String
    var startsAt: Date
    var endsAt: Date
    var timeZone: String
    var outcomeRule: String
    var goalPolicy: String?
    var defaultGoalValue: Double?
    var stakeKind: String
    var stakeMinor: Int?
    var currency: String?
    var actionText: String?
    var inviteHandles: [String]?
    var start: String?
}

struct FitFightSummary: Codable, Equatable {
    var id: UUID
    var state: String
}

struct FitFightInviteCreated: Codable, Equatable {
    var token: String
    var invitedUserId: UUID
}

struct FitFightSyncDue: Codable, Equatable {
    var checked: Int
    var closed: Int
    var fightIds: [UUID]?
}

struct FitFightAPI {
    var baseURL: URL?

    var isConfigured: Bool { baseURL != nil }

    init(baseURL: URL? = FitFightAPI.resolvedBaseURL) {
        self.baseURL = baseURL
    }

    static var resolvedBaseURL: URL? {
        if let url = APIConfig.baseURL { return url }
        let raw = ProcessInfo.processInfo.environment["FFAPIBaseURL"]?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }

    func connectAppleHealth(accessToken: String) async throws -> FitFightDataSource {
        try await post(
            path: "provider-connections/apple-health",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    func uploadHealthKitArchive<Batch: Encodable>(
        _ batch: Batch,
        accessToken: String
    ) async throws -> FitFightHealthKitArchiveAck {
        try await post(
            path: "healthkit/batches",
            accessToken: accessToken,
            body: batch,
            expected: [200]
        )
    }

    func deleteAccount(accessToken: String) async throws {
        let _: DiscardBody = try await delete(
            path: "me",
            accessToken: accessToken,
            expected: [200]
        )
    }

    func createFight(
        _ payload: FitFightCreateFight,
        accessToken: String,
        idempotencyKey: String
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights",
            accessToken: accessToken,
            body: payload,
            idempotencyKey: idempotencyKey,
            expected: [200, 201]
        )
    }

    func invite(
        fightID: UUID,
        handle: String,
        accessToken: String
    ) async throws -> FitFightInviteCreated {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/invites",
            accessToken: accessToken,
            body: HandleBody(handle: handle),
            expected: [200]
        )
    }

    func accept(
        token: String,
        accessToken: String,
        personalTarget: Double? = nil
    ) async throws -> FitFightSummary {
        try await post(
            path: "invites/\(token.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? token)/accept",
            accessToken: accessToken,
            body: AcceptBody(personalTarget: personalTarget),
            expected: [200]
        )
    }

    func acceptFight(
        fightID: UUID,
        accessToken: String,
        personalTarget: Double? = nil
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/accept",
            accessToken: accessToken,
            body: AcceptBody(personalTarget: personalTarget),
            expected: [200]
        )
    }

    func start(
        fightID: UUID,
        accessToken: String,
        when: String = "now"
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/start",
            accessToken: accessToken,
            body: StartBody(when: when),
            expected: [200]
        )
    }

    func syncDueFights(accessToken: String) async throws -> FitFightSyncDue {
        try await post(
            path: "fights/sync-due",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    func cancel(fightID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "fights/\(fightID.uuidString.lowercased())/cancel",
            accessToken: accessToken,
            body: EmptyJSON(),
            expected: [200]
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        accessToken: String,
        body: Body,
        idempotencyKey: String? = nil,
        expected: Set<Int>
    ) async throws -> Response {
        try await request(
            path: path,
            method: "POST",
            accessToken: accessToken,
            body: Self.encoder.encode(body),
            idempotencyKey: idempotencyKey,
            expected: expected
        )
    }

    private func delete<Response: Decodable>(
        path: String,
        accessToken: String,
        expected: Set<Int>
    ) async throws -> Response {
        try await request(
            path: path,
            method: "DELETE",
            accessToken: accessToken,
            body: nil,
            idempotencyKey: nil,
            expected: expected
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        body: Data?,
        idempotencyKey: String?,
        expected: Set<Int>
    ) async throws -> Response {
        guard let requestURL = endpoint(path) else {
            throw FitFightAPIError.notConfigured
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey {
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard expected.contains(status) else {
            let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw FitFightAPIError.http(status: status, body: text)
        }
        if Response.self == DiscardBody.self {
            return DiscardBody() as! Response
        }
        if data.isEmpty, let empty = EmptyJSON() as? Response {
            return empty
        }
        do {
            return try Self.decoder.decode(Response.self, from: data)
        } catch {
            throw FitFightAPIError.decoding(error)
        }
    }

    private func endpoint(_ path: String) -> URL? {
        guard let baseURL else { return nil }
        var root = baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if !root.lowercased().contains("/api/v1") {
            root += "/api/v1"
        }
        return URL(string: root + "/" + path)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct EmptyJSON: Codable {}

private struct HandleBody: Encodable {
    var handle: String
}

private struct AcceptBody: Encodable {
    var personalTarget: Double?
}

private struct StartBody: Encodable {
    var when: String
}

private struct DiscardBody: Decodable {
    init() {}
}

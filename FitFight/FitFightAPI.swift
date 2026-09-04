import Foundation

enum FitFightAPIError: LocalizedError {
    case notConfigured
    case http(status: Int, code: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(localized: "FitFight API is not configured. Set FFAPIBaseURL.")
        case .http(let status, let code):
            switch code {
            case "handle_not_found":
                return String(localized: "That username does not have a FitFight account yet.")
            case "already_member":
                return String(localized: "That person is already in this fight.")
            case "fight_not_joinable":
                return String(localized: "This fight is invite-only.")
            case "fight_full":
                return String(localized: "This fight is full.")
            case "join_rate_limited":
                return String(localized: "Too many join attempts. Try again later.")
            case "unauthorized":
                return String(localized: "Your session expired. Sign in again.")
            case "fight_not_startable", "fight_not_cancellable", "conflict":
                return String(localized: "This fight changed. Refresh and try again.")
            default:
                return String(
                    localized: "api.request-failed",
                    defaultValue: "Request failed (\(status))."
                )
            }
        case .decoding:
            return String(localized: "Couldn’t read the server response.")
        }
    }
}

struct FitFightDataSource: Codable, Equatable {
    var id: UUID
    var provider: String
    var sourceLabel: String
    var contributingSourceLabels: [String]?
}

struct FitFightHealthKitContext: Decodable, Equatable {
    struct FightWindow: Decodable, Equatable {
        var fightId: UUID
        var state: String
        var startsAt: Date
        var endsAt: Date
        var cutoffAt: Date

        enum CodingKeys: String, CodingKey {
            case fightId = "fight_id"
            case state
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case cutoffAt = "cutoff_at"
        }
    }

    var serverNow: Date
    var fightWindows: [FightWindow]

    enum CodingKeys: String, CodingKey {
        case serverNow = "server_now"
        case fightWindows = "fight_windows"
    }
}

struct FitFightHealthKitStepSync: Encodable, Equatable {
    struct MergedDay: Encodable, Equatable {
        var day: String
        var startsAt: String
        var endsAt: String
        var steps: Int

        enum CodingKeys: String, CodingKey {
            case day
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case steps
        }
    }

    struct FightAggregate: Encodable, Equatable {
        var fightId: String
        var startsAt: String
        var endsAt: String
        var cutoffAt: String
        var steps: Int

        enum CodingKeys: String, CodingKey {
            case fightId = "fight_id"
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case cutoffAt = "cutoff_at"
            case steps
        }
    }

    var completeThrough: String
    var timeZone: String
    var mergedDays: [MergedDay]
    var fightAggregates: [FightAggregate]

    enum CodingKeys: String, CodingKey {
        case completeThrough = "complete_through"
        case timeZone = "time_zone"
        case mergedDays = "merged_days"
        case fightAggregates = "fight_aggregates"
    }
}

struct FitFightHealthKitStepSyncResult: Decodable, Equatable {
    var completeThrough: Date
    var syncedDays: Int
    var syncedFights: Int

    enum CodingKeys: String, CodingKey {
        case completeThrough = "complete_through"
        case syncedDays = "synced_days"
        case syncedFights = "synced_fights"
    }
}

struct FitFightHealthKitDiagnosticSnapshot: Encodable {
    var backgroundRefreshStatus: String
    var deliveryRegistrationStatus: String
    var lastObserverWake: Date?
    var lastSyncAttempt: Date?
    var lastAutomaticSync: Date?
    var lastManualSync: Date?
    var lastTriggerContext: String?
    var errorCode: String?
    var appVersion: String
    var appBuild: String

    init(_ diagnostics: HealthKitStepsStore.Diagnostics) {
        backgroundRefreshStatus = diagnostics.backgroundRefreshStatus.rawValue
        deliveryRegistrationStatus = diagnostics.deliveryRegistrationStatus.rawValue
        lastObserverWake = diagnostics.lastObserverWake
        lastSyncAttempt = diagnostics.lastSyncAttempt
        lastAutomaticSync = diagnostics.lastAutomaticSync
        lastManualSync = diagnostics.lastManualSync
        lastTriggerContext = diagnostics.lastTrigger?.rawValue
        errorCode = diagnostics.errorCode?.rawValue
        appVersion = AppVersion.marketing
        appBuild = AppVersion.build
    }

    enum CodingKeys: String, CodingKey {
        case backgroundRefreshStatus = "background_refresh_status"
        case deliveryRegistrationStatus = "delivery_registration_status"
        case lastObserverWake = "last_observer_wake"
        case lastSyncAttempt = "last_sync_attempt"
        case lastAutomaticSync = "last_automatic_sync"
        case lastManualSync = "last_manual_sync"
        case lastTriggerContext = "last_trigger_context"
        case errorCode = "error_code"
        case appVersion = "app_version"
        case appBuild = "app_build"
    }
}

struct FitFightHealthKitDiagnosticSnapshotResult: Decodable {
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case updatedAt = "updated_at"
    }
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
    var visibility: String?
    var recurring: Bool?
}

struct FitFightJoinableFight: Decodable, Equatable, Identifiable {
    var fightId: UUID
    var seriesId: UUID
    var name: String
    var joinCode: String
    var ownerHandle: String
    var actionText: String?
    var startsAt: String
    var endsAt: String
    var memberCount: Int
    var recurring: Bool
    var alreadyMember: Bool

    var id: UUID { fightId }
}

private struct FitFightJoinableList: Decodable {
    var fights: [FitFightJoinableFight]
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

struct FitFightAccountDeletion: Decodable, Equatable {
    var appleAuthorizationRevoked: Bool
    var deleted: Bool

    enum CodingKeys: String, CodingKey {
        case appleAuthorizationRevoked = "apple_authorization_revoked"
        case deleted
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appleAuthorizationRevoked = try container.decodeIfPresent(
            Bool.self,
            forKey: .appleAuthorizationRevoked
        ) ?? false
        deleted = try container.decode(Bool.self, forKey: .deleted)
    }
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

    func healthKitUploadContext(accessToken: String) async throws -> FitFightHealthKitContext {
        try await get(
            path: "provider-uploads/context?provider=apple_health&metric=steps",
            accessToken: accessToken,
            expected: [200]
        )
    }

    func syncHealthKitSteps(
        _ sync: FitFightHealthKitStepSync,
        accessToken: String
    ) async throws -> FitFightHealthKitStepSyncResult {
        try await post(
            path: "healthkit/steps",
            accessToken: accessToken,
            body: sync,
            expected: [200]
        )
    }

    func saveHealthKitDiagnostics(
        _ diagnostics: HealthKitStepsStore.Diagnostics,
        accessToken: String
    ) async throws -> FitFightHealthKitDiagnosticSnapshotResult {
        try await post(
            path: "healthkit/diagnostics",
            accessToken: accessToken,
            body: FitFightHealthKitDiagnosticSnapshot(diagnostics),
            expected: [200]
        )
    }

    func storeAppleAuthorizationCode(
        _ authorizationCode: String,
        accessToken: String
    ) async throws {
        let _: DiscardBody = try await post(
            path: "auth/apple",
            accessToken: accessToken,
            body: AppleAuthorizationBody(authorizationCode: authorizationCode),
            expected: [200]
        )
    }

    func deleteAccount(accessToken: String) async throws -> FitFightAccountDeletion {
        try await delete(
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

    func listJoinableFights(accessToken: String) async throws -> [FitFightJoinableFight] {
        let list: FitFightJoinableList = try await get(
            path: "fights/joinable",
            accessToken: accessToken,
            expected: [200]
        )
        return list.fights
    }

    func joinableFight(code: String, accessToken: String) async throws -> FitFightJoinableFight {
        try await get(
            path: "fights/joinable/\(code)",
            accessToken: accessToken,
            expected: [200]
        )
    }

    func joinFight(
        code: String? = nil,
        fightID: UUID? = nil,
        accessToken: String
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/join",
            accessToken: accessToken,
            body: JoinFightBody(code: code, fightId: fightID),
            expected: [200]
        )
    }

    func leaveFight(fightID: UUID, accessToken: String) async throws -> FitFightSummary {
        try await post(
            path: "fights/leave",
            accessToken: accessToken,
            body: LeaveFightBody(fightId: fightID),
            expected: [200]
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

    private func get<Response: Decodable>(
        path: String,
        accessToken: String,
        expected: Set<Int>
    ) async throws -> Response {
        try await request(
            path: path,
            method: "GET",
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
            let code = (try? Self.decoder.decode(APIErrorResponse.self, from: data))?.code
            throw FitFightAPIError.http(status: status, code: code)
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

private struct APIErrorResponse: Decodable {
    var code: String
}

private struct JoinFightBody: Encodable {
    var code: String?
    var fightId: UUID?
}

private struct LeaveFightBody: Encodable {
    var fightId: UUID
}

private struct HandleBody: Encodable {
    var handle: String
}

private struct AcceptBody: Encodable {
    var personalTarget: Double?
}

private struct StartBody: Encodable {
    var when: String
}

private struct AppleAuthorizationBody: Encodable {
    var authorizationCode: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
    }
}

private struct DiscardBody: Decodable {
    init() {}
}

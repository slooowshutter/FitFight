import Foundation

enum FitFightAPIError: LocalizedError {
    case notConfigured
    case http(status: Int, code: String?, message: String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return String(appLocalized: "FitFight API is not configured. Set FFAPIBaseURL.")
        case .http(let status, let code, let message):
            switch code {
            case "update_required":
                return String(appLocalized: "Update FitFight to continue")
            case "release_unavailable":
                return String(appLocalized: "Couldn’t check for updates")
            case "handle_not_found":
                return String(appLocalized: "That username does not have a FitFight account yet.")
            case "companion_taken":
                return String(appLocalized: "That special was just claimed. Choose another companion.")
            case "special_purchase_required":
                return String(appLocalized: "Purchase this Special before using it.")
            case "special_limit":
                return String(appLocalized: "You already own a Special or have a purchase in progress.")
            case "special_unavailable":
                return String(appLocalized: "Special purchases are not available yet.")
            case "special_account":
                return String(appLocalized: "This purchase belongs to another FitFight account. Sign in to that account or contact support.")
            case "already_member":
                return String(appLocalized: "That person is already in this fight.")
            case "fight_not_joinable":
                return String(appLocalized: "This fight cannot be joined.")
            case "fight_full":
                return String(appLocalized: "This fight is full.")
            case "join_rate_limited":
                return String(appLocalized: "Too many join attempts. Try again later.")
            case "unauthorized":
                return String(appLocalized: "Your session expired. Sign in again.")
            case "forbidden":
                return message ?? String(appLocalized: "This is only available to the FitFight admin.")
            case "config":
                return message ?? String(appLocalized: "Cursor isn’t configured yet.")
            case "fight_not_startable", "fight_not_cancellable", "conflict":
                return String(appLocalized: "This fight changed. Refresh and try again.")
            case "validation":
                return message ?? String(appLocalized: "Check the title and details, then try again.")
            case "rate_limited":
                return message ?? String(appLocalized: "You’ve posted a few times recently. Try again later.")
            case "not_found":
                return message ?? String(appLocalized: "That isn’t available anymore.")
            default:
                return message ?? String(
                    appLocalized: "api.request-failed",
                    defaultValue: "Request failed (\(status))."
                )
            }
        case .decoding:
            return String(appLocalized: "Couldn’t read the server response.")
        }
    }
}

struct FitFightHealthKitContext: Decodable, Equatable {
    struct FightWindow: Decodable, Equatable {
        var fightId: UUID
        var state: String
        var startsAt: Date
        var endsAt: Date
        var cutoffAt: Date
        var timeZone: String? = nil

        enum CodingKeys: String, CodingKey {
            case fightId = "fight_id"
            case state
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case cutoffAt = "cutoff_at"
            case timeZone = "time_zone"
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
        var stepCheckpoints: [FightStepCheckpoint]? = nil

        enum CodingKeys: String, CodingKey {
            case fightId = "fight_id"
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case cutoffAt = "cutoff_at"
            case steps
            case stepCheckpoints = "step_checkpoints"
        }
    }

    struct ActivityDay: Encodable, Equatable {
        var day: String
        var startsAt: String
        var endsAt: String
        var metric: String
        var value: Double
        var unit: String

        enum CodingKeys: String, CodingKey {
            case day
            case startsAt = "starts_at"
            case endsAt = "ends_at"
            case metric
            case value
            case unit
        }
    }

    struct Workout: Encodable, Equatable {
        var healthkitUuid: String
        var startedAt: String
        var endedAt: String
        var activityType: String
        var durationSeconds: Double
        var activeMinutes: Double?
        var distanceM: Double?
        var energyKcal: Double?
        var effort: Double?

        enum CodingKeys: String, CodingKey {
            case healthkitUuid = "healthkit_uuid"
            case startedAt = "started_at"
            case endedAt = "ended_at"
            case activityType = "activity_type"
            case durationSeconds = "duration_seconds"
            case activeMinutes = "active_minutes"
            case distanceM = "distance_m"
            case energyKcal = "energy_kcal"
            case effort
        }
    }

    var completeThrough: String
    var timeZone: String
    var mergedDays: [MergedDay]
    var fightAggregates: [FightAggregate]
    var activityDays: [ActivityDay]? = nil
    var workouts: [Workout]? = nil

    enum CodingKeys: String, CodingKey {
        case completeThrough = "complete_through"
        case timeZone = "time_zone"
        case mergedDays = "merged_days"
        case fightAggregates = "fight_aggregates"
        case activityDays = "activity_days"
        case workouts
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

struct FitFightHealthKitActivityBatch: Encodable {
    var collectedAt: String
    var timeZone: String
    var totals: [FitFightHealthKitStepSync.ActivityDay]
    var workouts: [FitFightHealthKitStepSync.Workout]
    var deletedWorkouts: [String]

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case timeZone = "time_zone"
        case totals, workouts
        case deletedWorkouts = "deleted_workouts"
    }
}

struct FitFightHealthKitActivityResult: Decodable {
    var received: Int
    var processing: String
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
    var attempts: [HealthKitSyncTrace.Attempt]

    init(_ diagnostics: HealthKitStepsStore.Diagnostics, attempts: [HealthKitSyncTrace.Attempt]) {
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
        self.attempts = attempts
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
        case attempts
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

struct FitFightUpdateFight: Encodable, Equatable {
    var name: String?
    var actionText: String?
    var visibility: String?
    var recurring: Bool?
    var startsAt: Date?
    var endsAt: Date?
    var timeZone: String? = nil
    var inviteHandles: [String]?
    var removeUserIds: [UUID]?
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
    var canJoinNext: Bool?
    var membershipState: String?

    var id: UUID { fightId }
    var hasJoined: Bool { membershipState == "accepted" || membershipState == "deferred" }
}

private struct FitFightJoinableList: Decodable {
    var fights: [FitFightJoinableFight]
}

struct FitFightSuggested: Decodable {
    var suggested: Bool
}

private struct FitFightSuggestBody: Encodable {
    var suggested: Bool
}

struct FitFightSummary: Codable, Equatable {
    var id: UUID
    var state: String
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

struct FitFightFeedbackPost: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var kind: String
    var title: String
    var body: String
    var voteCount: Int
    var commentCount: Int
    var voted: Bool
    var authorId: UUID
    var authorHandle: String
    var mine: Bool
    var createdAt: Date
    var metadata: FitFightFeedbackMetadata
    var media: [FitFightMedia]
    var archived: Bool
    var archiveReason: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case body
        case voteCount = "vote_count"
        case commentCount = "comment_count"
        case voted
        case authorId = "author_id"
        case authorHandle = "author_handle"
        case mine
        case createdAt = "created_at"
        case metadata
        case media
        case archived
        case archiveReason = "archive_reason"
    }

    init(
        id: UUID,
        kind: String,
        title: String,
        body: String,
        voteCount: Int,
        commentCount: Int,
        voted: Bool,
        authorId: UUID,
        authorHandle: String,
        mine: Bool,
        createdAt: Date,
        metadata: FitFightFeedbackMetadata = FitFightFeedbackMetadata(),
        media: [FitFightMedia] = [],
        archived: Bool = false,
        archiveReason: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.voteCount = voteCount
        self.commentCount = commentCount
        self.voted = voted
        self.authorId = authorId
        self.authorHandle = authorHandle
        self.mine = mine
        self.createdAt = createdAt
        self.metadata = metadata
        self.media = media
        self.archived = archived
        self.archiveReason = archiveReason
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        voteCount = try container.decode(Int.self, forKey: .voteCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        voted = try container.decode(Bool.self, forKey: .voted)
        authorId = try container.decode(UUID.self, forKey: .authorId)
        authorHandle = try container.decode(String.self, forKey: .authorHandle)
        mine = try container.decode(Bool.self, forKey: .mine)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(FitFightFeedbackMetadata.self, forKey: .metadata)
            ?? FitFightFeedbackMetadata()
        media = try container.decodeIfPresent([FitFightMedia].self, forKey: .media) ?? []
        archived = try container.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        archiveReason = try container.decodeIfPresent(String.self, forKey: .archiveReason)
    }
}

struct FitFightFeedbackComment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var body: String
    var authorId: UUID?
    var authorHandle: String
    var createdAt: Date
    var metadata: FitFightFeedbackMetadata

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case authorId = "author_id"
        case authorHandle = "author_handle"
        case createdAt = "created_at"
        case metadata
    }

    init(
        id: UUID,
        body: String,
        authorHandle: String,
        createdAt: Date,
        metadata: FitFightFeedbackMetadata = FitFightFeedbackMetadata(),
        authorId: UUID? = nil
    ) {
        self.id = id
        self.body = body
        self.authorId = authorId
        self.authorHandle = authorHandle
        self.createdAt = createdAt
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        authorId = try container.decodeIfPresent(UUID.self, forKey: .authorId)
        authorHandle = try container.decode(String.self, forKey: .authorHandle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(FitFightFeedbackMetadata.self, forKey: .metadata)
            ?? FitFightFeedbackMetadata()
    }
}

struct FitFightFeedbackList: Decodable, Equatable {
    var posts: [FitFightFeedbackPost]
    var canArchive: Bool

    enum CodingKeys: String, CodingKey {
        case posts
        case canArchive = "can_archive"
    }

    init(posts: [FitFightFeedbackPost], canArchive: Bool = false) {
        self.posts = posts
        self.canArchive = canArchive
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        posts = try container.decode([FitFightFeedbackPost].self, forKey: .posts)
        canArchive = try container.decodeIfPresent(Bool.self, forKey: .canArchive) ?? false
    }
}

struct FitFightFeedbackDetail: Decodable, Equatable {
    var post: FitFightFeedbackPost
    var comments: [FitFightFeedbackComment]
    var canLaunchFix: Bool
    var canDelete: Bool
    var canArchive = false

    enum CodingKeys: String, CodingKey {
        case post
        case comments
        case canLaunchFix = "can_launch_fix"
        case canDelete = "can_delete"
        case canArchive = "can_archive"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        post = try container.decode(FitFightFeedbackPost.self, forKey: .post)
        comments = try container.decode([FitFightFeedbackComment].self, forKey: .comments)
        canLaunchFix = try container.decodeIfPresent(Bool.self, forKey: .canLaunchFix) ?? false
        canDelete = try container.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
        canArchive = try container.decodeIfPresent(Bool.self, forKey: .canArchive) ?? false
    }
}

struct FitFightFeedbackArchive: Decodable, Equatable {
    var archived: Bool
    var archiveReason: String?

    enum CodingKeys: String, CodingKey {
        case archived
        case archiveReason = "archive_reason"
    }
}

struct FitFightFeedbackFixAgent: Decodable, Equatable {
    var agentId: String
    var agentURL: URL

    enum CodingKeys: String, CodingKey {
        case agentId = "agent_id"
        case agentURL = "agent_url"
    }
}

struct FitFightFeedbackPostResponse: Decodable, Equatable {
    var post: FitFightFeedbackPost
}

struct FitFightFeedbackCommentResponse: Decodable, Equatable {
    var comment: FitFightFeedbackComment
}

struct FitFightFeedbackVote: Decodable, Equatable {
    var voted: Bool
    var voteCount: Int

    enum CodingKeys: String, CodingKey {
        case voted
        case voteCount = "vote_count"
    }
}

struct FitFightCreateFeedback: Encodable, Equatable {
    var kind: String
    var title: String
    var body: String
    var mediaIds: [UUID] = []
    var metadata: FitFightFeedbackMetadata

    enum CodingKeys: String, CodingKey {
        case kind, title, body, metadata
        case mediaIds = "media_ids"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(body, forKey: .body)
        try container.encode(metadata, forKey: .metadata)
        if !mediaIds.isEmpty {
            try container.encode(mediaIds, forKey: .mediaIds)
        }
    }
}

struct FitFightReferralLink: Encodable {
    let code: UUID
}

struct FitFightReferralClaim: Decodable {
    let recorded: Bool
}

struct FitFightDailyStatusRecap: Decodable {
    let recap: String
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case recap
        case sentAt = "sent_at"
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
        if !raw.isEmpty { return URL(string: raw) }
        #if DEBUG
        return URL(string: "https://staging.fitfight.app")
        #else
        return nil
        #endif
    }

    func claimReferral(code: UUID, accessToken: String) async throws -> FitFightReferralClaim {
        try await post(
            path: "referrals",
            accessToken: accessToken,
            body: FitFightReferralLink(code: code)
        )
    }

    func healthKitUploadContext(
        accessToken: String,
        trace: HealthKitSyncTrace
    ) async throws -> FitFightHealthKitContext {
        try await get(
            path: "provider-uploads/context?provider=apple_health&metric=steps",
            accessToken: accessToken,
            trace: trace,
            traceStage: .context
        )
    }

    func syncHealthKitSteps(
        _ sync: FitFightHealthKitStepSync,
        accessToken: String,
        trace: HealthKitSyncTrace
    ) async throws -> FitFightHealthKitStepSyncResult {
        let body = try Self.encoder.encode(sync)
        trace.recordUpload(fights: sync.fightAggregates.count, days: sync.mergedDays.count, bytes: body.count)
        return try await request(
            path: "healthkit/steps",
            method: "POST",
            accessToken: accessToken,
            body: body,
            trace: trace,
            traceStage: .upload
        )
    }

    func syncHealthKitActivity(
        _ batch: FitFightHealthKitActivityBatch,
        accessToken: String,
        trace: HealthKitSyncTrace
    ) async throws -> FitFightHealthKitActivityResult {
        try await request(
            path: "healthkit/activity",
            method: "POST",
            accessToken: accessToken,
            body: Self.encoder.encode(batch),
            trace: trace,
            traceStage: .activityUpload
        )
    }

    func saveHealthKitDiagnostics(
        _ diagnostics: FitFightHealthKitDiagnosticSnapshot,
        accessToken: String
    ) async throws -> FitFightHealthKitDiagnosticSnapshotResult {
        try await post(
            path: "healthkit/diagnostics",
            accessToken: accessToken,
            body: diagnostics
        )
    }

    func fightsSnapshot(
        accessToken: String, trace: HealthKitSyncTrace, performMaintenance: Bool = true
    ) async throws -> FitFightSnapshot {
        try await request(
            path: performMaintenance ? "fights/refresh" : "fights/snapshot",
            method: "POST",
            accessToken: accessToken,
            body: Self.encoder.encode(["time_zone": Calendar.current.timeZone.identifier]),
            trace: trace,
            traceStage: .fightsRefresh
        )
    }

    func dailyStatusRecap(fightID: UUID, accessToken: String) async throws -> FitFightDailyStatusRecap {
        try await get(
            path: "fights/\(fightID.uuidString.lowercased())/daily-status",
            accessToken: accessToken
        )
    }

    func reconcileGoogleIdentity(
        idToken: String,
        accessToken: String,
        nonce: String
    ) async throws {
        let _: DiscardBody = try await post(
            path: "auth/google",
            accessToken: "",
            body: GoogleIdentityBody(
                idToken: idToken,
                accessToken: accessToken,
                nonce: nonce
            )
        )
    }

    /// Reuse this key for the same user action. Poll the returned request instead of starting again.
    func startAvatarGeneration(
        description: String,
        idempotencyKey: UUID,
        accessToken: String
    ) async throws -> FitFightAIRequest {
        let response: FitFightAIRequest = try await post(
            path: "ai/runs",
            accessToken: accessToken,
            body: FitFightAvatarRequest(parameters: .init(description: description)),
            idempotencyKey: idempotencyKey.uuidString.lowercased(),
            expected: [200, 202]
        )
        if let failure = response.failure { throw failure }
        return response
    }

    func startFitnessGeneration(
        avatarRequestID: UUID,
        identityDetails: String,
        idempotencyKey: UUID,
        accessToken: String
    ) async throws -> FitFightAIRequest {
        let response: FitFightAIRequest = try await post(
            path: "ai/runs",
            accessToken: accessToken,
            body: FitFightFitnessRequest(parameters: .init(avatarRequestID: avatarRequestID, identityDetails: identityDetails)),
            idempotencyKey: idempotencyKey.uuidString.lowercased(),
            expected: [200, 202]
        )
        if let failure = response.failure { throw failure }
        return response
    }

    func startGroupPhotoGeneration(
        characters: [FitFightAICharacter],
        scene: String,
        idempotencyKey: UUID,
        accessToken: String
    ) async throws -> FitFightAIRequest {
        let response: FitFightAIRequest = try await post(
            path: "ai/runs",
            accessToken: accessToken,
            body: FitFightGroupPhotoRequest(parameters: .init(characters: characters, scene: scene)),
            idempotencyKey: idempotencyKey.uuidString.lowercased(),
            expected: [200, 202]
        )
        if let failure = response.failure { throw failure }
        return response
    }

    func aiAllowance(accessToken: String) async throws -> FitFightAIAllowance {
        try await get(path: "ai/allowance", accessToken: accessToken, expected: [200])
    }

    func aiLibrary(accessToken: String) async throws -> [FitFightAILibraryEntry] {
        try await get(path: "ai/library", accessToken: accessToken, expected: [200])
    }

    func aiRequest(requestID: UUID, accessToken: String) async throws -> FitFightAIRequest {
        let response: FitFightAIRequest = try await get(
            path: "ai/runs/\(requestID.uuidString.lowercased())",
            accessToken: accessToken,
            expected: [200]
        )
        if let failure = response.failure { throw failure }
        return response
    }

    func storeAppleAuthorizationCode(
        _ authorizationCode: String,
        accessToken: String
    ) async throws {
        let _: DiscardBody = try await post(
            path: "auth/apple",
            accessToken: accessToken,
            body: AppleAuthorizationBody(authorizationCode: authorizationCode)
        )
    }

    func sharedProfile(userID: UUID, preview: String? = nil, accessToken: String) async throws -> SharedProfile {
        let suffix = preview.map { "?preview=\($0)" } ?? ""
        return try await get(path: "profiles/\(userID.uuidString.lowercased())\(suffix)", accessToken: accessToken)
    }

    func ownRivalries(accessToken: String) async throws -> [ProfileRivalrySummary] {
        try await get(path: "me/rivalries", accessToken: accessToken)
    }

    func profileSettings(accessToken: String) async throws -> SharedProfileSettings {
        try await get(path: "me/profile-settings", accessToken: accessToken)
    }

    func updateProfileSettings(_ settings: SharedProfileSettings, accessToken: String) async throws -> SharedProfileSettings {
        try await request(
            path: "me/profile-settings", method: "PATCH", accessToken: accessToken,
            body: Self.encoder.encode(ProfileSettingsUpdate(settings: settings))
        )
    }

    func profileHistory(userID: UUID, shared: Bool, cursor: UUID? = nil, accessToken: String) async throws -> ProfileHistoryPage {
        let suffix = cursor.map { "&cursor=\($0.uuidString.lowercased())" } ?? ""
        return try await get(path: "profiles/\(userID.uuidString.lowercased())/history?shared=\(shared)\(suffix)", accessToken: accessToken)
    }

    func profileFriends(kind: String, cursor: UUID? = nil, accessToken: String) async throws -> ProfileFriendsPage {
        let suffix = cursor.map { "&cursor=\($0.uuidString.lowercased())" } ?? ""
        return try await get(path: "friends?kind=\(kind)\(suffix)", accessToken: accessToken)
    }

    func lookupProfile(handle: String, accessToken: String) async throws -> SharedProfileIdentity {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "handle", value: handle)]
        return try await get(path: "profiles/lookup?\(query.percentEncodedQuery ?? "")", accessToken: accessToken)
    }

    func changeFriendship(userID: UUID, action: String, accessToken: String) async throws -> ProfileFriendshipResponse {
        let path = "friends/\(userID.uuidString.lowercased())"
        if action == "remove" {
            return try await delete(path: path, accessToken: accessToken)
        }
        if action == "request" {
            return try await post(path: path + "/request", accessToken: accessToken, body: EmptyJSON())
        }
        return try await post(path: path + "/respond", accessToken: accessToken, body: ["action": action])
    }

    func blockProfile(userID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(path: "profiles/\(userID.uuidString.lowercased())/block", accessToken: accessToken, body: EmptyJSON())
    }

    func reportProfile(userID: UUID, reason: String, accessToken: String) async throws {
        let _: DiscardBody = try await post(path: "profiles/\(userID.uuidString.lowercased())/report", accessToken: accessToken, body: ["reason": reason])
    }

    func recordProfileView(userID: UUID, eventID: UUID, source: String, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "profiles/\(userID.uuidString.lowercased())/views", accessToken: accessToken,
            body: ["event_id": eventID.uuidString.lowercased(), "source": source]
        )
    }

    func profile(accessToken: String) async throws -> FitFightProfile {
        try await get(path: "me", accessToken: accessToken)
    }

    func companionPrompts(accessToken: String) async throws -> [String] {
        try await get(path: "me/companions", accessToken: accessToken)
    }

    func specials(accessToken: String) async throws -> SpecialStoreSnapshot {
        try await get(path: "me/specials", accessToken: accessToken, expected: [200])
    }

    func specialCheckout(action: String, companionId: String, attemptId: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(path: "me/specials/checkout", accessToken: accessToken,
            body: ["action": action, "companion_id": companionId, "attempt_id": attemptId.uuidString.lowercased()], expected: [200])
    }

    func claimSpecial(companionId: String, signedTransaction: String, accessToken: String) async throws -> SpecialClaimResult {
        try await post(path: "me/specials/transactions", accessToken: accessToken,
            body: ["companion_id": companionId, "signed_transaction": signedTransaction], expected: [200])
    }

    func customCharacters(accessToken: String) async throws -> CustomCharacterStoreSnapshot {
        try await get(path: "me/custom-characters", accessToken: accessToken, expected: [200])
    }

    func claimCustomCharacter(signedTransaction: String, accessToken: String) async throws -> CustomCharacterClaim {
        try await post(path: "me/custom-characters/purchases", accessToken: accessToken,
                       body: ["signed_transaction": signedTransaction], expected: [200])
    }

    func advanceCustomCharacter(id: UUID, description: String?, retry: Bool, accessToken: String) async throws -> CustomCharacterProgress {
        try await post(path: "me/custom-characters/\(id.uuidString.lowercased())/advance", accessToken: accessToken,
                       body: CustomCharacterAdvanceBody(description: description, retry: retry ? true : nil), expected: [200, 202])
    }

    func updateProfile(
        handle: String? = nil,
        displayName: String? = nil,
        avatarMediaId: UUID? = nil,
        companionId: String? = nil,
        companionPrompt: String? = nil,
        companionImage: FitFightAICompanionSelection? = nil,
        timeZone: String? = nil,
        accessToken: String
    ) async throws -> FitFightProfile {
        try await request(
            path: "me",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(ProfileUpdate(
                handle: handle,
                displayName: displayName,
                avatarMediaId: avatarMediaId,
                companionId: companionId,
                companionPrompt: companionPrompt,
                companionImage: companionImage,
                timeZone: timeZone
            ))
        )
    }

    func createMediaUpload(
        purpose: String,
        kind: String = "photo",
        filename: String,
        contentType: String,
        byteSize: Int,
        width: Int,
        height: Int,
        durationMs: Int? = nil,
        sha256: String,
        accessToken: String
    ) async throws -> FitFightMediaUpload {
        try await post(
            path: "media",
            accessToken: accessToken,
            body: MediaUploadBody(
                purpose: purpose,
                kind: kind,
                originalFilename: filename,
                contentType: contentType,
                byteSize: byteSize,
                width: width,
                height: height,
                durationMs: durationMs,
                sha256: sha256
            ),
            expected: [201]
        )
    }

    func commitMedia(id: UUID, accessToken: String) async throws -> FitFightMediaResponse {
        try await post(
            path: "media/\(id.uuidString.lowercased())/commit",
            accessToken: accessToken,
            body: EmptyJSON()
        )
    }

    func feed(scope: String? = nil, cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        var parts: [String] = ["limit=10"]
        if let scope, let encoded = scope.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("scope=\(encoded)")
        }
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("cursor=\(encoded)")
        }
        let path = "feed?\(parts.joined(separator: "&"))"
        return try await get(path: path, accessToken: accessToken, expected: [200])
    }

    func feedActivity(cursor: String?, accessToken: String) async throws -> FeedActivityList {
        var path = "feed/activity"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?cursor=\(encoded)"
        }
        return try await get(path: path, accessToken: accessToken)
    }

    func feedPeople(
        main: Bool,
        fightIDs: [UUID],
        accessToken: String
    ) async throws -> [FitFightFightPost.Author] {
        var parts: [String] = []
        if main {
            parts.append("main=true")
        }
        if !fightIDs.isEmpty {
            let ids = fightIDs.map { $0.uuidString.lowercased() }.joined(separator: ",")
            parts.append("fight_ids=\(ids)")
        }
        let path = parts.isEmpty ? "feed/people" : "feed/people?\(parts.joined(separator: "&"))"
        let response: FitFightFeedPeopleResponse = try await get(
            path: path,
            accessToken: accessToken
        )
        return response.people
    }

    func createFeedPosts(
        body: String,
        mediaIDs: [UUID],
        destinations: [FeedPostDestination],
        taggedUserIDs: [UUID],
        accessToken: String
    ) async throws -> FitFightFightPostBatch {
        try await post(
            path: "feed/posts",
            accessToken: accessToken,
            body: FeedPostsBody(
                body: body,
                mediaIds: mediaIDs,
                destinations: destinations,
                taggedUserIds: taggedUserIDs
            ),
            expected: [201]
        )
    }


    func fightPost(postID: UUID, accessToken: String) async throws -> FitFightFightPostResponse {
        try await get(path: "posts/\(postID.uuidString.lowercased())", accessToken: accessToken)
    }

    func fightPostComments(
        postID: UUID,
        cursor: String?,
        accessToken: String,
        sort: FightPostCommentSort = .comments
    ) async throws -> FitFightFightPostCommentList {
        var parts = ["sort=\(sort.rawValue)"]
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            parts.append("cursor=\(encoded)")
        }
        return try await get(
            path: "posts/\(postID.uuidString.lowercased())/comments?\(parts.joined(separator: "&"))",
            accessToken: accessToken
        )
    }

    func createFightPostComment(
        postID: UUID,
        body: String,
        parentID: UUID?,
        accessToken: String
    ) async throws -> FitFightFightPostCommentResponse {
        try await post(
            path: "posts/\(postID.uuidString.lowercased())/comments",
            accessToken: accessToken,
            body: FightPostCommentBody(body: body, parentId: parentID),
            expected: [201]
        )
    }

    func deleteFightPostComment(postID: UUID, commentID: UUID, accessToken: String) async throws -> FitFightFightPostCommentDeletion {
        try await delete(
            path: "posts/\(postID.uuidString.lowercased())/comments/\(commentID.uuidString.lowercased())",
            accessToken: accessToken
        )
    }

    func setFightPostCommentLike(postID: UUID, commentID: UUID, liked: Bool, accessToken: String) async throws -> FitFightFightPostCommentLike {
        try await request(
            path: "posts/\(postID.uuidString.lowercased())/comments/\(commentID.uuidString.lowercased())/like",
            method: "PUT",
            accessToken: accessToken,
            body: Self.encoder.encode(FightPostCommentLikeBody(liked: liked)),
            idempotencyKey: nil,
            expected: [200]
        )
    }

    func reportFightPostComment(postID: UUID, commentID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "posts/\(postID.uuidString.lowercased())/comments/\(commentID.uuidString.lowercased())/report",
            accessToken: accessToken,
            body: FightPostReportBody(reason: "other")
        )
    }

    func fightPostReactionPeople(postID: UUID, cursor: String?, accessToken: String) async throws -> FitFightFightPostReactionPeople {
        var path = "posts/\(postID.uuidString.lowercased())/reactions"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "?cursor=\(encoded)"
        }
        return try await get(path: path, accessToken: accessToken)
    }

    func reactToFightPost(postID: UUID, emoji: String, accessToken: String) async throws -> FitFightFightPostReactionList {
        try await post(
            path: "posts/\(postID.uuidString.lowercased())/reactions",
            accessToken: accessToken,
            body: FightPostReactionBody(emoji: emoji)
        )
    }

    func fightPosts(fightID: UUID, cursor: String?, accessToken: String) async throws -> FitFightFightPostList {
        var path = "fights/\(fightID.uuidString.lowercased())/posts?limit=10"
        if let cursor, let encoded = cursor.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&cursor=\(encoded)"
        }
        return try await get(path: path, accessToken: accessToken, expected: [200])
    }

    func deleteFightPost(postID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await delete(
            path: "posts/\(postID.uuidString.lowercased())",
            accessToken: accessToken
        )
    }

    func updateFightPost(postID: UUID, body: String, accessToken: String) async throws -> FitFightFightPostResponse {
        try await request(
            path: "posts/\(postID.uuidString.lowercased())",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(FightPostUpdateBody(body: body))
        )
    }

    func reportFightPost(postID: UUID, reason: String, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "posts/\(postID.uuidString.lowercased())/report",
            accessToken: accessToken,
            body: FightPostReportBody(reason: reason)
        )
    }

    func blockFeedAuthor(userID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "feed/blocks",
            accessToken: accessToken,
            body: FeedBlockBody(userId: userID)
        )
    }

    func deleteAccount(accessToken: String) async throws -> FitFightAccountDeletion {
        try await delete(
            path: "me",
            accessToken: accessToken
        )
    }

    func notificationDeliveryStatus() async throws -> FitFightNotificationDeliveryStatus {
        try await get(path: "notifications/status", accessToken: "")
    }

    func notificationPreferences(accessToken: String) async throws -> FitFightNotificationPreferences {
        try await get(path: "notifications/preferences", accessToken: accessToken)
    }

    func accountPreferences(accessToken: String) async throws -> AccountPreferences {
        try await get(path: "me/preferences", accessToken: accessToken)
    }

    func updateAccountPreferences(
        _ preferences: AccountPreferencesUpdate,
        accessToken: String
    ) async throws -> AccountPreferences {
        try await request(
            path: "me/preferences",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(preferences)
        )
    }

    func updateNotificationPreferences(
        _ prefs: FitFightNotificationPreferencesUpdate,
        accessToken: String
    ) async throws -> FitFightNotificationPreferences {
        try await request(
            path: "notifications/preferences",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(prefs)
        )
    }

    func registerDeviceInstallation(
        token: String,
        apnsEnvironment: String,
        locale: String,
        permissionStatus: String,
        accessToken: String
    ) async throws {
        let _: DiscardBody = try await post(
            path: "device-installations",
            accessToken: accessToken,
            body: FitFightDeviceInstallationBody(
                token: token,
                apnsEnvironment: apnsEnvironment,
                locale: locale,
                permissionStatus: permissionStatus
            )
        )
    }

    func revokeDeviceInstallation(token: String, accessToken: String) async throws {
        let _: DiscardBody = try await request(
            path: "device-installations",
            method: "DELETE",
            accessToken: accessToken,
            body: Self.encoder.encode(["token": token])
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

    func updateFight(
        fightID: UUID,
        payload: FitFightUpdateFight,
        accessToken: String
    ) async throws -> FitFightSummary {
        try await request(
            path: "fights/\(fightID.uuidString.lowercased())",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(payload)
        )
    }

    func listJoinableFights(accessToken: String) async throws -> [FitFightJoinableFight] {
        let list: FitFightJoinableList = try await get(
            path: "fights/joinable",
            accessToken: accessToken
        )
        return list.fights
    }

    func fightAdministrationCapabilities(accessToken: String) async throws -> FightAdministrationCapabilities {
        try await get(path: "me/capabilities", accessToken: accessToken)
    }

    func administerFight(fightID: UUID, input: AdministerFightRequest, accessToken: String) async throws -> FitFightSummary {
        try await request(path: "fights/\(fightID.uuidString.lowercased())/admin", method: "PATCH", accessToken: accessToken,
                          body: Self.encoder.encode(input))
    }

    func listSuggestedFights(accessToken: String) async throws -> [FitFightJoinableFight] {
        let list: FitFightJoinableList = try await get(
            path: "fights/suggested",
            accessToken: accessToken
        )
        return list.fights
    }

    func setFightSuggested(
        fightID: UUID,
        suggested: Bool,
        accessToken: String
    ) async throws -> FitFightSuggested {
        try await request(
            path: "fights/\(fightID.uuidString.lowercased())/suggested",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(FitFightSuggestBody(suggested: suggested))
        )
    }

    func joinableFight(code: String, accessToken: String) async throws -> FitFightJoinableFight {
        try await get(
            path: "fights/joinable/\(code)",
            accessToken: accessToken
        )
    }

    func joinFight(
        code: String? = nil,
        fightID: UUID? = nil,
        accessToken: String,
        start: String = "now"
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/join",
            accessToken: accessToken,
            body: JoinFightBody(code: code, fightId: fightID, start: start)
        )
    }

    func leaveFight(fightID: UUID, accessToken: String) async throws -> FitFightSummary {
        try await post(
            path: "fights/leave",
            accessToken: accessToken,
            body: LeaveFightBody(fightId: fightID)
        )
    }

    func acceptFight(
        fightID: UUID,
        accessToken: String,
        personalTarget: Double? = nil,
        start: String = "now"
    ) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/accept",
            accessToken: accessToken,
            body: AcceptBody(personalTarget: personalTarget, start: start)
        )
    }

    func declineFight(fightID: UUID, accessToken: String) async throws -> FitFightSummary {
        try await post(
            path: "fights/\(fightID.uuidString.lowercased())/decline",
            accessToken: accessToken,
            body: EmptyJSON()
        )
    }

    func cancel(fightID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "fights/\(fightID.uuidString.lowercased())/cancel",
            accessToken: accessToken,
            body: EmptyJSON()
        )
    }

    func listFeedback(kind: String?, status: String = "open", sort: String = "votes", accessToken: String) async throws -> FitFightFeedbackList {
        var query = URLComponents()
        query.queryItems = [URLQueryItem(name: "status", value: status), URLQueryItem(name: "sort", value: sort)]
        if let kind { query.queryItems?.append(URLQueryItem(name: "kind", value: kind)) }
        return try await get(path: "feedback?\(query.percentEncodedQuery ?? "")", accessToken: accessToken)
    }

    func archiveFeedbackPost(postID: UUID, archived: Bool, reason: String?, accessToken: String) async throws -> FitFightFeedbackArchive {
        struct ArchiveBody: Encodable {
            let archived: Bool
            let reason: String?
        }
        return try await request(
            path: "feedback/\(postID.uuidString.lowercased())",
            method: "PATCH",
            accessToken: accessToken,
            body: Self.encoder.encode(ArchiveBody(archived: archived, reason: reason))
        )
    }

    func feedbackDetail(postID: UUID, accessToken: String) async throws -> FitFightFeedbackDetail {
        try await get(
            path: "feedback/\(postID.uuidString.lowercased())",
            accessToken: accessToken
        )
    }

    func deleteFeedbackPost(postID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await delete(
            path: "feedback/\(postID.uuidString.lowercased())",
            accessToken: accessToken
        )
    }

    func createFeedback(
        _ payload: FitFightCreateFeedback,
        accessToken: String
    ) async throws -> FitFightFeedbackPostResponse {
        try await post(
            path: "feedback",
            accessToken: accessToken,
            body: payload,
            expected: [201]
        )
    }

    func toggleFeedbackVote(
        postID: UUID,
        accessToken: String
    ) async throws -> FitFightFeedbackVote {
        try await post(
            path: "feedback/\(postID.uuidString.lowercased())/vote",
            accessToken: accessToken,
            body: EmptyJSON()
        )
    }

    func createFeedbackComment(
        postID: UUID,
        body: String,
        metadata: FitFightFeedbackMetadata,
        accessToken: String
    ) async throws -> FitFightFeedbackCommentResponse {
        try await post(
            path: "feedback/\(postID.uuidString.lowercased())/comments",
            accessToken: accessToken,
            body: FeedbackCommentBody(body: body, metadata: metadata),
            expected: [201]
        )
    }

    func launchFeedbackFix(
        postID: UUID,
        metadata: FitFightFeedbackMetadata,
        accessToken: String
    ) async throws -> FitFightFeedbackFixAgent {
        try await post(
            path: "feedback/\(postID.uuidString.lowercased())/fix-agent",
            accessToken: accessToken,
            body: FeedbackFixAgentBody(metadata: metadata),
            expected: [201]
        )
    }

    func reportFeedbackPost(postID: UUID, reason: String, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "feedback/\(postID.uuidString.lowercased())/report",
            accessToken: accessToken,
            body: FightPostReportBody(reason: reason)
        )
    }

    func blockFeedbackAuthor(userID: UUID, accessToken: String) async throws {
        let _: DiscardBody = try await post(
            path: "feedback/blocks",
            accessToken: accessToken,
            body: FeedBlockBody(userId: userID)
        )
    }

    private func post<Body: Encodable, Response: Decodable>(
        path: String,
        accessToken: String,
        body: Body,
        idempotencyKey: String? = nil,
        expected: Set<Int> = [200]
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
        expected: Set<Int> = [200]
    ) async throws -> Response {
        try await request(
            path: path,
            method: "DELETE",
            accessToken: accessToken,
            body: nil,
            expected: expected
        )
    }

    private func get<Response: Decodable>(
        path: String,
        accessToken: String,
        expected: Set<Int> = [200],
        trace: HealthKitSyncTrace? = nil,
        traceStage: HealthKitSyncTrace.StageName? = nil
    ) async throws -> Response {
        try await request(
            path: path,
            method: "GET",
            accessToken: accessToken,
            body: nil,
            expected: expected,
            trace: trace,
            traceStage: traceStage
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        accessToken: String,
        body: Data?,
        idempotencyKey: String? = nil,
        expected: Set<Int> = [200],
        trace: HealthKitSyncTrace? = nil,
        traceStage: HealthKitSyncTrace.StageName? = nil
    ) async throws -> Response {
        let span = traceStage.flatMap { trace?.begin($0) }
        var succeeded = false
        var failure: Error?
        var serverTiming: [String: Double]?
        defer {
            trace?.end(span, outcome: Task.isCancelled ? .cancelled : (succeeded ? .succeeded : .failed), serverTiming: serverTiming, error: failure)
        }
        do {
            try Task.checkCancellation()
            guard await AppUpdateChecker.shared.permitsRequests() else {
                throw FitFightAPIError.http(
                    status: 426,
                    code: "update_required",
                    message: nil
                )
            }
            guard let requestURL = endpoint(path) else {
                throw FitFightAPIError.notConfigured
            }

            var request = URLRequest(url: requestURL)
            request.httpMethod = method
            if !accessToken.isEmpty {
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            }
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(AppVersion.marketing, forHTTPHeaderField: "X-FitFight-Version")
            request.setValue(AppVersion.build, forHTTPHeaderField: "X-FitFight-Build")
            if path.hasPrefix("ai/") {
                request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-FitFight-Trace-ID")
            }
            if let trace {
                request.setValue(trace.id.uuidString.lowercased(), forHTTPHeaderField: "X-FitFight-Trace-ID")
            }
            if body != nil {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            if let idempotencyKey {
                request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
            }
            request.httpBody = body

            let (data, response) = try await URLSession.shared.data(for: request)
            let http = response as? HTTPURLResponse
            if trace != nil, let header = http?.value(forHTTPHeaderField: "Server-Timing") {
                var timing: [String: Double] = [:]
                for entry in header.split(separator: ",") {
                    let parts = entry.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
                    guard let name = parts.first, ["auth", "db", "maintenance", "total"].contains(name),
                          let duration = parts.dropFirst().first(where: { $0.hasPrefix("dur=") }),
                          let value = Double(duration.dropFirst(4)), value.isFinite,
                          value >= 0, value <= 604_800_000 else { continue }
                    timing[name + "_ms"] = value
                }
                if !timing.isEmpty { serverTiming = timing }
            }
            let status = http?.statusCode ?? -1
            guard expected.contains(status) else {
                let payload = try? Self.decoder.decode(APIErrorResponse.self, from: data)
                if payload?.code == "update_required" || payload?.code == "release_unavailable" {
                    await AppUpdateChecker.shared.rejectRequest(updateRequired: payload?.code == "update_required")
                }
                if payload?.code.hasPrefix("ai_") == true,
                   let aiError = try? Self.decoder.decode(FitFightAIError.self, from: data) {
                    throw aiError
                }
                throw FitFightAPIError.http(
                    status: status,
                    code: payload?.code,
                    message: payload?.error
                )
            }
            if Response.self == DiscardBody.self {
                succeeded = true
                return DiscardBody() as! Response
            }
            do {
                let decoded = try Self.decoder.decode(Response.self, from: data)
                succeeded = true
                return decoded
            } catch {
                throw FitFightAPIError.decoding(error)
            }
        } catch {
            failure = error
            throw error
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
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO-8601 date \(raw)"
            )
        }
        return decoder
    }()
}

private struct EmptyJSON: Encodable {}

private struct ProfileUpdate: Encodable {
    let handle: String?
    let displayName: String?
    let avatarMediaId: UUID?
    let companionId: String?
    let companionPrompt: String?
    let companionImage: FitFightAICompanionSelection?
    let timeZone: String?

    enum CodingKeys: String, CodingKey {
        case handle
        case displayName = "display_name"
        case avatarMediaId = "avatar_media_id"
        case companionId = "companion_id"
        case companionPrompt = "companion_prompt"
        case companionImage = "companion_image"
        case timeZone = "time_zone"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(handle, forKey: .handle)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(avatarMediaId, forKey: .avatarMediaId)
        try container.encodeIfPresent(companionId, forKey: .companionId)
        try container.encodeIfPresent(companionImage, forKey: .companionImage)
        try container.encodeIfPresent(timeZone, forKey: .timeZone)
        if companionId != nil {
            try container.encode(companionPrompt, forKey: .companionPrompt)
        }
    }
}

private struct MediaUploadBody: Encodable {
    let purpose: String
    let kind: String
    let originalFilename: String
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
    let durationMs: Int?
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case purpose, kind, width, height, sha256
        case originalFilename = "original_filename"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case durationMs = "duration_ms"
    }
}

struct FeedPostDestination: Encodable, Hashable {
    let type: String
    let fightId: UUID?

    static var main: FeedPostDestination { FeedPostDestination(type: "main", fightId: nil) }
    static var broadcast: FeedPostDestination { FeedPostDestination(type: "broadcast", fightId: nil) }

    static func fight(_ id: UUID) -> FeedPostDestination {
        FeedPostDestination(type: "fight", fightId: id)
    }

    enum CodingKeys: String, CodingKey {
        case type
        case fightId = "fight_id"
    }
}

private struct FightPostUpdateBody: Encodable {
    let body: String
}

private struct FitFightFeedPeopleResponse: Decodable {
    let people: [FitFightFightPost.Author]
}

private struct FeedPostsBody: Encodable {
    let body: String
    let mediaIds: [UUID]
    let destinations: [FeedPostDestination]
    let taggedUserIds: [UUID]

    enum CodingKeys: String, CodingKey {
        case body
        case mediaIds = "media_ids"
        case destinations
        case taggedUserIds = "tagged_user_ids"
    }
}

private struct FightPostCommentLikeBody: Encodable {
    let liked: Bool
}

private struct FightPostCommentBody: Encodable {
    let body: String
    let parentId: UUID?

    enum CodingKeys: String, CodingKey {
        case body
        case parentId = "parent_id"
    }
}

private struct FightPostReactionBody: Encodable {
    let emoji: String
}

private struct FightPostReportBody: Encodable {
    let reason: String
}

private struct FeedBlockBody: Encodable {
    let userId: UUID

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }
}

private struct APIErrorResponse: Decodable {
    var code: String
    var error: String?
}

private struct JoinFightBody: Encodable {
    var code: String?
    var fightId: UUID?
    var start: String?
}

private struct LeaveFightBody: Encodable {
    var fightId: UUID
}

private struct AcceptBody: Encodable {
    var personalTarget: Double?
    var start: String?
}

private struct AppleAuthorizationBody: Encodable {
    var authorizationCode: String

    enum CodingKeys: String, CodingKey {
        case authorizationCode = "authorization_code"
    }
}

private struct GoogleIdentityBody: Encodable {
    var idToken: String
    var accessToken: String
    var nonce: String

    enum CodingKeys: String, CodingKey {
        case idToken = "id_token"
        case accessToken = "access_token"
        case nonce
    }
}

private struct FeedbackCommentBody: Encodable {
    var body: String
    var metadata: FitFightFeedbackMetadata
}

private struct FeedbackFixAgentBody: Encodable {
    var metadata: FitFightFeedbackMetadata
}

private struct DiscardBody: Decodable {
    init() {}
}

struct FitFightNotificationDeliveryStatus: Decodable {
    var apnsConfigured: Bool

    enum CodingKeys: String, CodingKey {
        case apnsConfigured = "apns_configured"
    }
}

struct FitFightNotificationPreferences: Codable, Equatable {
    var enabled: Bool = true
    var fightInvite: Bool = true
    var ending24h: Bool = true
    var endingWeek: Bool = false
    var fightEnded: Bool = false
    var finalSync: Bool = true
    var fightFinalized: Bool = true
    var mention: Bool = true
    var feedPost: Bool = false
    var postComment: Bool = true
    var commentReply: Bool = true
    var postReaction: Bool = true
    var challengeReminder: Bool = true
    var dailyStatus: Bool = false

    enum CodingKeys: String, CodingKey {
        case enabled = "enabled"
        case fightInvite = "fight_invite"
        case ending24h = "ending_24h"
        case endingWeek = "ending_week"
        case fightEnded = "fight_ended"
        case finalSync = "final_sync"
        case fightFinalized = "fight_finalized"
        case mention = "mention"
        case feedPost = "feed_post"
        case postComment = "post_comment"
        case commentReply = "comment_reply"
        case postReaction = "post_reaction"
        case challengeReminder = "challenge_reminder"
        case dailyStatus = "daily_status"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        feedPost = try container.decode(Bool.self, forKey: .feedPost)
        postComment = try container.decode(Bool.self, forKey: .postComment)
        commentReply = try container.decode(Bool.self, forKey: .commentReply)
        postReaction = try container.decode(Bool.self, forKey: .postReaction)
        challengeReminder = try container.decode(Bool.self, forKey: .challengeReminder)
        dailyStatus = try container.decode(Bool.self, forKey: .dailyStatus)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        fightInvite = try container.decodeIfPresent(Bool.self, forKey: .fightInvite) ?? true
        ending24h = try container.decodeIfPresent(Bool.self, forKey: .ending24h) ?? challengeReminder
        endingWeek = try container.decodeIfPresent(Bool.self, forKey: .endingWeek) ?? false
        fightEnded = try container.decodeIfPresent(Bool.self, forKey: .fightEnded) ?? false
        finalSync = try container.decodeIfPresent(Bool.self, forKey: .finalSync) ?? challengeReminder
        fightFinalized = try container.decodeIfPresent(Bool.self, forKey: .fightFinalized) ?? challengeReminder
        mention = try container.decodeIfPresent(Bool.self, forKey: .mention) ?? true
    }
}

struct FitFightNotificationPreferencesUpdate: Encodable {
    var enabled: Bool?
    var fightInvite: Bool?
    var ending24h: Bool?
    var endingWeek: Bool?
    var fightEnded: Bool?
    var finalSync: Bool?
    var fightFinalized: Bool?
    var mention: Bool?
    var feedPost: Bool?
    var postComment: Bool?
    var commentReply: Bool?
    var postReaction: Bool?
    var challengeReminder: Bool?
    var dailyStatus: Bool?

    enum CodingKeys: String, CodingKey {
        case enabled = "enabled"
        case fightInvite = "fight_invite"
        case ending24h = "ending_24h"
        case endingWeek = "ending_week"
        case fightEnded = "fight_ended"
        case finalSync = "final_sync"
        case fightFinalized = "fight_finalized"
        case mention = "mention"
        case feedPost = "feed_post"
        case postComment = "post_comment"
        case commentReply = "comment_reply"
        case postReaction = "post_reaction"
        case challengeReminder = "challenge_reminder"
        case dailyStatus = "daily_status"
    }
}

private struct FitFightDeviceInstallationBody: Encodable {
    var token: String
    var apnsEnvironment: String
    var locale: String
    var permissionStatus: String

    enum CodingKeys: String, CodingKey {
        case token
        case apnsEnvironment = "apns_environment"
        case locale
        case permissionStatus = "permission_status"
    }
}

private struct ProfileSettingsUpdate: Encodable {
    let settings: SharedProfileSettings
    enum CodingKeys: String, CodingKey {
        case competitive, audience, activityAudience = "activity_audience", activityDays = "activity_days", artworkAllowed = "artwork_allowed"
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(settings.competitive, forKey: .competitive)
        try container.encode(settings.audience, forKey: .audience)
        try container.encode(settings.activityAudience, forKey: .activityAudience)
        try container.encode(settings.activityDays, forKey: .activityDays)
        try container.encode(settings.artworkAllowed, forKey: .artworkAllowed)
    }
}

import Foundation

struct SharedProfileIdentity: Decodable, Equatable, Identifiable {
    let userId: UUID
    let handle: String
    let displayName: String
    let companionId: String?
    let avatarUrl: URL?
    var id: UUID { userId }
    var initials: String { String(displayName.prefix(2)).uppercased() }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", handle, displayName = "display_name"
        case companionId = "companion_id", avatarUrl = "avatar_url"
    }
}

struct SharedProfileSettings: Codable, Equatable {
    var competitive: Bool
    var audience: String
    var activityAudience: String
    var activityDays: Int
    var artworkAllowed: Bool
    let revision: Int

    enum CodingKeys: String, CodingKey {
        case competitive, audience, revision
        case activityAudience = "activity_audience", activityDays = "activity_days", artworkAllowed = "artwork_allowed"
    }
}

struct ProfileCounts: Decodable, Equatable {
    let played: Int
    let wins: Int
    let winRate: Double?
    enum CodingKeys: String, CodingKey { case played, wins, winRate = "win_rate" }
}

struct ProfileRecord: Decodable, Equatable {
    let played: Int
    let wins: Int
    let winRate: Double?
    let categories: [String: ProfileCounts]
    let excluded: Int
    enum CodingKeys: String, CodingKey { case played, wins, categories, excluded, winRate = "win_rate" }
}

struct ProfileRivalry: Decodable, Equatable {
    let wins: Int
    let losses: Int
    let draws: Int
    let rematch: ProfileRematch?
}

struct ProfileRematch: Decodable, Equatable {
    let durationSeconds: Int
    let actionText: String?
    enum CodingKeys: String, CodingKey { case durationSeconds = "duration_seconds", actionText = "action_text" }
}

struct ProfileActivity: Decodable, Equatable {
    let metric: String
    let days: Int
    let values: [ProfileActivityDay]
}

struct ProfileActivityDay: Decodable, Equatable, Identifiable {
    let day: String
    let steps: Double
    let timeZone: String?
    let updatedAt: String
    let finalized: Bool
    var id: String { day }
    enum CodingKeys: String, CodingKey { case day, steps, finalized, timeZone = "time_zone", updatedAt = "updated_at" }
}

struct ProfileStepStatistics: Decodable, Equatable {
    let scopeDays: Int?
    let from: String?
    let through: String
    let timeZone: String
    let recordedDays: Int
    let unknownDays: Int
    let totalSteps: Double
    let averageSteps: Double?
    let bestDay: ProfileBestStepDay?
    let week: ProfileStepWeek
    let levels: [ProfileActivityLevel]

    enum CodingKeys: String, CodingKey {
        case from, through, week, levels
        case scopeDays = "scope_days", timeZone = "time_zone", recordedDays = "recorded_days"
        case unknownDays = "unknown_days", totalSteps = "total_steps", averageSteps = "average_steps", bestDay = "best_day"
    }
}

struct ProfileBestStepDay: Decodable, Equatable {
    let day: String
    let steps: Double
}

struct ProfileStepWeek: Decodable, Equatable {
    let startsOn: String
    let elapsedDays: Int
    let recordedDays: Int
    let totalSteps: Double
    let averageSteps: Double?

    enum CodingKeys: String, CodingKey {
        case startsOn = "starts_on", elapsedDays = "elapsed_days", recordedDays = "recorded_days"
        case totalSteps = "total_steps", averageSteps = "average_steps"
    }
}

struct ProfileActivityLevel: Decodable, Equatable, Identifiable {
    let level: String
    let minimumSteps: Int
    let days: Int
    let share: Double?
    let longestStreak: Int
    let currentStreak: Int?
    var id: String { level }

    enum CodingKeys: String, CodingKey {
        case level, days, share
        case minimumSteps = "minimum_steps", longestStreak = "longest_streak", currentStreak = "current_streak"
    }
}

struct SharedProfile: Decodable, Equatable {
    let identity: SharedProfileIdentity
    let access: String
    let competitive: Bool
    let friendship: String
    let record: ProfileRecord?
    let rivalry: ProfileRivalry?
    let activity: ProfileActivity?
    let stepStatistics: ProfileStepStatistics?
    let viewMeasurementEnabled: Bool
    enum CodingKeys: String, CodingKey {
        case identity, access, competitive, friendship, record, rivalry, activity
        case viewMeasurementEnabled = "view_measurement_enabled"
        case stepStatistics = "step_statistics"
    }
}

struct ProfileHistoryRow: Decodable, Equatable, Identifiable {
    let id: UUID
    let fightId: UUID?
    let name: String?
    let startsAt: String
    let endsAt: String
    let category: String
    let result: String
    let placement: Int?
    let fieldSize: Int
    let counted: Bool
    let complete: Bool?
    enum CodingKeys: String, CodingKey {
        case id, name, category, result, placement, counted, complete
        case fightId = "fight_id", startsAt = "starts_at", endsAt = "ends_at", fieldSize = "field_size"
    }
}

struct ProfileHistoryPage: Decodable {
    let results: [ProfileHistoryRow]
    let nextCursor: UUID?
    enum CodingKeys: String, CodingKey { case results, nextCursor = "next_cursor" }
}

struct ProfileFriendsPage: Decodable {
    let people: [SharedProfileIdentity]
    let nextCursor: UUID?
    let incomingCount: Int
    enum CodingKeys: String, CodingKey { case people, nextCursor = "next_cursor", incomingCount = "incoming_count" }
}

struct ProfileFriendshipResponse: Decodable { let friendship: String }

struct ProfileChallengeDraft: Equatable {
    let handle: String
    let durationSeconds: Int?
    let actionText: String?
}

struct FightAdministrationCapabilities: Decodable {
    let manageFights: Bool
    enum CodingKeys: String, CodingKey { case manageFights = "manage_fights" }
}

struct AdministerFightRequest: Encodable {
    var visibility: String? = nil
    var recurring: Bool? = nil
    var action: String? = nil
}

struct ProfileRivalrySummary: Decodable, Identifiable {
    let identity: SharedProfileIdentity
    let rivalry: ProfileRivalry
    var id: UUID { identity.userId }
}

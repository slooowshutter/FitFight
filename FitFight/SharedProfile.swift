import Foundation

struct SharedProfileIdentity: Codable, Equatable, Identifiable {
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

struct ProfileCounts: Codable, Equatable {
    let played: Int
    let wins: Int
    let winRate: Double?
    enum CodingKeys: String, CodingKey { case played, wins, winRate = "win_rate" }
}

struct ProfileRecord: Codable, Equatable {
    let played: Int
    let wins: Int
    /// Nil from a backend deployed before draws and losses were added.
    let draws: Int?
    let losses: Int?
    let winRate: Double?
    let categories: [String: ProfileCounts]
    let excluded: Int
    enum CodingKeys: String, CodingKey { case played, wins, draws, losses, categories, excluded, winRate = "win_rate" }
}

struct ProfileRivalry: Codable, Equatable {
    let wins: Int
    let losses: Int
    let draws: Int
    let rematch: ProfileRematch?
}

struct ProfileRematch: Codable, Equatable {
    let durationSeconds: Int
    let durationDays: Int?
    let actionText: String?
    enum CodingKeys: String, CodingKey {
        case durationSeconds = "duration_seconds", durationDays = "duration_days", actionText = "action_text"
    }
}

struct ProfileActivity: Codable, Equatable {
    let metric: String
    let days: Int
    let values: [ProfileActivityDay]
}

struct ProfileActivityDay: Codable, Equatable, Identifiable {
    let day: String
    let steps: Double
    let timeZone: String?
    let updatedAt: String
    let finalized: Bool
    var id: String { day }
    enum CodingKeys: String, CodingKey { case day, steps, finalized, timeZone = "time_zone", updatedAt = "updated_at" }
}

struct ProfileStepStatistics: Codable, Equatable {
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

struct ProfileBestStepDay: Codable, Equatable {
    let day: String
    let steps: Double
}

struct ProfileStepWeek: Codable, Equatable {
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

struct ProfileActivityLevel: Codable, Equatable, Identifiable {
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

/// Every finished Fight both people are still in, 1v1 and group, from your side. `form` is oldest first.
struct ProfileHeadToHead: Codable, Equatable {
    let wins: Int
    let draws: Int
    let losses: Int
    let form: [String]
}

/// Days in a row at `goal` steps or more. Only your own profile carries `best` and `recent`.
struct ProfileTenKStreak: Codable, Equatable {
    let goal: Int
    let current: Int
    let todayCounted: Bool
    let best: ProfileStreakRun?
    let recent: [ProfileStreakDay]?

    enum CodingKeys: String, CodingKey {
        case goal, current, best, recent
        case todayCounted = "today_counted"
    }
}

struct ProfileStreakRun: Codable, Equatable {
    let days: Int
    let from: String
    let through: String
}

struct ProfileStreakDay: Codable, Equatable {
    let day: String
    /// Nil for a day with no data.
    let steps: Double?
}

struct ProfileStepTotals: Codable, Equatable {
    let recordedDays: Int
    let totalSteps: Double
    let averageSteps: Double?
    let bestDaySteps: Double?
    let tenKDays: Int

    enum CodingKeys: String, CodingKey {
        case recordedDays = "recorded_days", totalSteps = "total_steps", averageSteps = "average_steps"
        case bestDaySteps = "best_day_steps", tenKDays = "ten_k_days"
    }
}

/// Both people's complete days since they became friends. `days` is 0 on the first day.
struct ProfileFriendComparison: Codable, Equatable {
    let since: String
    let days: Int
    let you: ProfileStepTotals
    let them: ProfileStepTotals
}

/// Codable so You can show the last loaded own profile while a fresh one loads.
struct SharedProfile: Codable, Equatable {
    let identity: SharedProfileIdentity
    let access: String
    let competitive: Bool
    let friendship: String
    let record: ProfileRecord?
    let rivalry: ProfileRivalry?
    let activity: ProfileActivity?
    let stepStatistics: ProfileStepStatistics?
    let viewMeasurementEnabled: Bool
    /// A custom companion's name and line. Stock companions and older servers send none.
    let companionName: String?
    let companionLine: String?
    /// The Player card fields. Older servers send none of them.
    let memberSince: String?
    let headToHead: ProfileHeadToHead?
    let tenKStreak: ProfileTenKStreak?
    let friendComparison: ProfileFriendComparison?
    enum CodingKeys: String, CodingKey {
        case identity, access, competitive, friendship, record, rivalry, activity
        case viewMeasurementEnabled = "view_measurement_enabled"
        case stepStatistics = "step_statistics"
        case companionName = "companion_name"
        case companionLine = "companion_line"
        case memberSince = "member_since"
        case headToHead = "head_to_head"
        case tenKStreak = "ten_k_streak"
        case friendComparison = "friend_comparison"
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
    /// Fights together only: your place, and your result against this person once the Fight counts.
    let viewerPlacement: Int?
    let headToHead: String?
    enum CodingKeys: String, CodingKey {
        case id, name, category, result, placement, counted, complete
        case fightId = "fight_id", startsAt = "starts_at", endsAt = "ends_at", fieldSize = "field_size"
        case viewerPlacement = "viewer_placement", headToHead = "head_to_head"
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

/// `GET /api/v1/friends/suggestions`, most shared fights first. Each person also carries
/// `shared_fights`, which the app does not show.
struct FriendSuggestionList: Decodable { let people: [SharedProfileIdentity] }
struct ProfileSearchList: Decodable { let people: [SharedProfileIdentity] }

struct ProfileChallengeDraft: Equatable {
    let handle: String
    let durationSeconds: Int?
    let actionText: String?
    var durationDays: Int? = nil
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

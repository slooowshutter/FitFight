import Foundation

struct FightStepCheckpoint: Codable, Equatable {
    let day: String
    let cutoffAt: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case day, steps
        case cutoffAt = "cutoff_at"
    }
}

struct FitFightSnapshot: Decodable {
    let fights: [FightRow]
    let members: [MemberRow]
    let profiles: [FitFightProfile]
    let series: [SeriesRow]
    let stepDays: [StepDayRow]

    enum CodingKeys: String, CodingKey {
        case fights, members, profiles, series
        case stepDays = "step_days"
    }
}

struct SeriesRow: Decodable {
    let id: UUID
    let joinCode: String?
    let visibility: String
    let recurring: Bool
    let suggested: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case joinCode = "join_code"
        case visibility
        case recurring
        case suggested
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        joinCode = try container.decodeIfPresent(String.self, forKey: .joinCode)
        visibility = try container.decode(String.self, forKey: .visibility)
        recurring = try container.decode(Bool.self, forKey: .recurring)
        suggested = try container.decodeIfPresent(Bool.self, forKey: .suggested) ?? false
    }
}

struct StepDayRow: Decodable {
    let userId: UUID
    let day: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case day
        case steps
    }
}

struct FightRow: Decodable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let state: String
    let startsAt: String
    let endsAt: String
    let graceEndsAt: String?
    let actionText: String?
    let seriesId: UUID?
    let timeZone: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case state
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case graceEndsAt = "grace_ends_at"
        case actionText = "action_text"
        case seriesId = "series_id"
        case timeZone = "time_zone"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decode(String.self, forKey: .state)
        startsAt = try container.decode(String.self, forKey: .startsAt)
        endsAt = try container.decode(String.self, forKey: .endsAt)
        graceEndsAt = try container.decodeIfPresent(String.self, forKey: .graceEndsAt)
        actionText = try container.decodeIfPresent(String.self, forKey: .actionText)
        seriesId = try container.decodeIfPresent(UUID.self, forKey: .seriesId)
        timeZone = try container.decodeIfPresent(String.self, forKey: .timeZone)
    }

    var startsAtDate: Date { Self.parse(startsAt) ?? Date() }
    var endsAtDate: Date { Self.parse(endsAt) ?? Date().addingTimeInterval(86400) }
    var graceEndsAtDate: Date? { graceEndsAt.flatMap(Self.parse) }

    static func parse(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

struct MemberRow: Decodable {
    let fightId: UUID
    let userId: UUID
    let state: String
    let currentValue: Double?
    let rank: Int?
    let finalValue: Double?
    let lastSyncedAt: Date?
    let finalStepsComplete: Bool?
    let stepCheckpoints: [FightStepCheckpoint]?

    enum CodingKeys: String, CodingKey {
        case fightId = "fight_id"
        case userId = "user_id"
        case state
        case currentValue = "current_value"
        case rank
        case finalValue = "final_value"
        case lastSyncedAt = "last_synced_at"
        case finalStepsComplete = "final_steps_complete"
        case stepCheckpoints = "step_checkpoints"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fightId = try container.decode(UUID.self, forKey: .fightId)
        userId = try container.decode(UUID.self, forKey: .userId)
        state = try container.decode(String.self, forKey: .state)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        currentValue = Self.number(container, .currentValue)
        finalValue = Self.number(container, .finalValue)
        finalStepsComplete = try container.decodeIfPresent(Bool.self, forKey: .finalStepsComplete)
        stepCheckpoints = try container.decodeIfPresent([FightStepCheckpoint].self, forKey: .stepCheckpoints)
        if let date = try? container.decode(Date.self, forKey: .lastSyncedAt) {
            lastSyncedAt = date
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .lastSyncedAt) {
            lastSyncedAt = FightRow.parse(raw)
        } else {
            lastSyncedAt = nil
        }
    }

    private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decode(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

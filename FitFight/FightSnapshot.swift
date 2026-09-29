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

    var startsAtDate: Date { parseServerDate(startsAt) ?? Date() }
    var endsAtDate: Date { parseServerDate(endsAt) ?? Date().addingTimeInterval(86400) }
    var graceEndsAtDate: Date? { graceEndsAt.flatMap(parseServerDate) }
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
            lastSyncedAt = parseServerDate(raw)
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

/// `GET /api/v1/admin/dashboard`. Declared here rather than in FitFightAPI.swift because
/// tests/APIContractTests.swift compiles this file (see .github/workflows/ios-build.yml).
/// Cards and charts are server-defined: `kind`, `unit` and `x_kind` stay strings so new
/// values never fail decoding.
struct FitFightAdminDashboard: Decodable {
    struct Card: Decodable, Identifiable {
        let id: String
        let title: String
        let value: Double?
        let previous: Double?
        /// count, steps, percent (0-100), days, hours, minutes or seconds.
        let unit: String
        /// nil when neither direction is good or bad.
        let higherIsBetter: Bool?
        let note: String?

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case value
            case previous
            case unit
            case higherIsBetter = "higher_is_better"
            case note
        }
    }

    struct Chart: Decodable, Identifiable {
        let id: String
        let title: String
        /// line, bar or heatmap.
        let kind: String
        let unit: String
        /// date (x is YYYY-MM-DD) or label.
        let xKind: String
        let note: String?
        /// Line and bar charts. Empty for a heatmap.
        let series: [Series]
        /// Heatmaps only, row-major. Empty otherwise.
        let cells: [Cell]

        enum CodingKeys: String, CodingKey {
            case id
            case title
            case kind
            case unit
            case xKind = "x_kind"
            case note
            case series
            case cells
        }
    }

    struct Series: Decodable {
        let name: String
        /// The previous period, already shifted onto the current dates by the server.
        let previous: Bool
        let points: [Point]
    }

    struct Point: Decodable {
        let x: String
        let y: Double
    }

    struct Cell: Decodable {
        let x: String
        let y: String
        let value: Double
    }

    let section: String
    let days: Int
    /// production or staging.
    let environment: String
    let generatedAt: Date
    let cards: [Card]
    let charts: [Chart]

    enum CodingKeys: String, CodingKey {
        case section
        case days
        case environment
        case generatedAt = "generated_at"
        case cards
        case charts
    }
}

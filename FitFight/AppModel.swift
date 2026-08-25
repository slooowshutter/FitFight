import Foundation
import Supabase
import SwiftUI

enum MetricKind: String, CaseIterable, Identifiable {
    case activeMinutes
    case steps
    case workouts

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .activeMinutes: return "Active minutes"
        case .steps: return "Steps total"
        case .workouts: return "Workout count"
        }
    }

    var title: String {
        switch self {
        case .activeMinutes: return "Active Minutes"
        case .steps: return "Steps Total"
        case .workouts: return "Workout Count"
        }
    }

    var blurb: String {
        switch self {
        case .activeMinutes: return "Best cross-source metric"
        case .steps: return "Daily friend battles"
        case .workouts: return "Low-friction bragging rights"
        }
    }
}

enum SettlementKind: String, CaseIterable, Identifiable {
    case winner
    case proportional
    case goal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winner: return "Winner takes all"
        case .proportional: return "Proportional"
        case .goal: return "Hit your goal"
        }
    }

    var blurb: String {
        switch self {
        case .winner: return "First place takes everything. Nobody else gets anything back."
        case .proportional: return "Your share of the effort is your share of the pot — do 60% of the steps, take 60% of the money."
        case .goal: return "Hit your daily goal and your money comes back. Miss it and it goes to whoever made it."
        }
    }
}

enum StakeKind: String, CaseIterable, Identifiable {
    case bragging
    case ten
    case custom

    var id: String { rawValue }
}

enum CustomStakeKind: String {
    case money
    case action
}

enum FightStatus {
    case live
    case invited
    case finished
}

struct Person: Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var initials: String
    var isYou: Bool = false

    /// The design's cast photographs, cut out of the mocks into the asset catalogue.
    var photo: String { "Avatar-\(isYou ? "maya" : id)" }
}

extension FFAvatar {
    init(_ person: Person?, size: CGFloat = 24, ring: Bool = false, pending: Bool = false) {
        self.init(
            initials: person?.initials ?? "?",
            photo: person?.photo,
            size: size,
            ring: ring,
            pending: pending
        )
    }
}

struct Standing: Identifiable, Hashable {
    var person: Person
    var score: Double
    var today: Double
    var projectedNet: Int
    var invited: Bool = false
    var safe: Bool? = nil

    var id: String { person.id }
}

struct DayScore: Identifiable, Hashable {
    var person: Person
    var value: Double

    var id: String { person.id }
}

struct FightDay: Identifiable, Hashable {
    var label: String
    var scores: [DayScore]

    var id: String { label }
}

struct Fight: Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var metric: MetricKind
    var lengthDays: Int
    var daysLeft: Int? = nil
    var endedLabel: String? = nil
    var pot: Int
    var buyIn: Int
    var settlement: SettlementKind
    var status: FightStatus
    var rank: Int
    var of: Int
    var pending: Int
    var kickerPrefix: String = ""
    var kickerEmphasis: String
    var kickerRest: String = ""
    var listSubtitle: String
    var payoutLine: String
    var invitePitch: String? = nil
    var inviteAction: String? = nil
    var paceNote: String? = nil
    var standingsMeta: String? = nil
    var dailyGoal: Double? = nil
    var standings: [Standing]
    var days: [FightDay] = []
    var windowStart: Date = Date()
    var windowEnd: Date = Date().addingTimeInterval(86400)
}

struct RequestItem: Identifiable, Hashable {
    var id: String
    var title: String
    var body: String
    var kind: Kind
    var status: Status
    var author: Person
    var ago: String
    var comments: Int
    var votes: Int

    enum Kind { case feature, bug }
    enum Status { case open, planned, shipped }
}

struct HistoryItem: Identifiable, Hashable {
    var id: String
    var name: String
    var detail: String
    var net: Int
    var won: Bool
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tab: FFTab = .fights {
        didSet {
            if oldValue != tab {
                openFightID = nil
            }
        }
    }

    @Published var openFightID: String?
    @Published var showingVersions = false
    @Published var voted: Set<String> = ["r1", "r3", "r6"]
    @Published var joined: Set<String> = []
    @Published var createError: String?
    @Published var loadError: String?

    @Published var you: Person
    @Published var people: [Person]
    @Published var fights: [Fight]
    @Published var history: [HistoryItem]

    let requests: [RequestItem]

    private var session: SessionStore?
    private let api = FitFightAPI()
    private var inviteTokens: [String: String] = [:]

    static var preview: AppModel { AppModel(fixtures: true) }

    static var shouldLoadFixtures: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["FF_SHOOT"] == "1" || env["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    convenience init() {
        self.init(fixtures: Self.shouldLoadFixtures)
    }

    convenience init(preview: Void) {
        self.init(fixtures: true)
    }

    init(fixtures: Bool) {
        let bundle = AppModelFixtures.load()
        you = bundle.you
        requests = bundle.requests
        if fixtures {
            people = bundle.people
            fights = bundle.fights
            history = bundle.history
        } else {
            people = []
            fights = []
            history = []
        }
    }

    func fight(id: String) -> Fight? {
        fights.first { $0.id == id }
    }

    var live: [Fight] { fights.filter { $0.status == .live } }
    var invitations: [Fight] { fights.filter { $0.status == .invited } }
    var finished: [Fight] { fights.filter { $0.status == .finished } }

    var projectedNet: Int {
        live.reduce(0) { $0 + (youStanding(in: $1)?.projectedNet ?? 0) }
    }

    func youStanding(in fight: Fight) -> Standing? {
        fight.standings.first { $0.person.isYou }
    }

    func formatScore(_ value: Double, metric: MetricKind) -> String {
        switch metric {
        case .activeMinutes, .workouts:
            return String(format: "%.0f", value)
        case .steps:
            if value >= 1000 {
                return String(format: "%.1fk", value / 1000)
            }
            return String(format: "%.0f", value)
        }
    }

    func formatDelta(_ value: Double, metric: MetricKind) -> String {
        let body = formatScore(value, metric: metric)
        if value > 0 { return "+\(body)" }
        if value < 0 { return "−\(body)" }
        return body
    }

    func projectedPace(_ row: Standing, in fight: Fight) -> Double {
        let elapsed = max(1, fight.lengthDays - (fight.daysLeft ?? 0))
        return row.score * Double(fight.lengthDays) / Double(elapsed)
    }

    func paceLine(_ row: Standing, in fight: Fight) -> String {
        if row.invited { return "Hasn’t joined yet" }
        if fight.status == .invited {
            switch fight.metric {
            case .activeMinutes: return "on pace for 0 min"
            case .steps: return "on pace for 0 steps"
            case .workouts: return "0 so far"
            }
        }
        let pace = projectedPace(row, in: fight)
        switch fight.metric {
        case .activeMinutes:
            return "on pace for \(Int(pace.rounded())) min"
        case .steps:
            return "on pace for \(formatScore(pace, metric: .steps))"
        case .workouts:
            return "\(Int(row.score)) so far"
        }
    }

    func refreshFromServer() async {
        guard let session else { return }
        await refreshFromServer(session: session)
    }

    func refreshFromServer(session: SessionStore) async {
        self.session = session
        guard let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id else {
            return
        }
        if let profile = session.profile {
            you = Self.person(from: profile, isYou: true)
        }

        let friends = FriendshipStore(client: session.client)
        do {
            try await friends.load(userId: userId)
            people = friends.friends.map { Self.person(from: $0, isYou: false) }
        } catch {
            people = []
        }

        if let token = session.authSession?.accessToken, api.isConfigured {
            _ = try? await api.syncDueFights(accessToken: token)
        }

        do {
            try await closeDueFights(client: session.client, userId: userId)
            var loaded = try await loadFights(client: session.client, userId: userId)
            loaded = try await overlayStepDays(loaded, client: session.client, userId: userId)
            fights = loaded
            history = loaded
                .filter { $0.status == .finished }
                .map { fight in
                    let net = youStanding(in: fight)?.projectedNet ?? 0
                    return HistoryItem(
                        id: fight.id,
                        name: fight.name,
                        detail: fight.listSubtitle,
                        net: net,
                        won: fight.rank == 1
                    )
                }
            loadError = nil
        } catch {
            loadError = "Couldn’t refresh fights. Pull to try again."
        }
    }

    func createAndStartFight(
        name: String = "Steps Fight",
        startsAt: Date,
        endsAt: Date,
        outcomeRule: SettlementKind,
        stake: StakeKind,
        customKind: CustomStakeKind = .money,
        customMoney: Int = 15,
        actionText: String? = nil,
        dailyGoal: Double? = nil,
        inviteHandles: [String]
    ) async {
        createError = nil
        guard session?.authSession?.accessToken != nil else {
            createError = "Sign in to start a fight."
            return
        }

        let stakePair = Self.apiStake(stake: stake, customKind: customKind, customMoney: customMoney)
        let payload = FitFightCreateFight(
            name: name,
            startsAt: startsAt,
            endsAt: max(endsAt, startsAt.addingTimeInterval(60)),
            timeZone: TimeZone.current.identifier,
            outcomeRule: Self.apiOutcome(outcomeRule),
            goalPolicy: outcomeRule == .goal ? "shared" : nil,
            defaultGoalValue: outcomeRule == .goal ? dailyGoal : nil,
            stakeKind: stakePair.kind,
            stakeMinor: stakePair.minor,
            currency: stakePair.kind == "money" ? "USD" : nil,
            actionText: stake == .custom && customKind == .action ? actionText : nil,
            inviteHandles: inviteHandles,
            start: "now"
        )

        do {
            try await createFightOnClient(
                payload,
                inviteHandles: inviteHandles
            )
            await refreshFromServer()
        } catch {
            createError = (error as? LocalizedError)?.errorDescription ?? "Couldn’t start the fight."
        }
    }

    func acceptInvite(token: String) async throws {
        createError = nil
        guard let access = session?.authSession?.accessToken else {
            throw FitFightAPIError.notConfigured
        }
        let summary = try await api.accept(token: token, accessToken: access)
        inviteTokens[summary.id.uuidString] = token
        await refreshFromServer()
    }

    func acceptFight(id: String) async {
        createError = nil
        if let token = inviteTokens[id], api.isConfigured {
            do {
                try await acceptInvite(token: token)
            } catch {
                createError = (error as? LocalizedError)?.errorDescription ?? "Couldn’t accept."
            }
            return
        }
        guard let session, let userId = session.authSession?.user.id, let fightID = UUID(uuidString: id) else {
            createError = "Sign in to accept this fight."
            return
        }
        do {
            try await session.client.from("fight_members")
                .update(MemberAcceptUpdate(state: "accepted", acceptedAt: Self.isoNow()))
                .eq("fight_id", value: fightID)
                .eq("user_id", value: userId)
                .execute()
            joined.insert(id)
            await refreshFromServer()
        } catch {
            createError = (error as? LocalizedError)?.errorDescription ?? "Couldn’t accept."
        }
    }

    private func createFightOnClient(
        _ payload: FitFightCreateFight,
        inviteHandles: [String]
    ) async throws {
        guard let session, let userId = session.authSession?.user.id else {
            throw LiveFightError.notSignedIn
        }

        var inviteIds: [UUID] = []
        let handles = inviteHandles
            .map { FriendshipStore.strippedHandle($0) }
            .filter { !$0.isEmpty }
        if !handles.isEmpty {
            let found: [FitFightProfile] = try await session.client.from("profiles")
                .select("user_id, handle, display_name")
                .in("handle", values: handles)
                .execute()
                .value
            if let missing = handles.first(where: { want in !found.contains { $0.handle == want } }) {
                throw LiveFightError.unknownHandle(missing)
            }
            inviteIds = found.map(\.userId).filter { $0 != userId }
        }

        let inserted: FightIDRow = try await session.client.from("fights")
            .insert(
                FightInsert(
                    ownerId: userId,
                    name: payload.name,
                    state: "live",
                    startsAt: Self.isoString(payload.startsAt),
                    endsAt: Self.isoString(payload.endsAt),
                    timeZone: payload.timeZone,
                    metric: "steps",
                    outcomeRule: payload.outcomeRule,
                    goalPolicy: payload.goalPolicy ?? "shared",
                    defaultGoalValue: payload.defaultGoalValue,
                    stakeKind: payload.stakeKind,
                    stakeMinor: payload.stakeMinor,
                    currency: payload.currency,
                    actionText: payload.actionText
                )
            )
            .select("id")
            .single()
            .execute()
            .value

        var members = [
            MemberInsert(
                fightId: inserted.id,
                userId: userId,
                state: "accepted",
                acceptedAt: Self.isoNow()
            )
        ]
        members += inviteIds.map {
            MemberInsert(fightId: inserted.id, userId: $0, state: "invited", acceptedAt: nil)
        }
        try await session.client.from("fight_members").insert(members).execute()
    }

    private func closeDueFights(client: SupabaseClient, userId: UUID) async throws {
        let mine: [MemberRow] = try await client.from("fight_members")
            .select("fight_id, user_id, state, current_value, rank, outcome_minor, personal_target, final_value")
            .eq("user_id", value: userId)
            .execute()
            .value
        var ids = Set(mine.map(\.fightId))
        let owned: [FightIDRow] = try await client.from("fights")
            .select("id")
            .eq("owner_id", value: userId)
            .execute()
            .value
        owned.forEach { ids.insert($0.id) }
        guard !ids.isEmpty else { return }

        let rows: [FightRow] = try await client.from("fights")
            .select("id, owner_id, name, state, starts_at, ends_at, time_zone, metric, outcome_rule, goal_policy, default_goal_value, stake_kind, stake_minor, currency, action_text")
            .in("id", values: ids.map(\.uuidString))
            .execute()
            .value
        let due = rows.filter { row in
            row.endsAtDate < Date() && row.state != "final" && row.state != "cancelled"
        }
        for row in due {
            try? await client.from("fights")
                .update(["state": "final"])
                .eq("id", value: row.id)
                .execute()
        }
    }

    private func overlayStepDays(
        _ fights: [Fight],
        client: SupabaseClient,
        userId: UUID
    ) async throws -> [Fight] {
        let ids = fights.flatMap { fight in
            fight.standings.compactMap { UUID(uuidString: $0.person.id) }
        }
        guard !ids.isEmpty else { return fights }

        let days: [StepDayRow]
        do {
            days = try await client.from("step_days")
                .select("user_id, day, steps")
                .in("user_id", values: ids.map(\.uuidString))
                .execute()
                .value
        } catch {
            return fights
        }

        let today = Self.dayStamp(Date())
        var updated: [Fight] = []
        updated.reserveCapacity(fights.count)
        for fight in fights {
            var next = fight
            let window = Self.fightDayWindow(fight)
            let people = fight.standings.map { row -> Standing in
                var standing = row
                guard let personID = UUID(uuidString: row.person.id) else { return row }
                let mine = days.filter { $0.userId == personID && window.contains($0.day) }
                standing.score = Double(mine.reduce(0) { $0 + $1.steps })
                standing.today = Double(mine.first { $0.day == today }?.steps ?? 0)
                return standing
            }
            .sorted { lhs, rhs in
                if lhs.invited != rhs.invited { return !lhs.invited && rhs.invited }
                if lhs.score == rhs.score { return lhs.person.name < rhs.person.name }
                return lhs.score > rhs.score
            }
            next.standings = people
            next.days = Self.dayCards(from: days, standings: people, window: window)
            if let you = people.first(where: { $0.person.isYou }) {
                next.rank = people.filter { !$0.invited }.firstIndex { $0.person.id == you.person.id }.map { $0 + 1 } ?? next.rank
                if let fightID = UUID(uuidString: fight.id) {
                    try? await client.from("fight_members")
                        .update(CurrentValueUpdate(currentValue: you.score))
                        .eq("fight_id", value: fightID)
                        .eq("user_id", value: userId)
                        .execute()
                }
            }
            updated.append(next)
        }
        return updated
    }

    /// Civil days in `[windowStart, windowEnd)`. A 3-day chip is three dates, not four.
    private static func fightDayWindow(_ fight: Fight) -> Set<String> {
        let calendar = Calendar.current
        var days: [String] = []
        var cursor = calendar.startOfDay(for: fight.windowStart)
        let last = calendar.startOfDay(for: fight.windowEnd)
        while cursor < last && days.count <= 40 {
            days.append(dayStamp(cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        if days.isEmpty {
            days.append(dayStamp(fight.windowStart))
        }
        return Set(days)
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func dayCards(
        from days: [StepDayRow],
        standings: [Standing],
        window: Set<String>
    ) -> [FightDay] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let label = DateFormatter()
        label.dateFormat = "EEE d MMM"
        return window.sorted().map { day in
            let scores = standings.map { row in
                let personID = UUID(uuidString: row.person.id)
                let value = days.first { $0.userId == personID && $0.day == day }?.steps ?? 0
                return DayScore(person: row.person, value: Double(value))
            }
            let date = formatter.date(from: day) ?? Date()
            return FightDay(label: label.string(from: date), scores: scores)
        }
    }

    private static func dayStamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isoNow() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }

    func addFriend(handle: String) async {
        createError = nil
        guard let session, let userId = session.authSession?.user.id else {
            createError = "Sign in to add a friend."
            return
        }
        let store = FriendshipStore(client: session.client)
        do {
            try await store.requestFriendship(handle: handle, requesterId: userId)
            await refreshFromServer(session: session)
        } catch {
            createError = (error as? LocalizedError)?.errorDescription ?? "Couldn’t add that friend."
        }
    }

    private func loadFights(client: SupabaseClient, userId: UUID) async throws -> [Fight] {
        let memberSelect = "fight_id, user_id, state, current_value, rank, outcome_minor, personal_target, final_value"
        let fightSelect = "id, owner_id, name, state, starts_at, ends_at, time_zone, metric, outcome_rule, goal_policy, default_goal_value, stake_kind, stake_minor, currency, action_text"

        let myRows: [MemberRow] = try await client.from("fight_members")
            .select(memberSelect)
            .eq("user_id", value: userId)
            .execute()
            .value
        var fightIDs = Set(myRows.map(\.fightId))

        let owned: [FightRow] = try await client.from("fights")
            .select(fightSelect)
            .eq("owner_id", value: userId)
            .execute()
            .value
        owned.forEach { fightIDs.insert($0.id) }

        guard !fightIDs.isEmpty else { return [] }

        let fightRows: [FightRow] = try await client.from("fights")
            .select(fightSelect)
            .in("id", values: fightIDs.map(\.uuidString))
            .execute()
            .value

        let memberRows: [MemberRow] = try await client.from("fight_members")
            .select(memberSelect)
            .in("fight_id", values: fightIDs.map(\.uuidString))
            .execute()
            .value

        var profileIDs = Set(memberRows.map(\.userId))
        fightRows.forEach { profileIDs.insert($0.ownerId) }
        let profiles = try await Self.fetchProfiles(client: client, ids: Array(profileIDs))
        let byProfile = Dictionary(uniqueKeysWithValues: profiles.map { ($0.userId, $0) })
        let membersByFight = Dictionary(grouping: memberRows, by: \.fightId)
        let myByFight = Dictionary(uniqueKeysWithValues: myRows.map { ($0.fightId, $0) })

        return fightRows.compactMap { row in
            Self.mapFight(
                row,
                members: membersByFight[row.id] ?? [],
                mine: myByFight[row.id],
                profiles: byProfile,
                userId: userId,
                formatScore: formatScore
            )
        }
    }

    private static func fetchProfiles(client: SupabaseClient, ids: [UUID]) async throws -> [FitFightProfile] {
        guard !ids.isEmpty else { return [] }
        return try await client.from("profiles")
            .select("user_id, handle, display_name")
            .in("user_id", values: ids.map(\.uuidString))
            .execute()
            .value
    }

    private static func person(from profile: FitFightProfile, isYou: Bool) -> Person {
        Person(
            id: profile.userId.uuidString,
            name: isYou ? (profile.displayName.isEmpty ? "You" : profile.displayName) : profile.displayName,
            handle: profile.atHandle,
            initials: profile.initials,
            isYou: isYou
        )
    }

    private static func apiOutcome(_ settlement: SettlementKind) -> String {
        switch settlement {
        case .winner: return "highest_total"
        case .proportional: return "proportional"
        case .goal: return "hit_your_goal"
        }
    }

    private static func apiStake(
        stake: StakeKind,
        customKind: CustomStakeKind,
        customMoney: Int
    ) -> (kind: String, minor: Int?) {
        switch stake {
        case .bragging:
            return ("bragging", nil)
        case .ten:
            return ("money", 1000)
        case .custom:
            if customKind == .action { return ("action", nil) }
            return ("money", max(0, customMoney) * 100)
        }
    }

    private static func mapFight(
        _ row: FightRow,
        members: [MemberRow],
        mine: MemberRow?,
        profiles: [UUID: FitFightProfile],
        userId: UUID,
        formatScore: (Double, MetricKind) -> String
    ) -> Fight? {
        if row.state == "draft" { return nil }

        let settlement: SettlementKind
        switch row.outcomeRule {
        case "proportional": settlement = .proportional
        case "hit_your_goal": settlement = .goal
        default: settlement = .winner
        }

        let accepted = members.filter { $0.state == "accepted" }
        let pendingMembers = members.filter { $0.state == "invited" }
        let buyIn = row.stakeKind == "money" ? (row.stakeMinor ?? 0) / 100 : 0
        let pot = row.stakeKind == "money" ? buyIn * accepted.count : 0

        let starts = row.startsAtDate
        let ends = row.endsAtDate
        let lengthDays = max(1, Calendar.current.dateComponents([.day], from: starts, to: ends).day ?? 1)

        let status: FightStatus
        if mine?.state == "invited" && row.state != "final" && row.state != "cancelled" {
            status = .invited
        } else if row.state == "final" || row.state == "cancelled" || ends < Date() {
            status = .finished
        } else {
            status = .live
        }

        let daysLeft: Int?
        if row.state == "awaiting_final_sync" {
            daysLeft = 0
        } else if status == .finished {
            daysLeft = nil
        } else {
            daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: ends).day ?? 0)
        }

        let people = members.map { member -> Standing in
            let profile = profiles[member.userId]
            let person: Person
            if let profile {
                person = Self.person(from: profile, isYou: member.userId == userId)
            } else {
                person = Person(
                    id: member.userId.uuidString,
                    name: member.userId == userId ? "You" : "Fighter",
                    handle: "@user",
                    initials: "FF",
                    isYou: member.userId == userId
                )
            }
            let score = member.currentValue ?? member.finalValue ?? 0
            let net = (member.outcomeMinor ?? 0) / 100
            return Standing(
                person: person,
                score: score,
                today: 0,
                projectedNet: net,
                invited: member.state == "invited"
            )
        }
        .sorted { lhs, rhs in
            if lhs.invited != rhs.invited { return !lhs.invited && rhs.invited }
            if lhs.score == rhs.score { return lhs.person.name < rhs.person.name }
            return lhs.score > rhs.score
        }

        let joined = people.filter { !$0.invited }
        let youRow = people.first { $0.person.isYou }
        let rank = youRow.flatMap { row in joined.firstIndex { $0.person.id == row.person.id }.map { $0 + 1 } }
            ?? mine?.rank
            ?? 0
        let of = max(joined.count, 1)
        let owner = profiles[row.ownerId].map { Self.person(from: $0, isYou: $0.userId == userId) }
        let ownerName = owner?.name ?? "Someone"

        let payoutLine: String
        if row.stakeKind == "bragging" || pot == 0 && row.stakeKind != "money" {
            payoutLine = row.actionText?.isEmpty == false ? (row.actionText ?? "Bragging rights only") : "Bragging rights only"
        } else {
            switch settlement {
            case .winner:
                payoutLine = "Winner takes the whole $\(pot)"
            case .proportional:
                payoutLine = "Your share of the steps is your share of the pot"
            case .goal:
                let goal = row.defaultGoalValue ?? 10000
                payoutLine = "Hit \(Self.shortSteps(goal)) steps/day and your $\(buyIn) comes back"
            }
        }

        var kickerPrefix = ""
        var kickerEmphasis = ""
        var kickerRest = ""
        var listSubtitle = ""
        var invitePitch: String?
        var inviteAction: String?
        var endedLabel: String?
        var standingsMeta: String?

        switch status {
        case .invited:
            invitePitch = "\(ownerName) wants a piece of you"
            inviteAction = "Accept"
            kickerEmphasis = invitePitch ?? ""
            let stakeBit = pot > 0 ? "$\(pot) pot" : "No stake"
            listSubtitle = "\(ownerName) · \(lengthDays) days · \(stakeBit)"
            standingsMeta = "\(accepted.count) in · \(pendingMembers.count) not replied"
        case .finished:
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            endedLabel = "Ended \(formatter.string(from: ends))"
            listSubtitle = "\(endedLabel ?? "Ended") · \(Self.ordinal(rank)) of \(of)"
            kickerPrefix = rank == 1 ? "Won by" : "Finished"
            kickerEmphasis = Self.ordinal(rank)
        case .live:
            if row.state == "awaiting_final_sync" {
                kickerEmphasis = "Syncing final steps"
                listSubtitle = "0d left"
            } else if let youRow, let leader = joined.first, !youRow.invited {
                if youRow.person.id == leader.person.id {
                    kickerPrefix = "Holding"
                    kickerEmphasis = "1st"
                    kickerRest = "with \(daysLeft ?? 0)d to go"
                    listSubtitle = "Holding 1st with \(daysLeft ?? 0)d to go"
                } else {
                    let gap = leader.score - youRow.score
                    kickerEmphasis = formatScore(max(0, gap), .steps)
                    kickerRest = "behind \(leader.person.name)"
                    listSubtitle = "\(kickerEmphasis) behind \(leader.person.name)"
                }
            } else {
                kickerEmphasis = "\(daysLeft ?? 0)d left"
                listSubtitle = kickerEmphasis
            }
        }

        let short = row.id.uuidString.replacingOccurrences(of: "-", with: "")
        let code = "FIGHT-" + String(short.prefix(3)).uppercased()

        return Fight(
            id: row.id.uuidString,
            code: code,
            name: row.name,
            metric: .steps,
            lengthDays: lengthDays,
            daysLeft: daysLeft,
            endedLabel: endedLabel,
            pot: pot,
            buyIn: buyIn,
            settlement: settlement,
            status: status,
            rank: rank,
            of: of,
            pending: pendingMembers.count,
            kickerPrefix: kickerPrefix,
            kickerEmphasis: kickerEmphasis,
            kickerRest: kickerRest,
            listSubtitle: listSubtitle,
            payoutLine: payoutLine,
            invitePitch: invitePitch,
            inviteAction: inviteAction,
            standingsMeta: standingsMeta,
            dailyGoal: row.defaultGoalValue,
            standings: people,
            windowStart: starts,
            windowEnd: ends
        )
    }

    private static func shortSteps(_ value: Double) -> String {
        if value >= 1000 { return String(format: "%.1fk", value / 1000) }
        return String(format: "%.0f", value)
    }

    private static func ordinal(_ value: Int) -> String {
        switch value {
        case 1: return "1st"
        case 2: return "2nd"
        case 3: return "3rd"
        default: return "\(value)th"
        }
    }
}

enum LiveFightError: LocalizedError {
    case notSignedIn
    case unknownHandle(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to start a fight."
        case .unknownHandle(let handle):
            return "No one with @\(handle). They need to open the app and pick a username first."
        }
    }
}

private struct FightIDRow: Decodable {
    let id: UUID
}

private struct FightInsert: Encodable {
    let ownerId: UUID
    let name: String
    let state: String
    let startsAt: String
    let endsAt: String
    let timeZone: String
    let metric: String
    let outcomeRule: String
    let goalPolicy: String
    let defaultGoalValue: Double?
    let stakeKind: String
    let stakeMinor: Int?
    let currency: String?
    let actionText: String?

    enum CodingKeys: String, CodingKey {
        case ownerId = "owner_id"
        case name
        case state
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeZone = "time_zone"
        case metric
        case outcomeRule = "outcome_rule"
        case goalPolicy = "goal_policy"
        case defaultGoalValue = "default_goal_value"
        case stakeKind = "stake_kind"
        case stakeMinor = "stake_minor"
        case currency
        case actionText = "action_text"
    }
}

private struct MemberInsert: Encodable {
    let fightId: UUID
    let userId: UUID
    let state: String
    let acceptedAt: String?

    enum CodingKeys: String, CodingKey {
        case fightId = "fight_id"
        case userId = "user_id"
        case state
        case acceptedAt = "accepted_at"
    }
}

private struct MemberAcceptUpdate: Encodable {
    let state: String
    let acceptedAt: String

    enum CodingKeys: String, CodingKey {
        case state
        case acceptedAt = "accepted_at"
    }
}

private struct CurrentValueUpdate: Encodable {
    let currentValue: Double

    enum CodingKeys: String, CodingKey {
        case currentValue = "current_value"
    }
}

private struct StepDayRow: Decodable {
    let userId: UUID
    let day: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case day
        case steps
    }
}

private struct FightRow: Decodable {
    let id: UUID
    let ownerId: UUID
    let name: String
    let state: String
    let startsAt: String
    let endsAt: String
    let timeZone: String
    let metric: String
    let outcomeRule: String
    let goalPolicy: String
    let defaultGoalValue: Double?
    let stakeKind: String
    let stakeMinor: Int?
    let currency: String?
    let actionText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case state
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case timeZone = "time_zone"
        case metric
        case outcomeRule = "outcome_rule"
        case goalPolicy = "goal_policy"
        case defaultGoalValue = "default_goal_value"
        case stakeKind = "stake_kind"
        case stakeMinor = "stake_minor"
        case currency
        case actionText = "action_text"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        ownerId = try container.decode(UUID.self, forKey: .ownerId)
        name = try container.decode(String.self, forKey: .name)
        state = try container.decode(String.self, forKey: .state)
        startsAt = try container.decode(String.self, forKey: .startsAt)
        endsAt = try container.decode(String.self, forKey: .endsAt)
        timeZone = try container.decode(String.self, forKey: .timeZone)
        metric = try container.decode(String.self, forKey: .metric)
        outcomeRule = try container.decode(String.self, forKey: .outcomeRule)
        goalPolicy = try container.decode(String.self, forKey: .goalPolicy)
        stakeKind = try container.decode(String.self, forKey: .stakeKind)
        stakeMinor = try container.decodeIfPresent(Int.self, forKey: .stakeMinor)
        currency = try container.decodeIfPresent(String.self, forKey: .currency)
        actionText = try container.decodeIfPresent(String.self, forKey: .actionText)
        if let value = try? container.decode(Double.self, forKey: .defaultGoalValue) {
            defaultGoalValue = value
        } else if let value = try? container.decode(Int.self, forKey: .defaultGoalValue) {
            defaultGoalValue = Double(value)
        } else if let value = try? container.decode(String.self, forKey: .defaultGoalValue) {
            defaultGoalValue = Double(value)
        } else {
            defaultGoalValue = nil
        }
    }

    var startsAtDate: Date { Self.parse(startsAt) ?? Date() }
    var endsAtDate: Date { Self.parse(endsAt) ?? Date().addingTimeInterval(86400) }

    private static func parse(_ raw: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }
}

private struct MemberRow: Decodable {
    let fightId: UUID
    let userId: UUID
    let state: String
    let currentValue: Double?
    let rank: Int?
    let outcomeMinor: Int?
    let personalTarget: Double?
    let finalValue: Double?

    enum CodingKeys: String, CodingKey {
        case fightId = "fight_id"
        case userId = "user_id"
        case state
        case currentValue = "current_value"
        case rank
        case outcomeMinor = "outcome_minor"
        case personalTarget = "personal_target"
        case finalValue = "final_value"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fightId = try container.decode(UUID.self, forKey: .fightId)
        userId = try container.decode(UUID.self, forKey: .userId)
        state = try container.decode(String.self, forKey: .state)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        outcomeMinor = try container.decodeIfPresent(Int.self, forKey: .outcomeMinor)
        currentValue = Self.number(container, .currentValue)
        personalTarget = Self.number(container, .personalTarget)
        finalValue = Self.number(container, .finalValue)
    }

    private static func number(_ container: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
        if let value = try? container.decode(Double.self, forKey: key) { return value }
        if let value = try? container.decode(Int.self, forKey: key) { return Double(value) }
        if let value = try? container.decode(String.self, forKey: key) { return Double(value) }
        return nil
    }
}

private enum AppModelFixtures {
    struct Bundle {
        var you: Person
        var people: [Person]
        var fights: [Fight]
        var requests: [RequestItem]
        var history: [HistoryItem]
    }

    static func load() -> Bundle {
        let leo = Person(id: "leo", name: "Leo", handle: "@leo.runs", initials: "L")
        let sam = Person(id: "sam", name: "Sam", handle: "@sam.sweats", initials: "S")
        let ivy = Person(id: "ivy", name: "Ivy", handle: "@ivy.climbs", initials: "I")
        let theo = Person(id: "theo", name: "Theo", handle: "@theo.rows", initials: "T")
        let nina = Person(id: "nina", name: "Nina", handle: "@nina.lifts", initials: "N")
        let you = Person(id: "you", name: "You", handle: "@maya.moves", initials: "MM", isYou: true)

        let fights = [
            Fight(
                id: "sweat",
                code: "FIGHT-742",
                name: "7-Day Sweat Ladder",
                metric: .activeMinutes,
                lengthDays: 7,
                daysLeft: 4,
                pot: 30,
                buyIn: 10,
                settlement: .winner,
                status: .live,
                rank: 2,
                of: 3,
                pending: 0,
                kickerEmphasis: "12 min",
                kickerRest: "behind Leo",
                listSubtitle: "12 min behind Leo",
                payoutLine: "Winner takes the whole $30",
                paceNote: "At this pace you finish on 98 min.",
                standings: [
                    Standing(person: leo, score: 54, today: 16, projectedNet: 20),
                    Standing(person: you, score: 42, today: 14, projectedNet: -10),
                    Standing(person: sam, score: 37, today: 12, projectedNet: -10)
                ],
                days: [
                    FightDay(label: "Day 1", scores: [
                        DayScore(person: leo, value: 20),
                        DayScore(person: you, value: 12),
                        DayScore(person: sam, value: 15)
                    ]),
                    FightDay(label: "Day 2", scores: [
                        DayScore(person: leo, value: 18),
                        DayScore(person: you, value: 16),
                        DayScore(person: sam, value: 10)
                    ]),
                    FightDay(label: "Day 3", scores: [
                        DayScore(person: leo, value: 16),
                        DayScore(person: you, value: 14),
                        DayScore(person: sam, value: 12)
                    ])
                ]
            ),
            Fight(
                id: "derby",
                code: "FIGHT-118",
                name: "Step Derby",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 2,
                pot: 50,
                buyIn: 10,
                settlement: .proportional,
                status: .live,
                rank: 1,
                of: 5,
                pending: 1,
                kickerPrefix: "Holding",
                kickerEmphasis: "1st",
                kickerRest: "with 2d to go",
                listSubtitle: "Holding 1st with 2d to go",
                payoutLine: "Your share of the steps is your share of the pot — 60% pays $30",
                standings: [
                    Standing(person: you, score: 61400, today: 8200, projectedNet: 1),
                    Standing(person: ivy, score: 59800, today: 6100, projectedNet: 1),
                    Standing(person: theo, score: 55200, today: 5200, projectedNet: 0),
                    Standing(person: leo, score: 40100, today: 4800, projectedNet: -8),
                    Standing(person: nina, score: 22000, today: 0, projectedNet: -10, invited: true)
                ]
            ),
            Fight(
                id: "club",
                code: "FIGHT-655",
                name: "10K Club",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 3,
                pot: 80,
                buyIn: 20,
                settlement: .goal,
                status: .live,
                rank: 2,
                of: 4,
                pending: 2,
                kickerEmphasis: "3.2k steps",
                kickerRest: "behind Sam",
                listSubtitle: "3.2k steps behind Sam",
                payoutLine: "Hit 10.0k steps/day and your $20 comes back",
                dailyGoal: 10000,
                standings: [
                    Standing(person: sam, score: 44800, today: 12100, projectedNet: 7, safe: true),
                    Standing(person: you, score: 41600, today: 8240, projectedNet: 7, safe: true),
                    Standing(person: nina, score: 31900, today: 4100, projectedNet: -20, safe: false),
                    Standing(person: ivy, score: 28100, today: 3900, projectedNet: -20, safe: false)
                ]
            ),
            Fight(
                id: "desk",
                code: "FIGHT-556",
                name: "Desk Job Revenge",
                metric: .steps,
                lengthDays: 5,
                daysLeft: 5,
                pot: 50,
                buyIn: 10,
                settlement: .winner,
                status: .invited,
                rank: 0,
                of: 4,
                pending: 2,
                kickerEmphasis: "Theo wants a piece of you",
                listSubtitle: "Theo · 5 days · $50 pot",
                payoutLine: "Winner takes the whole $50",
                invitePitch: "Theo wants a piece of you",
                inviteAction: "Accept",
                standingsMeta: "2 in · 2 not replied",
                standings: [
                    Standing(person: theo, score: 0, today: 0, projectedNet: 40),
                    Standing(person: nina, score: 0, today: 0, projectedNet: -10),
                    Standing(person: ivy, score: 0, today: 0, projectedNet: 0, invited: true)
                ]
            ),
            Fight(
                id: "sprint",
                code: "FIGHT-221",
                name: "City Sprint",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 7,
                pot: 0,
                buyIn: 0,
                settlement: .winner,
                status: .invited,
                rank: 0,
                of: 3,
                pending: 0,
                kickerEmphasis: "Ivy wants a piece of you",
                listSubtitle: "Ivy · 7 days · No stake",
                payoutLine: "Bragging rights only",
                invitePitch: "Ivy wants a piece of you",
                inviteAction: "Join",
                standings: [
                    Standing(person: ivy, score: 0, today: 0, projectedNet: 0)
                ]
            ),
            Fight(
                id: "weekend",
                code: "FIGHT-088",
                name: "Weekend Step Duel",
                metric: .steps,
                lengthDays: 2,
                endedLabel: "Ended Jul 13",
                pot: 20,
                buyIn: 10,
                settlement: .winner,
                status: .finished,
                rank: 1,
                of: 2,
                pending: 0,
                kickerPrefix: "Leading by",
                kickerEmphasis: "2.2k steps",
                listSubtitle: "Ended Jul 13 · 1st of 2",
                payoutLine: "Winner takes the whole $20",
                standingsMeta: "2 in",
                standings: [
                    Standing(person: you, score: 24100, today: 0, projectedNet: 10),
                    Standing(person: leo, score: 21900, today: 0, projectedNet: -10)
                ]
            )
        ]

        let requests = [
            RequestItem(
                id: "r1",
                title: "Custom challenge length",
                body: "Let me pick any number of days, not just 3 / 7 / 14.",
                kind: .feature,
                status: .planned,
                author: leo,
                ago: "3d ago",
                comments: 12,
                votes: 83
            ),
            RequestItem(
                id: "r2",
                title: "Team fights, 2 v 2",
                body: "Me and my wife against another couple. Scores add up per team.",
                kind: .feature,
                status: .open,
                author: nina,
                ago: "5d ago",
                comments: 9,
                votes: 71
            ),
            RequestItem(
                id: "r3",
                title: "Strava ride counted twice",
                body: "A ride synced from both Apple Health and Strava and I got double minutes.",
                kind: .bug,
                status: .planned,
                author: theo,
                ago: "1d ago",
                comments: 7,
                votes: 62
            ),
            RequestItem(
                id: "r4",
                title: "Rest days that don’t break a streak",
                body: "One planned rest day per week should not reset the streak counter.",
                kind: .feature,
                status: .open,
                author: ivy,
                ago: "1w ago",
                comments: 5,
                votes: 48
            ),
            RequestItem(
                id: "r5",
                title: "Apple Watch live standings",
                body: "A complication showing my position without opening the phone.",
                kind: .feature,
                status: .open,
                author: sam,
                ago: "1w ago",
                comments: 3,
                votes: 39
            ),
            RequestItem(
                id: "r6",
                title: "Pot shows the old amount after someone joins",
                body: "Joined a fight, the pot on the card kept the pre-join number until I killed the app.",
                kind: .bug,
                status: .shipped,
                author: Person(id: "maya", name: "Maya", handle: "@maya.moves", initials: "MM", isYou: true),
                ago: "2w ago",
                comments: 4,
                votes: 26
            ),
            RequestItem(
                id: "r7",
                title: "Pause a fight when you’re ill",
                body: "Freeze the clock for everyone rather than forcing a forfeit.",
                kind: .feature,
                status: .open,
                author: leo,
                ago: "2w ago",
                comments: 8,
                votes: 22
            )
        ]

        return Bundle(
            you: you,
            people: [leo, sam, nina, theo, ivy],
            fights: fights,
            requests: requests,
            history: [
                HistoryItem(id: "weekend", name: "Weekend Step Duel", detail: "Ended Jul 13 · 1st of 2", net: 10, won: true)
            ]
        )
    }
}

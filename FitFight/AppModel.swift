import Foundation
import Supabase
import SwiftUI

enum MetricKind: String, Codable, Hashable {
    case steps

    var eyebrow: String {
        "Steps total"
    }

    var title: String {
        "Steps Total"
    }
}

enum FightStatus: String, Codable, Hashable {
    case live
    case invited
    case finished
}

struct Person: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var initials: String
    var isYou: Bool = false

    /// The design's cast photographs, cut out of the mocks into the asset catalogue.
    var photo: String { "Avatar-\(isYou ? "maya" : id)" }
}

extension FFAvatar {
    init(_ person: Person?, size: CGFloat = 24, selected: Bool = false, pending: Bool = false) {
        self.init(
            monogram: person?.initials ?? "?",
            size: size,
            selected: selected,
            photo: person?.photo,
            dimmed: pending
        )
    }
}

struct Standing: Codable, Identifiable, Hashable {
    var person: Person
    var score: Double
    var today: Double
    var invited: Bool = false

    var id: String { person.id }
}

struct DayScore: Codable, Identifiable, Hashable {
    var person: Person
    var value: Double

    var id: String { person.id }
}

struct FightDay: Codable, Identifiable, Hashable {
    var label: String
    var scores: [DayScore]

    var id: String { label }
}

struct Fight: Codable, Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var metric: MetricKind
    var lengthDays: Int
    var daysLeft: Int? = nil
    var endedLabel: String? = nil
    var actionText: String
    var status: FightStatus
    var rank: Int
    var of: Int
    var pending: Int
    var kickerPrefix: String = ""
    var kickerEmphasis: String
    var kickerRest: String = ""
    var listSubtitle: String
    var inviter: Person? = nil
    var invitePitch: String? = nil
    var inviteAction: String? = nil
    var paceNote: String? = nil
    var standingsMeta: String? = nil
    var standings: [Standing]
    var days: [FightDay] = []
    var windowStart: Date = Date()
    var windowEnd: Date = Date().addingTimeInterval(86400)

    var durationLabel: String {
        let hours = max(1, Int((windowEnd.timeIntervalSince(windowStart) / 3_600).rounded()))
        if hours <= 6 {
            return "\(hours) \(hours == 1 ? "hour" : "hours")"
        }
        return "\(lengthDays) \(lengthDays == 1 ? "day" : "days")"
    }
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
    @Published var joined: Set<String> = []
    @Published var createError: String?
    @Published private(set) var isCreatingFight = false
    @Published private(set) var isRefreshingFights = false

    @Published var you: Person
    @Published var fights: [Fight]

    private var session: SessionStore?
    private let api = FitFightAPI()
    private var inviteTokens: [String: String] = [:]
    private var cachedUserID: UUID?

    private static let fightsCachePrefix = "fitfight.fights."

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
        if fixtures {
            fights = bundle.fights
        } else {
            fights = []
        }
    }

    func fight(id: String) -> Fight? {
        fights.first { $0.id == id }
    }

    var live: [Fight] { fights.filter { $0.status == .live } }
    var invitations: [Fight] { fights.filter { $0.status == .invited } }
    var finished: [Fight] { fights.filter { $0.status == .finished } }

    func youStanding(in fight: Fight) -> Standing? {
        fight.standings.first { $0.person.isYou }
    }

    func formatScore(_ value: Double, metric _: MetricKind) -> String {
        if value >= 1000 {
            return String(format: "%.1fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }

    func formatDelta(_ value: Double, metric: MetricKind) -> String {
        let body = formatScore(value, metric: metric)
        if value > 0 { return "+\(body)" }
        if value < 0 { return "−\(body)" }
        return body
    }

    func refreshFromServer() async {
        guard let session else { return }
        await refreshFromServer(session: session)
    }

    func restoreCachedFights(session: SessionStore) {
        guard let userID = session.authSession?.user.id ?? session.client.auth.currentUser?.id else {
            cachedUserID = nil
            fights = []
            return
        }
        guard cachedUserID != userID else { return }
        cachedUserID = userID
        guard
            let data = UserDefaults.standard.data(forKey: Self.fightsCachePrefix + userID.uuidString),
            let cached = try? JSONDecoder().decode([Fight].self, from: data)
        else {
            fights = []
            return
        }
        fights = cached
    }

    func refreshFights(session: SessionStore, steps: HealthKitStepsStore) async {
        guard !isRefreshingFights else { return }
        isRefreshingFights = true
        defer { isRefreshingFights = false }

        await steps.refresh(requestAccess: false)
        if session.authSession != nil {
            await steps.syncToBackend(session: session)
        }
        await refreshFromServer(session: session)
    }

    func removeCachedFights(for userID: UUID) {
        UserDefaults.standard.removeObject(forKey: Self.fightsCachePrefix + userID.uuidString)
        if cachedUserID == userID {
            cachedUserID = nil
            fights = []
        }
    }

    func refreshFromServer(session: SessionStore) async {
        self.session = session
        guard let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id else {
            return
        }
        if let profile = session.profile {
            you = Self.person(from: profile, isYou: true)
        }

        if let token = session.authSession?.accessToken, api.isConfigured {
            _ = try? await api.syncDueFights(accessToken: token)
        }

        do {
            var loaded = try await loadFights(client: session.client, userId: userId)
            loaded = try await populateStepDays(loaded, client: session.client)
            guard session.authSession?.user.id == userId else { return }
            fights = loaded
            cachedUserID = userId
            if let data = try? JSONEncoder().encode(loaded) {
                UserDefaults.standard.set(data, forKey: Self.fightsCachePrefix + userId.uuidString)
            }
        } catch {
            // Keep the last successful result visible while the phone is offline.
        }
    }

    /// Locks Start fight immediately so extra taps cannot insert another row.
    func beginCreateFight() -> Bool {
        guard !isCreatingFight else { return false }
        isCreatingFight = true
        createError = nil
        return true
    }

    func createAndStartFight(
        name: String = "Steps Fight",
        startsAt: Date,
        endsAt: Date,
        actionText: String,
        inviteHandles: [String]
    ) async {
        if !isCreatingFight {
            isCreatingFight = true
        }
        defer { isCreatingFight = false }
        createError = nil
        guard session?.authSession?.accessToken != nil else {
            createError = "Sign in to start a fight."
            return
        }
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            createError = "Add the action the loser will do."
            return
        }
        guard action.count <= 120 else {
            createError = "Keep the action to 120 characters."
            return
        }

        let payload = FitFightCreateFight(
            name: name,
            startsAt: startsAt,
            endsAt: max(endsAt, startsAt.addingTimeInterval(60)),
            timeZone: TimeZone.current.identifier,
            outcomeRule: "highest_total",
            goalPolicy: "shared",
            defaultGoalValue: nil,
            stakeKind: "action",
            stakeMinor: nil,
            currency: nil,
            actionText: action,
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

    func declineFight(id: String) async {
        createError = nil
        guard let session, let userId = session.authSession?.user.id, let fightID = UUID(uuidString: id) else {
            createError = "Sign in to decline this fight."
            return
        }
        do {
            try await session.client.from("fight_members")
                .update(MemberDeclineUpdate(state: "declined"))
                .eq("fight_id", value: fightID)
                .eq("user_id", value: userId)
                .execute()
            await refreshFromServer()
        } catch {
            createError = (error as? LocalizedError)?.errorDescription ?? "Couldn’t decline."
        }
    }

    private func createFightOnClient(
        _ payload: FitFightCreateFight,
        inviteHandles: [String]
    ) async throws {
        guard let session, let userId = session.authSession?.user.id else {
            throw LiveFightError.notSignedIn
        }

        let handles = inviteHandles.reduce(into: [String]()) { result, raw in
            let handle = SessionStore.strippedHandle(raw)
            if SessionStore.isValidHandle(handle), !result.contains(handle) {
                result.append(handle)
            }
        }
        guard !handles.isEmpty else { throw LiveFightError.noOpponents }

        let found: [FitFightProfile] = try await session.client.from("profiles")
            .select("user_id, handle, display_name")
            .in("handle", values: handles)
            .execute()
            .value
        if let missing = handles.first(where: { want in !found.contains { $0.handle == want } }) {
            throw LiveFightError.unknownHandle(missing)
        }
        let inviteIds = found.map(\.userId).filter { $0 != userId }
        guard !inviteIds.isEmpty else { throw LiveFightError.noOpponents }

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

    private func populateStepDays(
        _ fights: [Fight],
        client: SupabaseClient
    ) async throws -> [Fight] {
        let ids = fights.flatMap { fight in
            fight.standings.compactMap { UUID(uuidString: $0.person.id) }
        }
        guard !ids.isEmpty else { return fights }
        let requestedDays = fights.flatMap { Self.fightDayWindow($0) }
        guard let firstDay = requestedDays.min(), let lastDay = requestedDays.max() else {
            return fights
        }

        let days: [StepDayRow]
        do {
            days = try await client.from("step_days")
                .select("user_id, day, steps")
                .in("user_id", values: ids.map(\.uuidString))
                .gte("day", value: firstDay)
                .lte("day", value: lastDay)
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
                standing.today = Double(mine.first { $0.day == today }?.steps ?? 0)
                return standing
            }
            next.standings = people
            next.days = Self.dayCards(from: days, standings: people, window: window)
            updated.append(next)
        }
        return updated
    }

    private static func fightDayWindow(_ fight: Fight) -> Set<String> {
        let calendar = Calendar.current
        var days: [String] = []
        var cursor = calendar.startOfDay(for: fight.windowStart)
        while cursor < fight.windowEnd && days.count <= 40 {
            days.append(dayStamp(cursor))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
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

    private func loadFights(client: SupabaseClient, userId: UUID) async throws -> [Fight] {
        let memberSelect = "fight_id, user_id, state, current_value, rank, final_value"
        let fightSelect = "id, owner_id, name, state, starts_at, ends_at, action_text"

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

    private static func mapFight(
        _ row: FightRow,
        members: [MemberRow],
        mine: MemberRow?,
        profiles: [UUID: FitFightProfile],
        userId: UUID,
        formatScore: (Double, MetricKind) -> String
    ) -> Fight? {
        if row.state == "draft" || mine?.state == "declined" { return nil }

        let pendingMembers = members.filter { $0.state == "invited" }

        let starts = row.startsAtDate
        let ends = row.endsAtDate
        let lengthDays = max(1, Calendar.current.dateComponents([.day], from: starts, to: ends).day ?? 1)
        let lengthHours = max(1, Int((ends.timeIntervalSince(starts) / 3_600).rounded()))
        let durationLabel = lengthHours <= 6
            ? "\(lengthHours) \(lengthHours == 1 ? "hour" : "hours")"
            : "\(lengthDays) \(lengthDays == 1 ? "day" : "days")"

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
        let remainingLabel = lengthHours <= 6
            ? "\(max(1, Int(ceil(ends.timeIntervalSinceNow / 3_600))))h"
            : "\(daysLeft ?? 0)d"

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
            return Standing(
                person: person,
                score: score,
                today: 0,
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

        let actionText = row.actionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText?.isEmpty == false ? (actionText ?? "") : "No action was set for this older fight."

        var kickerPrefix = ""
        var kickerEmphasis = ""
        var kickerRest = ""
        var listSubtitle = ""
        var invitePitch: String?
        var inviteAction: String?
        var endedLabel: String?

        switch status {
        case .invited:
            invitePitch = "\(ownerName) challenged you"
            inviteAction = "Accept"
            kickerEmphasis = invitePitch ?? ""
            listSubtitle = "\(ownerName) · \(durationLabel)"
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
                    kickerRest = "with \(remainingLabel) to go"
                    listSubtitle = "Holding 1st with \(remainingLabel) to go"
                } else {
                    let gap = leader.score - youRow.score
                    kickerEmphasis = formatScore(max(0, gap), .steps)
                    kickerRest = "behind \(leader.person.name)"
                    listSubtitle = "\(kickerEmphasis) behind \(leader.person.name)"
                }
            } else {
                kickerEmphasis = "\(remainingLabel) left"
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
            actionText: action,
            status: status,
            rank: rank,
            of: of,
            pending: pendingMembers.count,
            kickerPrefix: kickerPrefix,
            kickerEmphasis: kickerEmphasis,
            kickerRest: kickerRest,
            listSubtitle: listSubtitle,
            inviter: owner,
            invitePitch: invitePitch,
            inviteAction: inviteAction,
            standingsMeta: nil,
            standings: people,
            windowStart: starts,
            windowEnd: ends
        )
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
    case noOpponents
    case unknownHandle(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Sign in to start a fight."
        case .noOpponents:
            return "Add at least one other username."
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

private struct MemberDeclineUpdate: Encodable {
    let state: String
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
    let actionText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case ownerId = "owner_id"
        case name
        case state
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case actionText = "action_text"
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
    let finalValue: Double?

    enum CodingKeys: String, CodingKey {
        case fightId = "fight_id"
        case userId = "user_id"
        case state
        case currentValue = "current_value"
        case rank
        case finalValue = "final_value"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fightId = try container.decode(UUID.self, forKey: .fightId)
        userId = try container.decode(UUID.self, forKey: .userId)
        state = try container.decode(String.self, forKey: .state)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        currentValue = Self.number(container, .currentValue)
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
        var fights: [Fight]
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
                metric: .steps,
                lengthDays: 7,
                daysLeft: 4,
                actionText: "Loser plans the next walk",
                status: .live,
                rank: 2,
                of: 3,
                pending: 0,
                kickerEmphasis: "12.0k",
                kickerRest: "behind Leo",
                listSubtitle: "12.0k behind Leo",
                standings: [
                    Standing(person: leo, score: 54_000, today: 16_000),
                    Standing(person: you, score: 42_000, today: 14_000),
                    Standing(person: sam, score: 37_000, today: 12_000)
                ],
                days: [
                    FightDay(label: "Day 1", scores: [
                        DayScore(person: leo, value: 20_000),
                        DayScore(person: you, value: 12_000),
                        DayScore(person: sam, value: 15_000)
                    ]),
                    FightDay(label: "Day 2", scores: [
                        DayScore(person: leo, value: 18_000),
                        DayScore(person: you, value: 16_000),
                        DayScore(person: sam, value: 10_000)
                    ]),
                    FightDay(label: "Day 3", scores: [
                        DayScore(person: leo, value: 16_000),
                        DayScore(person: you, value: 14_000),
                        DayScore(person: sam, value: 12_000)
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
                actionText: "Losers cook Sunday dinner",
                status: .live,
                rank: 1,
                of: 5,
                pending: 1,
                kickerPrefix: "Holding",
                kickerEmphasis: "1st",
                kickerRest: "with 2d to go",
                listSubtitle: "Holding 1st with 2d to go",
                standings: [
                    Standing(person: you, score: 61400, today: 8200),
                    Standing(person: ivy, score: 59800, today: 6100),
                    Standing(person: theo, score: 55200, today: 5200),
                    Standing(person: leo, score: 40100, today: 4800),
                    Standing(person: nina, score: 22000, today: 0, invited: true)
                ]
            ),
            Fight(
                id: "club",
                code: "FIGHT-655",
                name: "10K Club",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 3,
                actionText: "Losers organize the next hike",
                status: .live,
                rank: 2,
                of: 4,
                pending: 2,
                kickerEmphasis: "3.2k steps",
                kickerRest: "behind Sam",
                listSubtitle: "3.2k steps behind Sam",
                standings: [
                    Standing(person: sam, score: 44800, today: 12100),
                    Standing(person: you, score: 41600, today: 8240),
                    Standing(person: nina, score: 31900, today: 4100),
                    Standing(person: ivy, score: 28100, today: 3900)
                ]
            ),
            Fight(
                id: "desk",
                code: "FIGHT-556",
                name: "Desk Job Revenge",
                metric: .steps,
                lengthDays: 5,
                daysLeft: 5,
                actionText: "Losers take the stairs all day",
                status: .invited,
                rank: 0,
                of: 4,
                pending: 2,
                kickerEmphasis: "Theo challenged you",
                listSubtitle: "Theo · 5 days",
                inviter: theo,
                invitePitch: "Theo challenged you",
                inviteAction: "Accept",
                standingsMeta: "2 in · 2 not replied",
                standings: [
                    Standing(person: theo, score: 0, today: 0),
                    Standing(person: nina, score: 0, today: 0),
                    Standing(person: ivy, score: 0, today: 0, invited: true)
                ]
            ),
            Fight(
                id: "sprint",
                code: "FIGHT-221",
                name: "City Sprint",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 7,
                actionText: "Losers plan a park walk",
                status: .invited,
                rank: 0,
                of: 3,
                pending: 0,
                kickerEmphasis: "Ivy challenged you",
                listSubtitle: "Ivy · 7 days",
                inviter: ivy,
                invitePitch: "Ivy challenged you",
                inviteAction: "Join",
                standings: [
                    Standing(person: ivy, score: 0, today: 0)
                ]
            ),
            Fight(
                id: "weekend",
                code: "FIGHT-088",
                name: "Weekend Step Duel",
                metric: .steps,
                lengthDays: 2,
                endedLabel: "Ended Jul 13",
                actionText: "Loser plans the next route",
                status: .finished,
                rank: 1,
                of: 2,
                pending: 0,
                kickerPrefix: "Leading by",
                kickerEmphasis: "2.2k steps",
                listSubtitle: "Ended Jul 13 · 1st of 2",
                standingsMeta: "2 in",
                standings: [
                    Standing(person: you, score: 24100, today: 0),
                    Standing(person: leo, score: 21900, today: 0)
                ]
            )
        ]

        return Bundle(
            you: you,
            fights: fights
        )
    }
}

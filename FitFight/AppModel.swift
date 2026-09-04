import Foundation
import Supabase
import SwiftUI

enum MetricKind: String, Codable, Hashable {
    case steps

    var eyebrow: String {
        String(localized: "Steps total")
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
    var invited: Bool = false
    var lastSyncedAt: Date? = nil
    var finalStepsComplete: Bool? = nil

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
    var serverState: String? = nil

    var durationLabel: String {
        let hours = max(1, Int((windowEnd.timeIntervalSince(windowStart) / 3_600).rounded()))
        return localizedDuration(hours: hours, days: lengthDays)
    }

    /// Short test fights count in hours; a day count would round them away.
    var timeLeftLabel: String {
        let durationHours = windowEnd.timeIntervalSince(windowStart) / 3_600
        if durationHours <= 6, daysLeft != nil {
            let hours = max(1, Int(ceil(windowEnd.timeIntervalSinceNow / 3_600)))
            return String(
                localized: "fight.hours-left",
                defaultValue: "\(hours) hours left"
            )
        }
        if let daysLeft {
            return String(
                localized: "fight.days-left",
                defaultValue: "\(daysLeft) days left"
            )
        }
        return endedLabel ?? String(localized: "Ended")
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
    @Published var showingRequests = false
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

    private static var fightsCachePrefix: String {
        "fitfight.fights.\(Bundle.main.preferredLocalizations.first ?? "en")."
    }

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
        value.formatted(
            .number
                .notation(.compactName)
                .precision(.fractionLength(value >= 1_000 ? 0...1 : 0...0))
        )
    }

    func formatLastSync(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return String(localized: "Not synced yet") }
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return String(localized: "Just now") }
        if elapsed < 3_600 {
            let minutes = Int(elapsed / 60)
            return String(localized: "health.minutes-ago", defaultValue: "\(minutes) minutes ago")
        }
        if elapsed < 86_400 {
            let hours = Int(elapsed / 3_600)
            return String(localized: "health.hours-ago", defaultValue: "\(hours) hours ago")
        }
        let days = Int(elapsed / 86_400)
        return String(localized: "health.days-ago", defaultValue: "\(days) days ago")
    }

    func formatStandingFreshness(_ standing: Standing, fight: Fight, now: Date) -> String {
        guard fight.windowEnd <= now else { return formatLastSync(standing.lastSyncedAt, now: now) }
        if standing.finalStepsComplete == true {
            guard let lastSyncedAt = standing.lastSyncedAt else {
                return String(localized: "Final steps synced")
            }
            let freshness = formatLastSync(lastSyncedAt, now: now)
            return String(
                localized: "health.final-steps-synced-at",
                defaultValue: "Final steps synced · \(freshness)"
            )
        }
        let finalized = fight.serverState == "final" || fight.serverState == "cancelled"
        if let lastSyncedAt = standing.lastSyncedAt {
            let freshness = formatLastSync(lastSyncedAt, now: now)
            return finalized
                ? String(
                    localized: "health.finalized-last-steps-at",
                    defaultValue: "Finalized from last available steps · \(freshness)"
                )
                : String(
                    localized: "health.waiting-final-steps-at",
                    defaultValue: "Waiting for final steps · \(freshness)"
                )
        }
        return finalized
            ? String(localized: "Finalized without synced steps")
            : String(localized: "Waiting for first sync")
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
            await steps.syncToBackend(session: session, trigger: .foreground)
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
        name: String = String(localized: "Steps Fight"),
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
            createError = String(localized: "Sign in to start a fight.")
            return
        }
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !action.isEmpty else {
            createError = String(localized: "Add the action the loser will do.")
            return
        }
        guard action.count <= 120 else {
            createError = String(localized: "Keep the action to 120 characters.")
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
            createError = (error as? LiveFightError)?.errorDescription
                ?? (error as? FitFightAPIError)?.errorDescription
                ?? String(localized: "Couldn’t start the fight.")
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
                createError = (error as? FitFightAPIError)?.errorDescription
                    ?? String(localized: "Couldn’t accept.")
            }
            return
        }
        guard let session, let userId = session.authSession?.user.id, let fightID = UUID(uuidString: id) else {
            createError = String(localized: "Sign in to accept this fight.")
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
            createError = String(localized: "Couldn’t accept.")
        }
    }

    func declineFight(id: String) async {
        createError = nil
        guard let session, let userId = session.authSession?.user.id, let fightID = UUID(uuidString: id) else {
            createError = String(localized: "Sign in to decline this fight.")
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
            createError = String(localized: "Couldn’t decline.")
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

        var updated: [Fight] = []
        updated.reserveCapacity(fights.count)
        for fight in fights {
            var next = fight
            let window = Self.fightDayWindow(fight)
            next.days = Self.dayCards(from: days, standings: fight.standings, window: window)
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
        label.locale = .autoupdatingCurrent
        label.setLocalizedDateFormatFromTemplate("EEEdMMM")
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
        let memberSelect = "fight_id, user_id, state, current_value, rank, final_value, last_synced_at, final_steps_complete"
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
            name: profile.atHandle,
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
        let durationLabel = localizedDuration(hours: lengthHours, days: lengthDays)

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
            let remaining = Calendar.current.dateComponents([.day, .hour, .minute, .second], from: Date(), to: ends)
            let hasPartialDay = (remaining.hour ?? 0) > 0
                || (remaining.minute ?? 0) > 0
                || (remaining.second ?? 0) > 0
            daysLeft = max(1, (remaining.day ?? 0) + (hasPartialDay ? 1 : 0))
        }
        let remainingLabel = localizedDuration(
            hours: max(1, Int(ceil(ends.timeIntervalSinceNow / 3_600))),
            days: daysLeft ?? 0
        )

        let people = members.map { member -> Standing in
            let profile = profiles[member.userId]
            let person: Person
            if let profile {
                person = Self.person(from: profile, isYou: member.userId == userId)
            } else {
                person = Person(
                    id: member.userId.uuidString,
                    name: member.userId == userId ? String(localized: "You") : "@user",
                    handle: "@user",
                    initials: "FF",
                    isYou: member.userId == userId
                )
            }
            let score = member.currentValue ?? member.finalValue ?? 0
            return Standing(
                person: person,
                score: score,
                invited: member.state == "invited",
                lastSyncedAt: member.lastSyncedAt,
                finalStepsComplete: member.finalStepsComplete
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
        let ownerName = owner?.name ?? String(localized: "Someone")

        let actionText = row.actionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText?.isEmpty == false
            ? (actionText ?? "")
            : String(localized: "No action was set for this older fight.")

        var kickerPrefix = ""
        var kickerEmphasis = ""
        var kickerRest = ""
        var listSubtitle = ""
        var invitePitch: String?
        var inviteAction: String?
        var endedLabel: String?

        switch status {
        case .invited:
            invitePitch = String(
                localized: "fight.challenged-you",
                defaultValue: "\(ownerName) challenged you"
            )
            inviteAction = String(localized: "Accept")
            kickerEmphasis = invitePitch ?? ""
            listSubtitle = "\(ownerName) · \(durationLabel)"
        case .finished:
            let formatter = DateFormatter()
            formatter.locale = .autoupdatingCurrent
            formatter.setLocalizedDateFormatFromTemplate("MMMd")
            endedLabel = String(
                localized: "fight.ended-on",
                defaultValue: "Ended \(formatter.string(from: ends))"
            )
            listSubtitle = String(
                localized: "fight.finished-position",
                defaultValue: "\(endedLabel ?? String(localized: "Ended")) · \(Self.ordinal(rank)) of \(of)"
            )
            kickerPrefix = rank == 1 ? String(localized: "Won by") : String(localized: "Finished")
            kickerEmphasis = Self.ordinal(rank)
        case .live:
            if row.state == "awaiting_final_sync" {
                kickerEmphasis = String(localized: "Syncing final steps")
                listSubtitle = kickerEmphasis
            } else if let youRow, let leader = joined.first, !youRow.invited {
                if youRow.person.id == leader.person.id, let runnerUp = joined.dropFirst().first {
                    let gap = leader.score - runnerUp.score
                    kickerPrefix = gap == 0 ? "" : String(localized: "Leading by")
                    kickerEmphasis = gap == 0
                        ? String(localized: "Tied")
                        : String(
                            localized: "fight.steps-value",
                            defaultValue: "\(formatScore(gap, .steps)) steps"
                        )
                    kickerRest = String(
                        localized: "fight.time-to-go",
                        defaultValue: "with \(remainingLabel) to go"
                    )
                    listSubtitle = gap == 0
                        ? String(
                            localized: "fight.tied-time-to-go",
                            defaultValue: "Tied with \(remainingLabel) to go"
                        )
                        : String(
                            localized: "fight.leading-time-to-go",
                            defaultValue: "Leading by \(kickerEmphasis) with \(remainingLabel) to go"
                        )
                } else if youRow.person.id == leader.person.id {
                    kickerEmphasis = String(
                        localized: "fight.time-left",
                        defaultValue: "\(remainingLabel) left"
                    )
                    listSubtitle = kickerEmphasis
                } else {
                    let gap = leader.score - youRow.score
                    kickerEmphasis = gap == 0
                        ? String(localized: "Tied")
                        : String(
                            localized: "fight.steps-value",
                            defaultValue: "\(formatScore(gap, .steps)) steps"
                        )
                    kickerRest = gap == 0
                        ? ""
                        : String(
                            localized: "fight.behind-person",
                            defaultValue: "behind \(leader.person.name)"
                        )
                    listSubtitle = gap == 0
                        ? String(localized: "Tied")
                        : String(
                            localized: "fight.steps-behind-person",
                            defaultValue: "\(kickerEmphasis) behind \(leader.person.name)"
                        )
                }
            } else {
                kickerEmphasis = String(
                    localized: "fight.time-left",
                    defaultValue: "\(remainingLabel) left"
                )
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
            windowEnd: ends,
            serverState: row.state
        )
    }

    private static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? value.formatted()
    }
}

enum LiveFightError: LocalizedError {
    case notSignedIn
    case noOpponents
    case unknownHandle(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return String(localized: "Sign in to start a fight.")
        case .noOpponents:
            return String(localized: "Add at least one other username.")
        case .unknownHandle(let handle):
            return String(
                localized: "fight.unknown-handle",
                defaultValue: "No one with @\(handle). They need to open the app and pick a username first."
            )
        }
    }
}

private func localizedDuration(hours: Int, days: Int) -> String {
    if hours <= 6 {
        return String(
            localized: "duration.hours",
            defaultValue: "\(hours) hours"
        )
    }
    return String(
        localized: "duration.days",
        defaultValue: "\(days) days"
    )
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

    fileprivate static func parse(_ raw: String) -> Date? {
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
    let lastSyncedAt: Date?
    let finalStepsComplete: Bool?

    enum CodingKeys: String, CodingKey {
        case fightId = "fight_id"
        case userId = "user_id"
        case state
        case currentValue = "current_value"
        case rank
        case finalValue = "final_value"
        case lastSyncedAt = "last_synced_at"
        case finalStepsComplete = "final_steps_complete"
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

private enum AppModelFixtures {
    struct Bundle {
        var you: Person
        var fights: [Fight]
    }

    static func load() -> Bundle {
        let isFrench = Foundation.Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true
        let leo = Person(id: "leo", name: "@leo_runs", handle: "@leo_runs", initials: "L")
        let sam = Person(id: "sam", name: "@sam_sweats", handle: "@sam_sweats", initials: "S")
        let ivy = Person(id: "ivy", name: "@ivy_climbs", handle: "@ivy_climbs", initials: "I")
        let theo = Person(id: "theo", name: "@theo_rows", handle: "@theo_rows", initials: "T")
        let nina = Person(id: "nina", name: "@nina_lifts", handle: "@nina_lifts", initials: "N")
        let you = Person(id: "you", name: "@maya_moves", handle: "@maya_moves", initials: "MM", isYou: true)
        let syncedJustNow = Date().addingTimeInterval(-4 * 60)
        let syncedToday = Date().addingTimeInterval(-2 * 3_600)
        let syncedYesterday = Date().addingTimeInterval(-22 * 3_600)

        let fights = [
            Fight(
                id: "sweat",
                code: "FIGHT-742",
                name: isFrench ? "Défi transpiration 7 jours" : "7-Day Sweat Ladder",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 4,
                actionText: isFrench ? "Le perdant organise la prochaine balade" : "Loser plans the next walk",
                status: .live,
                rank: 2,
                of: 3,
                pending: 0,
                kickerEmphasis: "12.0k",
                kickerRest: String(localized: "behind @leo_runs"),
                listSubtitle: String(localized: "12.0k behind @leo_runs"),
                standings: [
                    Standing(person: leo, score: 54_000, lastSyncedAt: syncedJustNow),
                    Standing(person: you, score: 42_000, lastSyncedAt: syncedToday),
                    Standing(person: sam, score: 37_000, lastSyncedAt: syncedYesterday)
                ],
                days: [
                    FightDay(label: String(localized: "Day 1"), scores: [
                        DayScore(person: leo, value: 20_000),
                        DayScore(person: you, value: 12_000),
                        DayScore(person: sam, value: 15_000)
                    ]),
                    FightDay(label: String(localized: "Day 2"), scores: [
                        DayScore(person: leo, value: 18_000),
                        DayScore(person: you, value: 16_000),
                        DayScore(person: sam, value: 10_000)
                    ]),
                    FightDay(label: String(localized: "Day 3"), scores: [
                        DayScore(person: leo, value: 16_000),
                        DayScore(person: you, value: 14_000),
                        DayScore(person: sam, value: 12_000)
                    ])
                ]
            ),
            Fight(
                id: "derby",
                code: "FIGHT-118",
                name: isFrench ? "Derby des pas" : "Step Derby",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 2,
                actionText: isFrench ? "Les perdants préparent le dîner dimanche" : "Losers cook Sunday dinner",
                status: .live,
                rank: 1,
                of: 5,
                pending: 1,
                kickerPrefix: String(localized: "Holding"),
                kickerEmphasis: String(localized: "1st"),
                kickerRest: String(localized: "with 2d to go"),
                listSubtitle: String(localized: "Holding 1st with 2d to go"),
                standings: [
                    Standing(person: you, score: 61400, lastSyncedAt: syncedJustNow),
                    Standing(person: ivy, score: 59800, lastSyncedAt: syncedToday),
                    Standing(person: theo, score: 55200, lastSyncedAt: syncedYesterday),
                    Standing(person: leo, score: 40100, lastSyncedAt: syncedYesterday),
                    Standing(person: nina, score: 22000, invited: true)
                ]
            ),
            Fight(
                id: "club",
                code: "FIGHT-655",
                name: isFrench ? "Club des 10 000" : "10K Club",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 3,
                actionText: isFrench ? "Les perdants organisent la prochaine randonnée" : "Losers organize the next hike",
                status: .live,
                rank: 2,
                of: 4,
                pending: 2,
                kickerEmphasis: String(localized: "3.2k steps"),
                kickerRest: String(localized: "behind @sam_sweats"),
                listSubtitle: String(localized: "3.2k steps behind @sam_sweats"),
                standings: [
                    Standing(person: sam, score: 44800, lastSyncedAt: syncedToday),
                    Standing(person: you, score: 41600, lastSyncedAt: syncedJustNow),
                    Standing(person: nina, score: 31900, lastSyncedAt: syncedYesterday),
                    Standing(person: ivy, score: 28100, lastSyncedAt: syncedYesterday)
                ]
            ),
            Fight(
                id: "desk",
                code: "FIGHT-556",
                name: isFrench ? "Revanche du bureau" : "Desk Job Revenge",
                metric: .steps,
                lengthDays: 3,
                daysLeft: 3,
                actionText: isFrench ? "Les perdants prennent les escaliers toute la journée" : "Losers take the stairs all day",
                status: .invited,
                rank: 0,
                of: 4,
                pending: 2,
                kickerEmphasis: String(localized: "@theo_rows challenged you"),
                listSubtitle: String(localized: "@theo_rows · 3 days"),
                inviter: theo,
                invitePitch: String(localized: "@theo_rows challenged you"),
                inviteAction: String(localized: "Accept"),
                standingsMeta: String(localized: "2 in · 2 not replied"),
                standings: [
                    Standing(person: theo, score: 0),
                    Standing(person: nina, score: 0),
                    Standing(person: ivy, score: 0, invited: true)
                ]
            ),
            Fight(
                id: "sprint",
                code: "FIGHT-221",
                name: isFrench ? "Sprint en ville" : "City Sprint",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 7,
                actionText: isFrench ? "Les perdants organisent une balade au parc" : "Losers plan a park walk",
                status: .invited,
                rank: 0,
                of: 3,
                pending: 0,
                kickerEmphasis: String(localized: "@ivy_climbs challenged you"),
                listSubtitle: String(localized: "@ivy_climbs · 7 days"),
                inviter: ivy,
                invitePitch: String(localized: "@ivy_climbs challenged you"),
                inviteAction: String(localized: "Join"),
                standings: [
                    Standing(person: ivy, score: 0)
                ]
            ),
            Fight(
                id: "weekend",
                code: "FIGHT-088",
                name: isFrench ? "Duel de pas du week-end" : "Weekend Step Duel",
                metric: .steps,
                lengthDays: 2,
                endedLabel: String(localized: "Ended Jul 13"),
                actionText: isFrench ? "Le perdant choisit le prochain parcours" : "Loser plans the next route",
                status: .finished,
                rank: 1,
                of: 2,
                pending: 0,
                kickerPrefix: String(localized: "Leading by"),
                kickerEmphasis: String(localized: "2.2k steps"),
                listSubtitle: String(localized: "Ended Jul 13 · 1st of 2"),
                standingsMeta: String(localized: "2 in"),
                standings: [
                    Standing(person: you, score: 24100, lastSyncedAt: syncedYesterday),
                    Standing(person: leo, score: 21900, lastSyncedAt: syncedYesterday)
                ]
            )
        ]

        return Bundle(
            you: you,
            fights: fights
        )
    }
}

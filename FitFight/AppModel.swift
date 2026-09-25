import Foundation
import SwiftUI

enum MetricKind: String, Codable, Hashable {
    case steps
}

enum FightStatus: String, Codable, Hashable {
    case live
    case invited
    case pending
    case finished
}

enum FightRefreshPhase: Equatable {
    case idle
    case readingHealth
    case uploading
    case updatingFights

    func statusText(line: Int) -> String {
        let lines: [String]
        switch self {
        case .idle:
            return ""
        case .readingHealth:
            lines = [
                String(appLocalized: "Syncing your step activity…"),
                String(appLocalized: "Asking Apple Health how far you walked…"),
            ]
        case .uploading:
            lines = [
                String(appLocalized: "Updating the database…"),
                String(appLocalized: "Filing your steps where they belong…"),
            ]
        case .updatingFights:
            lines = [
                String(appLocalized: "Updating the challenges…"),
                String(appLocalized: "Counting how far you are from your friend…"),
                String(appLocalized: "Checking whether you’re still ahead…"),
            ]
        }
        return lines[line % lines.count]
    }
}

struct Person: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var initials: String
    var isYou: Bool = false
    var photoURL: URL? = nil
    var companionId: String? = nil
}

struct Standing: Codable, Identifiable, Hashable {
    var person: Person
    var score: Double
    var invited: Bool = false
    var deferred: Bool = false
    var lastSyncedAt: Date? = nil
    var finalStepsComplete: Bool? = nil
    var rank: Int? = nil

    var id: String { person.id }
}

struct DayScore: Codable, Identifiable, Hashable {
    var person: Person
    var value: Double
    var hasData: Bool = true

    var id: String { person.id }
}

struct FightDay: Codable, Identifiable, Hashable {
    var label: String
    var scores: [DayScore]

    var id: String { label }
}

struct Fight: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var metric: MetricKind
    var lengthDays: Int
    var daysLeft: Int? = nil
    var endedLabel: String? = nil
    var actionText: String
    var status: FightStatus
    var rank: Int
    var of: Int
    var kickerEmphasis: String
    var listSubtitle: String
    var inviter: Person? = nil
    var invitePitch: String? = nil
    var standingsMeta: String? = nil
    var standings: [Standing]
    var days: [FightDay] = []
    var windowStart: Date = Date()
    var windowEnd: Date = Date().addingTimeInterval(86400)
    var graceEndsAt: Date? = nil
    var serverState: String? = nil
    var joinCode: String? = nil
    var seriesId: String? = nil
    var recurring: Bool = false
    var visibility: String = "invite_only"
    var suggested: Bool = false
    var pendingJoin: Bool = false
    var offersJoinNext: Bool = false
    var timeZone: String? = nil

    var hasAction: Bool {
        !actionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Title shown on Fights. A typed name wins; otherwise the action; otherwise the stored name.
    var listTitle: String {
        Self.displayTitle(name: name, actionText: actionText)
    }

    static func displayTitle(name: String, actionText: String?) -> String {
        let stored = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if stored.isEmpty || stored == "Steps Fight" || stored == "Défi de pas" {
            return action.isEmpty ? (stored.isEmpty ? String(appLocalized: "Steps Fight") : stored) : action
        }
        return stored
    }

    var isTiedForFirst: Bool {
        standings.filter { !$0.invited && !$0.deferred && $0.rank == 1 }.count > 1
    }

    var durationLabel: String {
        let hours = max(1, Int((windowEnd.timeIntervalSince(windowStart) / 3_600).rounded()))
        return localizedDuration(hours: hours, days: lengthDays)
    }

    var timeLeftLabel: String {
        if isUpcoming {
            return String(appLocalized: "fight.starts-at", defaultValue: "Starts \(Self.deadlineStamp(windowStart))")
        }
        if hasPassedDeadline {
            return deadlineLabel
        }
        let remaining = RemainingTime.phrase(until: windowEnd)
        return String(
            appLocalized: "fight.time-left",
            defaultValue: "\(remaining) left"
        )
    }

    var isUpcoming: Bool { serverState == "scheduled" && windowStart > Date() }

    var canOwnerEdit: Bool {
        inviter?.isYou == true && (status == .live || isUpcoming)
    }

    /// Exact stored cutoff, in the phone’s local date and time.
    var deadlineLabel: String {
        let stamp = Self.deadlineStamp(windowEnd)
        if hasPassedDeadline {
            return endedLabel ?? String(
                appLocalized: "fight.ended-on",
                defaultValue: "Ended \(stamp)"
            )
        }
        return String(
            appLocalized: "fight.ends-at",
            defaultValue: "Ends \(stamp)"
        )
    }

    var timeAndDeadlineLabel: String {
        hasPassedDeadline ? deadlineLabel : "\(timeLeftLabel) · \(deadlineLabel)"
    }

    private var hasPassedDeadline: Bool {
        daysLeft == nil || status == .finished || status == .pending || windowEnd <= Date()
    }

    static func deadlineStamp(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(AppLocalization.locale))
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var tabBarHeight: CGFloat = 0

    @Published var tab: FFTab = .fights {
        didSet {
            if oldValue != tab {
                openFightID = nil
                openPost = nil
                showingActivity = false
            }
        }
    }

    @Published var openFightID: String? {
        didSet {
            if openFightID != selectedHistoryFightID { selectedHistoryFightID = nil }
        }
    }
    private var selectedHistoryFightID: String?
    @Published var openPost: FeedPostLink?
    @Published var showingActivity = false
    @Published var feedRevision = 0
    @Published var dailyStatusRecap: DailyStatusRecap?
    @Published var showingVersions = false
    @Published var showingPreferences = false
    @Published var showingDebugMenu = false
    @Published var showingUpdateToastPreview = false
    @Published var feedbackRequestFilter = RequestFilter()
    @Published var companionPreviewNotice: String?
    @Published var joined: Set<String> = []
    @Published var createError: String?
    @Published var pendingJoinable: Fight?
    @Published var profileChallenge: ProfileChallengeDraft?
    @Published var pendingReferralError: String?
    @Published private(set) var isCreatingFight = false
    @Published private(set) var isUpdatingFight = false
    @Published private(set) var isDeletingFight = false
    @Published private(set) var isJoiningFight = false
    @Published private(set) var isRefreshingFights = false
    @Published private(set) var refreshPhase: FightRefreshPhase = .idle
    @Published private(set) var refreshLine = 0

    var refreshStatusText: String {
        refreshPhase.statusText(line: refreshLine)
    }

    @Published var you: Person
    @Published var fights: [Fight]
    @Published private(set) var joinableFights: [FitFightJoinableFight] = []
    @Published private(set) var suggestedFights: [FitFightJoinableFight] = []
    @Published private(set) var isLoadingDiscovery = false
    @Published private(set) var discoveryError: String?

    private var session: SessionStore?
    private let api = FitFightAPI()
    private var cachedUserID: UUID?
    private var snapshotGeneration = 0
    private var discoveryUserID: UUID?
    private var discoveryLoadedAt: Date?
    private var discoveryTask: Task<Void, Never>?
    private var discoveryGeneration = 0
    private var refreshTask: Task<Void, Never>?
    private var refreshLineTask: Task<Void, Never>?
    private var refreshUserID: UUID?
    private var pendingRefresh: (
        session: SessionStore,
        steps: HealthKitStepsStore,
        trigger: HealthKitStepsStore.SyncTrigger,
        requestAccess: Bool
    )?
    private static let pendingJoinCodeKey = "fitfight.pendingJoinCode"
    private static let pendingReferralCodeKey = "fitfight.pendingReferralCode"
    private static let pendingReferralUserKey = "fitfight.pendingReferralUser"
    private static let pendingFightRouteKey = "fitfight.pendingFightRoute"
    private static let pendingDailyStatusKey = "fitfight.pendingDailyStatus"

    static func storePendingFightRoute(_ route: String) {
        let trimmed = route.trimmingCharacters(in: .whitespacesAndNewlines)
        let withSlash = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        let components = URLComponents(string: "https://fitfight.app\(withSlash)")
        let path = (components?.path.isEmpty == false) ? components!.path : withSlash
        let dailyStatus = components?.queryItems?.contains { item in
            item.name == "daily_status" && (item.value == "1" || item.value?.lowercased() == "true")
        } ?? false
        let query = components?.percentEncodedQuery.map { "?\($0)" } ?? ""
        UserDefaults.standard.set(path + query, forKey: pendingFightRouteKey)
        UserDefaults.standard.set(dailyStatus, forKey: pendingDailyStatusKey)
    }

    private static var fightsCachePrefix: String {
        "fitfight.fights.\(AppLocalization.languageCode)."
    }

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

    #if DEBUG && targetEnvironment(simulator)
    func showCompanionPreviewState(_ state: CompanionPreview.DisplayState) {
        guard CompanionPreview.isEnabled else { return }
        let fixture = CompanionPreview.model(state: state)
        you = fixture.you
        fights = fixture.fights
        tab = .fights
        openFightID = nil
        createError = nil
        isRefreshingFights = state == .loading
        refreshPhase = state == .loading ? .updatingFights : .idle
        companionPreviewNotice = state == .offline
            ? String(appLocalized: "Offline preview. These are the last cached sample fights.") : nil
    }
    #endif

    init(fixtures: Bool) {
        if fixtures {
            let bundle = AppModelFixtures.load()
            you = bundle.you
            fights = bundle.fights
        } else {
            you = Person(id: "", name: String(appLocalized: "You"), handle: "", initials: "", isYou: true)
            fights = []
        }
    }

    func fight(id: String) -> Fight? {
        fights.first { $0.id.caseInsensitiveCompare(id) == .orderedSame }
            ?? pendingJoinable.flatMap { $0.id.caseInsensitiveCompare(id) == .orderedSame ? $0 : nil }
    }

    func canonicalFight(for id: String) -> Fight? {
        guard let fight = fight(id: id) else { return nil }
        guard let seriesId = fight.seriesId else { return fight }
        return fights
            .filter { $0.seriesId == seriesId }
            .reduce(fight) { Self.preferredCanonicalFight($0, $1) }
    }

    func detailFight(for id: String) -> Fight? {
        selectedHistoryFightID == id ? fight(id: id) : canonicalFight(for: id)
    }

    func seriesHistory(for fight: Fight) -> [Fight] {
        guard let seriesId = fight.seriesId else { return [] }
        return fights
            .filter { $0.seriesId == seriesId && $0.id != fight.id }
            .sorted { $0.windowStart > $1.windowStart }
    }

    func fightResult(for fight: Fight) -> FFResult {
        if fight.standings.contains(where: { $0.person.isYou && $0.deferred }) {
            return .draw
        }
        if fight.status == .pending {
            return .pending
        }
        if let state = fight.serverState, state != "final", state != "cancelled" {
            return .pending
        }
        if fight.isTiedForFirst {
            return .draw
        }
        return fight.rank == 1 ? .win : .loss
    }

    private var canonicalFights: [Fight] {
        var chosen: [String: Fight] = [:]
        for fight in fights {
            let key = fight.seriesId ?? fight.id
            if let existing = chosen[key] {
                chosen[key] = Self.preferredCanonicalFight(existing, fight)
            } else {
                chosen[key] = fight
            }
        }
        return Array(chosen.values)
    }

    var live: [Fight] {
        canonicalFights
            .filter { $0.status == .live }
            .sorted { $0.windowStart > $1.windowStart }
    }
    var invitations: [Fight] {
        canonicalFights
            .filter { $0.status == .invited }
            .sorted { $0.windowStart > $1.windowStart }
    }
    var finished: [Fight] {
        canonicalFights
            .filter { $0.status == .pending || $0.status == .finished }
            .sorted { $0.windowStart > $1.windowStart }
    }

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
        guard let date else { return String(appLocalized: "Not synced yet") }
        let elapsed = max(0, now.timeIntervalSince(date))
        if elapsed < 60 { return String(appLocalized: "Just now") }
        if elapsed < 3_600 {
            let minutes = Int(elapsed / 60)
            return String(appLocalized: "health.minutes-ago", defaultValue: "\(minutes) minutes ago")
        }
        if elapsed < 86_400 {
            let hours = Int(elapsed / 3_600)
            return String(appLocalized: "health.hours-ago", defaultValue: "\(hours) hours ago")
        }
        let days = Int(elapsed / 86_400)
        return String(appLocalized: "health.days-ago", defaultValue: "\(days) days ago")
    }

    func formatStandingFreshness(_ standing: Standing, fight: Fight, now: Date) -> String {
        guard fight.windowEnd <= now else { return formatLastSync(standing.lastSyncedAt, now: now) }
        if standing.finalStepsComplete == true {
            guard let lastSyncedAt = standing.lastSyncedAt else {
                return String(appLocalized: "Final steps synced")
            }
            let freshness = formatLastSync(lastSyncedAt, now: now)
            return String(
                appLocalized: "health.final-steps-synced-at",
                defaultValue: "Final steps synced · \(freshness)"
            )
        }
        if fight.serverState == "final", !standing.invited, !standing.deferred {
            return String(appLocalized: "Did not sync · forfeited")
        }
        let finalized = fight.serverState == "final" || fight.serverState == "cancelled"
        if let lastSyncedAt = standing.lastSyncedAt {
            let freshness = formatLastSync(lastSyncedAt, now: now)
            return finalized
                ? String(
                    appLocalized: "health.finalized-last-steps-at",
                    defaultValue: "Finalized from last available steps · \(freshness)"
                )
                : String(
                    appLocalized: "health.waiting-final-steps-at",
                    defaultValue: "Waiting for final steps · \(freshness)"
                )
        }
        return finalized
            ? String(appLocalized: "Finalized without synced steps")
            : String(appLocalized: "Waiting for first sync")
    }

    func refreshFromServer() async {
        guard let session else { return }
        await refreshFromServer(session: session)
    }

    func restoreCachedFights(session: SessionStore) {
        guard !CompanionPreview.isEnabled else { return }
        guard let userID = session.authSession?.user.id ?? session.client.auth.currentUser?.id else {
            snapshotGeneration += 1
            cachedUserID = nil
            fights = []
            return
        }
        guard cachedUserID != userID else { return }
        snapshotGeneration += 1
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

    func refreshFights(
        session: SessionStore,
        steps: HealthKitStepsStore,
        trigger: HealthKitStepsStore.SyncTrigger = .foreground,
        requestAccess: Bool = false
    ) async {
        if CompanionPreview.isEnabled {
            if requestAccess || trigger == .manual { companionPreviewNotice = CompanionPreview.writeUnavailable }
            return
        }
        if let refreshTask {
            if trigger != .foreground || requestAccess
                || (session.authSession?.user.id ?? session.client.auth.currentUser?.id) != refreshUserID {
                pendingRefresh = (session, steps, trigger, requestAccess || (pendingRefresh?.requestAccess ?? false))
            }
            await refreshTask.value
            return
        }
        isRefreshingFights = true
        refreshPhase = .readingHealth
        refreshUserID = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        let work = Task { @MainActor in
            defer {
                self.refreshLineTask?.cancel()
                self.refreshLineTask = nil
                self.refreshTask = nil
                self.refreshUserID = nil
                self.isRefreshingFights = false
                self.refreshPhase = .idle
                self.refreshLine = 0
            }
            var current = (session: session, steps: steps, trigger: trigger, requestAccess: requestAccess)
            repeat {
                self.pendingRefresh = nil
                self.refreshUserID = current.session.authSession?.user.id ?? current.session.client.auth.currentUser?.id
                await self.performRefreshFights(
                    session: current.session,
                    steps: current.steps,
                    trigger: current.trigger,
                    requestAccess: current.requestAccess
                )
                if let pending = self.pendingRefresh {
                    current = pending
                }
            } while self.pendingRefresh != nil
        }
        refreshTask = work
        guard !Task.isCancelled else { return }
        await work.value
    }

    private func performRefreshFights(
        session: SessionStore,
        steps: HealthKitStepsStore,
        trigger: HealthKitStepsStore.SyncTrigger,
        requestAccess: Bool
    ) async {
        let userID = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        let trace = HealthKitSyncTrace(trigger: trigger)

        await holdRefreshPhase(.readingHealth) {
            await steps.refresh(requestAccess: requestAccess, trace: trace)
        }
        guard (session.authSession?.user.id ?? session.client.auth.currentUser?.id) == userID else {
            trace.fail(.attemptExpired)
            steps.completeAttempt(trace, session: session, userID: userID)
            return
        }
        if session.authSession != nil {
            await holdRefreshPhase(.uploading) {
                await steps.syncToBackend(session: session, trigger: trigger, trace: trace)
            }
        }
        guard (session.authSession?.user.id ?? session.client.auth.currentUser?.id) == userID else {
            trace.fail(.attemptExpired)
            steps.completeAttempt(trace, session: session, userID: userID)
            return
        }
        await holdRefreshPhase(.updatingFights) {
            await refreshFromServer(session: session, trace: trace)
        }
        steps.completeAttempt(trace, session: session, userID: userID)
    }

    private func holdRefreshPhase(_ phase: FightRefreshPhase, work: () async -> Void) async {
        refreshPhase = phase
        refreshLine = 0
        refreshLineTask?.cancel()
        refreshLineTask = Task { @MainActor in
            var line = 0
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1.15)) } catch { return }
                line += 1
                self.refreshLine = line
            }
        }
        await work()
        refreshLineTask?.cancel()
        refreshLineTask = nil
    }

    func removeCachedFights(for userID: UUID) {
        snapshotGeneration += 1
        for language in ["en", "fr"] {
            UserDefaults.standard.removeObject(forKey: "fitfight.fights.\(language).\(userID.uuidString)")
        }
        if cachedUserID == userID {
            cachedUserID = nil
            fights = []
        }
    }

    func relocalizeFights() {
        var localized = fights
        for index in localized.indices {
            Self.localizeFight(&localized[index], formatScore: formatScore)
        }
        fights = localized
        if var pending = pendingJoinable {
            Self.localizeFight(&pending, formatScore: formatScore)
            pendingJoinable = pending
        }
        if let userID = cachedUserID, let data = try? JSONEncoder().encode(localized) {
            UserDefaults.standard.set(data, forKey: Self.fightsCachePrefix + userID.uuidString)
        }
    }

    func refreshFromServer(
        session: SessionStore, trace: HealthKitSyncTrace? = nil, performMaintenance: Bool = true
    ) async {
        guard !CompanionPreview.isEnabled else { return }
        self.session = session
        guard let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id else {
            return
        }
        snapshotGeneration += 1
        let generation = snapshotGeneration
        if let profile = session.profile {
            you = Self.person(from: profile, isYou: true)
        }
        let attempt = trace ?? HealthKitSyncTrace(trigger: .foreground)
        defer {
            if trace == nil && performMaintenance {
                HealthKitStepsStore.shared.completeAttempt(attempt, session: session, userID: userId)
            }
        }

        do {
            let token = try await attempt.measure(.session) { try await session.freshAccessToken() }
            guard session.authSession?.user.id == userId else { throw CancellationError() }
            let snapshot = try await api.fightsSnapshot(
                accessToken: token, trace: attempt, performMaintenance: performMaintenance
            )
            try Task.checkCancellation()
            guard session.authSession?.user.id == userId else {
                throw CancellationError()
            }
            // A newer read owns publication; superseding this response is not a sync failure.
            guard generation == snapshotGeneration else { return }
            let profiles = Dictionary(snapshot.profiles.map { ($0.userId, $0) }, uniquingKeysWith: { _, last in last })
            let members = Dictionary(grouping: snapshot.members, by: \.fightId)
            let mine = Dictionary(
                snapshot.members.filter { $0.userId == userId }.map { ($0.fightId, $0) },
                uniquingKeysWith: { _, last in last }
            )
            let series = Dictionary(snapshot.series.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            let loaded = snapshot.fights.compactMap { row -> Fight? in
                guard var fight = Self.mapFight(
                    row, members: members[row.id] ?? [], mine: mine[row.id], profiles: profiles,
                    series: row.seriesId.flatMap { series[$0] }, userId: userId, formatScore: formatScore
                ) else { return nil }
                fight.days = Self.dayCards(
                    from: members[row.id] ?? [], standings: fight.standings
                )
                return fight
            }
            guard session.authSession?.user.id == userId else { throw CancellationError() }
            fights = loaded
            cachedUserID = userId
            if let data = try? JSONEncoder().encode(loaded) {
                UserDefaults.standard.set(data, forKey: Self.fightsCachePrefix + userId.uuidString)
            }
            RemoteImageLoader.shared.prefetch(
                (loaded.flatMap { $0.standings.map(\.person.photoURL) } + [session.profile?.avatar?.url])
                    .compactMap { $0 },
                kind: .avatar
            )
        } catch {
            attempt.fail(HealthKitStepsStore.errorCode(for: error))
            // Keep the last successful result visible while the phone is offline.
        }
    }

    /// Locks Start fight immediately so extra taps cannot insert another row.
    func beginCreateFight() -> Bool {
        guard !CompanionPreview.isEnabled else { createError = CompanionPreview.writeUnavailable; return false }
        guard !isCreatingFight else { return false }
        isCreatingFight = true
        createError = nil
        return true
    }

    func createAndStartFight(
        name: String = "",
        startsAt: Date,
        endsAt: Date,
        timeZone: TimeZone,
        actionText: String,
        inviteHandles: [String],
        visibility: String = "invite_only",
        recurring: Bool = true,
        scheduled: Bool = false
    ) async {
        guard !CompanionPreview.isEnabled else { createError = CompanionPreview.writeUnavailable; return }
        if !isCreatingFight {
            isCreatingFight = true
        }
        defer { isCreatingFight = false }
        createError = nil
        guard let session, session.authSession != nil, api.isConfigured else {
            createError = String(appLocalized: "Sign in to start a fight.")
            return
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 120 else {
            createError = String(appLocalized: "Keep the title to 120 characters.")
            return
        }
        guard action.count <= 120 else {
            createError = String(appLocalized: "Keep the action to 120 characters.")
            return
        }
        guard endsAt > startsAt else {
            createError = String(appLocalized: "The end must be after the start.")
            return
        }
        guard !scheduled || startsAt > Date() else {
            createError = String(appLocalized: "Choose a start time in the future.")
            return
        }
        let storedName = title.isEmpty
            ? (action.isEmpty ? String(appLocalized: "Steps Fight") : action)
            : title

        let handles = inviteHandles.reduce(into: [String]()) { result, raw in
            let handle = SessionStore.strippedHandle(raw)
            if SessionStore.isValidHandle(handle), !result.contains(handle) {
                result.append(handle)
            }
        }
        let payload = FitFightCreateFight(
            name: storedName,
            startsAt: startsAt,
            endsAt: endsAt,
            timeZone: timeZone.identifier,
            outcomeRule: "highest_total",
            goalPolicy: "shared",
            defaultGoalValue: nil,
            stakeKind: "action",
            stakeMinor: nil,
            currency: nil,
            actionText: action.isEmpty ? nil : action,
            inviteHandles: handles.isEmpty ? nil : handles,
            start: scheduled ? "scheduled" : "now",
            visibility: visibility,
            recurring: recurring
        )

        do {
            let created = try await api.createFight(
                payload,
                accessToken: try await session.freshAccessToken(),
                idempotencyKey: UUID().uuidString
            )
            await syncStepsAfterMembershipChange(session: session)
            keepCreatedFight(created, payload: payload)
            tab = .fights
            openFightID = created.id.uuidString
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(appLocalized: "Couldn’t start the fight.")
        }
    }

    func updateFight(
        id: String,
        name: String,
        actionText: String,
        visibility: String,
        recurring: Bool,
        startsAt: Date?,
        endsAt: Date,
        timeZone: String?,
        inviteHandles: [String],
        removeUserIds: [String]
    ) async -> Bool {
        guard !CompanionPreview.isEnabled else {
            createError = CompanionPreview.writeUnavailable
            return false
        }
        guard !isUpdatingFight else { return false }
        isUpdatingFight = true
        defer { isUpdatingFight = false }
        createError = nil
        guard let session, session.authSession != nil, api.isConfigured else {
            createError = String(appLocalized: "Sign in to edit this fight.")
            return false
        }
        guard let fightID = UUID(uuidString: id) else {
            createError = String(appLocalized: "Couldn’t save the fight.")
            return false
        }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count <= 120 else {
            createError = String(appLocalized: "Keep the title to 120 characters.")
            return false
        }
        guard action.count <= 120 else {
            createError = String(appLocalized: "Keep the action to 120 characters.")
            return false
        }
        if let startsAt, startsAt <= Date() {
            createError = String(appLocalized: "Choose a start time in the future.")
            return false
        }
        guard endsAt > (startsAt ?? Date.distantPast) else {
            createError = String(appLocalized: "The end must be after the start.")
            return false
        }
        guard endsAt > Date() else {
            createError = String(appLocalized: "The end must be in the future.")
            return false
        }
        let handles = inviteHandles.reduce(into: [String]()) { result, raw in
            let handle = SessionStore.strippedHandle(raw)
            if SessionStore.isValidHandle(handle), !result.contains(handle) {
                result.append(handle)
            }
        }
        let removals = removeUserIds.compactMap(UUID.init(uuidString:))
        do {
            _ = try await api.updateFight(
                fightID: fightID,
                payload: FitFightUpdateFight(
                    name: title,
                    actionText: action,
                    visibility: visibility,
                    recurring: recurring,
                    startsAt: startsAt,
                    endsAt: endsAt,
                    timeZone: timeZone,
                    inviteHandles: handles.isEmpty ? nil : handles,
                    removeUserIds: removals.isEmpty ? nil : removals
                ),
                accessToken: try await session.freshAccessToken()
            )
            invalidateFightDiscovery()
            await refreshFromServer()
            return true
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(appLocalized: "Couldn’t save the fight.")
            return false
        }
    }

    func deleteFight(id: String) async -> Bool {
        guard !CompanionPreview.isEnabled else {
            createError = CompanionPreview.writeUnavailable
            return false
        }
        guard !isDeletingFight, !isUpdatingFight else { return false }
        isDeletingFight = true
        defer { isDeletingFight = false }
        createError = nil
        guard let session, session.authSession != nil, api.isConfigured else {
            createError = String(appLocalized: "Sign in to delete this fight.")
            return false
        }
        guard let fightID = UUID(uuidString: id) else {
            createError = String(appLocalized: "Couldn’t delete the fight.")
            return false
        }
        do {
            try await api.cancel(fightID: fightID, accessToken: try await session.freshAccessToken())
            invalidateFightDiscovery()
            openFightID = nil
            await refreshFromServer()
            return true
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(appLocalized: "Couldn’t delete the fight.")
            return false
        }
    }

    func acceptFight(id: String, start: String = "now") async {
        guard !CompanionPreview.isEnabled else { createError = CompanionPreview.writeUnavailable; return }
        guard !isJoiningFight else { return }
        isJoiningFight = true
        defer { isJoiningFight = false }
        createError = nil
        if let pending = pendingJoinable, pending.id == id, pending.pendingJoin {
            await joinPendingFight(pending, start: start)
            return
        }
        guard let session, session.authSession != nil, let fightID = UUID(uuidString: id) else {
            createError = String(appLocalized: "Sign in to accept this fight.")
            return
        }
        do {
            let token = try await session.freshAccessToken()
            _ = try await api.acceptFight(fightID: fightID, accessToken: token, start: start)
            joined.insert(id)
            await syncStepsAfterMembershipChange(session: session)
        } catch {
            createError = String(appLocalized: "Couldn’t accept.")
        }
    }

    func declineFight(id: String) async {
        guard !CompanionPreview.isEnabled else { createError = CompanionPreview.writeUnavailable; return }
        createError = nil
        if pendingJoinable?.id == id {
            pendingJoinable = nil
            openFightID = nil
            return
        }
        guard let session, session.authSession != nil, let fightID = UUID(uuidString: id) else {
            createError = String(appLocalized: "Sign in to decline this fight.")
            return
        }
        do {
            let token = try await session.freshAccessToken()
            _ = try await api.declineFight(fightID: fightID, accessToken: token)
            await refreshFromServer()
        } catch {
            createError = String(appLocalized: "Couldn’t decline.")
        }
    }

    private func invalidateFightDiscovery() {
        discoveryGeneration += 1
        discoveryLoadedAt = nil
        discoveryTask?.cancel()
        discoveryTask = nil
        isLoadingDiscovery = false
    }

    func loadFightDiscovery(session: SessionStore, force: Bool = false) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            joinableFights = fights.filter { $0.status == .live }.map { fight in
                FitFightJoinableFight(
                    fightId: UUID(uuidString: fight.id)!,
                    seriesId: UUID(uuidString: fight.seriesId ?? fight.id)!,
                    name: fight.name, joinCode: fight.joinCode!, ownerHandle: "lea",
                    actionText: fight.actionText, startsAt: fight.windowStart.ISO8601Format(),
                    endsAt: fight.windowEnd.ISO8601Format(), memberCount: fight.of,
                    recurring: fight.recurring, alreadyMember: true, canJoinNext: false
                )
            }
            suggestedFights = Array(joinableFights.prefix(2))
            return
        }
        #endif
        self.session = session
        let userID = session.authSession?.user.id
        if discoveryUserID != userID {
            invalidateFightDiscovery()
            discoveryUserID = userID
            joinableFights = []
            suggestedFights = []
            discoveryError = nil
        }
        guard let userID, api.isConfigured else { return }
        if let discoveryTask {
            await discoveryTask.value
            return
        }
        if !force, let discoveryLoadedAt, Date().timeIntervalSince(discoveryLoadedAt) < 60 {
            return
        }
        isLoadingDiscovery = true
        let generation = discoveryGeneration
        let task = Task { @MainActor in
            defer {
                if !Task.isCancelled, discoveryUserID == userID, discoveryGeneration == generation {
                    isLoadingDiscovery = false
                    discoveryTask = nil
                }
            }
            do {
                let access = try await session.freshAccessToken()
                guard !Task.isCancelled, discoveryUserID == userID, discoveryGeneration == generation,
                      session.authSession?.user.id == userID else { return }
                let complete = await withTaskGroup(of: (Bool, Result<[FitFightJoinableFight], Error>).self) { group in
                    for suggested in [false, true] {
                        group.addTask { @MainActor in
                            do {
                                let rows = try await suggested
                                    ? self.api.listSuggestedFights(accessToken: access)
                                    : self.api.listJoinableFights(accessToken: access)
                                return (suggested, .success(rows))
                            } catch {
                                return (suggested, .failure(error))
                            }
                        }
                    }
                    var loaded = 0
                    for await (suggested, result) in group {
                        guard !Task.isCancelled, discoveryUserID == userID, discoveryGeneration == generation,
                              session.authSession?.user.id == userID else {
                            group.cancelAll()
                            return false
                        }
                        switch result {
                        case .success(let rows):
                            if suggested { suggestedFights = rows } else { joinableFights = rows }
                            loaded += 1
                        case .failure(let error):
                            if !(error is CancellationError) {
                                discoveryError = (error as? FitFightAPIError)?.errorDescription
                                    ?? String(appLocalized: "Couldn’t load joinable fights.")
                            }
                        }
                    }
                    return loaded == 2
                }
                guard !Task.isCancelled, discoveryUserID == userID, discoveryGeneration == generation,
                      session.authSession?.user.id == userID else { return }
                discoveryLoadedAt = complete ? Date() : nil
                if complete { discoveryError = nil }
            } catch {
                guard !Task.isCancelled, !(error is CancellationError),
                      discoveryUserID == userID, discoveryGeneration == generation,
                      session.authSession?.user.id == userID else { return }
                discoveryLoadedAt = nil
                discoveryError = (error as? FitFightAPIError)?.errorDescription
                    ?? String(appLocalized: "Couldn’t load joinable fights.")
            }
        }
        discoveryTask = task
        await task.value
    }

    func setFightSuggested(id: String, suggested: Bool) async {
        createError = nil
        guard let session, session.authSession != nil, let fightID = UUID(uuidString: id) else {
            createError = String(appLocalized: "Sign in to suggest this fight.")
            return
        }
        if let index = fights.firstIndex(where: { $0.id == id }) {
            fights[index].suggested = suggested
        }
        do {
            let token = try await session.freshAccessToken()
            _ = try await api.setFightSuggested(fightID: fightID, suggested: suggested, accessToken: token)
            invalidateFightDiscovery()
            await refreshFromServer()
        } catch {
            if let index = fights.firstIndex(where: { $0.id == id }) {
                fights[index].suggested = !suggested
            }
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(appLocalized: "Couldn’t update that suggestion.")
        }
    }

    func openJoinable(_ summary: FitFightJoinableFight, session: SessionStore) async {
        self.session = session
        createError = nil
        if summary.alreadyMember {
            pendingJoinable = nil
            tab = .fights
            openFightID = summary.fightId.uuidString
            await refreshFromServer()
            return
        }
        if let profile = session.profile {
            you = Self.person(from: profile, isYou: true)
        }
        pendingJoinable = Self.fight(from: summary, you: you)
        if tab != .newFight {
            tab = .newFight
        }
    }

    func openJoinCode(_ raw: String, session: SessionStore) async {
        #if DEBUG && targetEnvironment(simulator)
        if CompanionPreview.isEnabled {
            if let match = fights.first(where: { $0.joinCode == raw.uppercased() }) {
                tab = .fights
                openFightID = match.id
            } else {
                createError = String(appLocalized: "Preview codes: K7M2, H8P4, B4K9.")
            }
            return
        }
        #endif
        self.session = session
        createError = nil
        let code = raw.replacingOccurrences(of: "[\\s-]", with: "", options: .regularExpression).uppercased()
        guard code.count == 4 else {
            createError = String(appLocalized: "Enter the 4-character code.")
            return
        }
        guard let userID = session.authSession?.user.id, api.isConfigured,
              session.profile != nil, !session.needsOnboarding else {
            UserDefaults.standard.set(code, forKey: Self.pendingJoinCodeKey)
            createError = String(appLocalized: "Sign in to join this fight.")
            return
        }
        do {
            let summary = try await api.joinableFight(code: code, accessToken: try await session.freshAccessToken())
            guard session.authSession?.user.id == userID else { return }
            if UserDefaults.standard.string(forKey: Self.pendingJoinCodeKey) == code {
                UserDefaults.standard.removeObject(forKey: Self.pendingJoinCodeKey)
            }
            await openJoinable(summary, session: session)
        } catch {
            guard session.authSession?.user.id == userID else { return }
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(appLocalized: "Couldn’t find that fight.")
        }
    }

    func handleOpenURL(_ url: URL, session: SessionStore) async {
        guard url.scheme == "https", url.host == APIConfig.publicOrigin.host,
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return }
        let parts = url.path.split(separator: "/")
        guard parts.count == 2 else { return }
        if parts[0] == "fights", let fightID = UUID(uuidString: String(parts[1])) {
            Self.storePendingFightRoute(
                "/fights/\(fightID.uuidString.lowercased())" + (url.query.map { "?\($0)" } ?? "")
            )
            await consumePendingLinks(session: session)
            return
        }
        let referral: UUID?
        if parts[0] == "r", let code = UUID(uuidString: String(parts[1])) {
            referral = code
        } else if let code = Self.joinCode(from: url) {
            UserDefaults.standard.set(code, forKey: Self.pendingJoinCodeKey)
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            referral = items.first(where: { $0.name == "ref" })
                .flatMap { $0.value }.flatMap { UUID(uuidString: $0) }
        } else {
            return
        }
        if let referral {
            UserDefaults.standard.set(referral.uuidString, forKey: Self.pendingReferralCodeKey)
            UserDefaults.standard.set(session.authSession?.user.id.uuidString, forKey: Self.pendingReferralUserKey)
        }
        await consumePendingLinks(session: session)
    }

    func consumePendingLinks(session: SessionStore) async {
        guard !session.needsOnboarding, let profile = session.profile,
              session.authSession?.user.id == profile.userId else { return }
        let pendingDailyStatus = UserDefaults.standard.bool(forKey: Self.pendingDailyStatusKey)
        consumePendingFightRoute(showDailyStatusRecap: pendingDailyStatus)
        if let code = UserDefaults.standard.string(forKey: Self.pendingJoinCodeKey) {
            await openJoinCode(code, session: session)
            guard session.authSession?.user.id == profile.userId else { return }
            if createError != nil { tab = .newFight }
        }
        guard let raw = UserDefaults.standard.string(forKey: Self.pendingReferralCodeKey),
              let code = UUID(uuidString: raw) else { return }
        if let owner = UserDefaults.standard.string(forKey: Self.pendingReferralUserKey),
           owner != profile.userId.uuidString {
            UserDefaults.standard.removeObject(forKey: Self.pendingReferralCodeKey)
            UserDefaults.standard.removeObject(forKey: Self.pendingReferralUserKey)
            return
        }
        UserDefaults.standard.set(profile.userId.uuidString, forKey: Self.pendingReferralUserKey)
        pendingReferralError = nil
        do {
            let access = try await session.freshAccessToken()
            guard session.authSession?.user.id == profile.userId else { return }
            _ = try await api.claimReferral(code: code, accessToken: access)
            guard session.authSession?.user.id == profile.userId else { return }
            if UserDefaults.standard.string(forKey: Self.pendingReferralCodeKey) == raw {
                UserDefaults.standard.removeObject(forKey: Self.pendingReferralCodeKey)
                UserDefaults.standard.removeObject(forKey: Self.pendingReferralUserKey)
            }
        } catch {
            guard session.authSession?.user.id == profile.userId else { return }
            pendingReferralError = String(appLocalized: "Your referral hasn’t been saved yet. Check your connection and try again.")
        }
    }

    private func keepCreatedFight(_ created: FitFightSummary, payload: FitFightCreateFight) {
        invalidateFightDiscovery()
        let id = created.id.uuidString
        guard fight(id: id) == nil else { return }
        fights.insert(Self.fight(created: created, payload: payload, you: you), at: 0)
        let userId = cachedUserID ?? session?.authSession?.user.id
        if let userId, let data = try? JSONEncoder().encode(fights) {
            UserDefaults.standard.set(data, forKey: Self.fightsCachePrefix + userId.uuidString)
            cachedUserID = userId
        }
    }

    func syncStepsAfterMembershipChange(session: SessionStore) async {
        invalidateFightDiscovery()
        let steps = HealthKitStepsStore.shared
        let trace = HealthKitSyncTrace(trigger: .manual)
        _ = await steps.syncToBackend(
            session: session,
            trigger: .manual,
            trace: trace,
            coalesceInFlight: false
        )
        steps.completeAttempt(trace, session: session, userID: session.authSession?.user.id)
        await refreshFromServer(session: session)
    }

    private func joinPendingFight(_ fight: Fight, start: String = "now") async {
        guard let session, session.authSession != nil, api.isConfigured else {
            createError = String(appLocalized: "Sign in to join this fight.")
            return
        }
        guard let fightID = UUID(uuidString: fight.id) else {
            createError = String(appLocalized: "Couldn’t join.")
            return
        }
        do {
            _ = try await api.joinFight(
                code: fight.joinCode, fightID: fightID, accessToken: try await session.freshAccessToken(), start: start
            )
            joined.insert(fight.id)
            await syncStepsAfterMembershipChange(session: session)
            pendingJoinable = nil
            tab = .fights
            openFightID = fight.id
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(appLocalized: "Couldn’t join.")
        }
    }

    func leaveFight(id: String) async {
        guard !CompanionPreview.isEnabled else { createError = CompanionPreview.writeUnavailable; return }
        createError = nil
        guard let session, session.authSession != nil, api.isConfigured else {
            createError = String(appLocalized: "Sign in to leave this fight.")
            return
        }
        guard let fightID = UUID(uuidString: id) else {
            createError = String(appLocalized: "Couldn’t leave.")
            return
        }
        do {
            _ = try await api.leaveFight(fightID: fightID, accessToken: try await session.freshAccessToken())
            invalidateFightDiscovery()
            openFightID = nil
            joined.remove(id)
            await refreshFromServer()
        } catch {
            createError = (error as? FitFightAPIError)?.errorDescription
                ?? String(appLocalized: "Couldn’t leave.")
        }
    }

    static func joinCode(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "j" else {
            return nil
        }
        let code = parts[1]
            .replacingOccurrences(of: "-", with: "")
            .uppercased()
        let alphabet = CharacterSet(charactersIn: "23456789ABCDEFGHJKMNPQRSTVWXYZ")
        guard code.count == 4, code.unicodeScalars.allSatisfy({ alphabet.contains($0) }) else {
            return nil
        }
        return code
    }

    private static func fight(
        created: FitFightSummary,
        payload: FitFightCreateFight,
        you: Person
    ) -> Fight {
        let starts = payload.startsAt
        let ends = payload.endsAt
        let lengthDays = max(1, Calendar.current.dateComponents([.day], from: starts, to: ends).day ?? 1)
        let lengthHours = max(1, Int((ends.timeIntervalSince(starts) / 3_600).rounded()))
        let remaining = RemainingTime.phrase(until: ends)
        return Fight(
            id: created.id.uuidString,
            name: payload.name,
            metric: .steps,
            lengthDays: lengthDays,
            daysLeft: max(1, Calendar.current.dateComponents([.day], from: Date(), to: ends).day ?? 1),
            actionText: payload.actionText ?? "",
            status: .live,
            rank: 1,
            of: 1,
            kickerEmphasis: String(
                appLocalized: "fight.time-left",
                defaultValue: "\(remaining) left"
            ),
            listSubtitle: localizedDuration(hours: lengthHours, days: lengthDays),
            standings: [Standing(person: you, score: 0, rank: 1)],
            windowStart: starts,
            windowEnd: ends,
            serverState: created.state,
            recurring: payload.recurring ?? false,
            visibility: payload.visibility ?? "invite_only",
            timeZone: payload.timeZone
        )
    }

    private static func fight(from summary: FitFightJoinableFight, you: Person) -> Fight {
        let starts = parseServerDate(summary.startsAt) ?? Date()
        let ends = parseServerDate(summary.endsAt) ?? starts.addingTimeInterval(86400)
        let lengthDays = max(1, Calendar.current.dateComponents([.day], from: starts, to: ends).day ?? 1)
        let owner = Person(
            id: summary.ownerHandle,
            name: "@\(summary.ownerHandle)",
            handle: "@\(summary.ownerHandle)",
            initials: String(summary.ownerHandle.prefix(2)).uppercased()
        )
        let action = summary.actionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let offersJoinNext = summary.canJoinNext ?? (summary.recurring && Self.isAfterFightStartDay(starts) && !summary.alreadyMember)
        return Fight(
            id: summary.fightId.uuidString,
            name: summary.name,
            metric: .steps,
            lengthDays: lengthDays,
            daysLeft: max(1, Calendar.current.dateComponents([.day], from: Date(), to: ends).day ?? 1),
            actionText: (action?.isEmpty == false ? action : nil) ?? "",
            status: .invited,
            rank: 0,
            of: max(summary.memberCount, 1),
            kickerEmphasis: String(
                appLocalized: "fight.challenged-you",
                defaultValue: "@\(summary.ownerHandle) challenged you"
            ),
            listSubtitle: "@\(summary.ownerHandle) · \(summary.memberCount)",
            inviter: owner,
            invitePitch: String(
                appLocalized: "fight.challenged-you",
                defaultValue: "@\(summary.ownerHandle) challenged you"
            ),
            standings: [
                Standing(person: you, score: 0),
                Standing(person: owner, score: 0),
            ],
            windowStart: starts,
            windowEnd: ends,
            joinCode: summary.joinCode,
            recurring: summary.recurring,
            visibility: "joinable",
            pendingJoin: true,
            offersJoinNext: offersJoinNext
        )
    }

    private static func dayCards(
        from members: [MemberRow],
        standings: [Standing]
    ) -> [FightDay] {
        let racers = standings.filter { !$0.invited && !$0.deferred }
        var histories: [String: [FightStepCheckpoint]] = [:]
        for row in racers {
            guard let personID = UUID(uuidString: row.person.id),
                  let points = members.first(where: { $0.userId == personID })?.stepCheckpoints,
                  let last = points.last, Double(last.steps) == row.score else { continue }
            histories[row.person.id] = points
        }
        guard !histories.isEmpty else { return [] }
        let days = Set(histories.values.flatMap { $0.map(\.day) }).sorted()
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let label = DateFormatter()
        label.calendar = formatter.calendar
        label.timeZone = formatter.timeZone
        label.locale = AppLocalization.locale
        label.setLocalizedDateFormatFromTemplate("EEEdMMM")
        var previous: [String: Int] = [:]
        return days.map { day in
            let scores = racers.map { row in
                guard let point = histories[row.person.id]?.first(where: { $0.day == day }) else {
                    return DayScore(person: row.person, value: 0, hasData: false)
                }
                let value = point.steps - (previous[row.person.id] ?? 0)
                previous[row.person.id] = point.steps
                return DayScore(person: row.person, value: Double(value))
            }
            let date = formatter.date(from: day) ?? Date()
            return FightDay(label: label.string(from: date), scores: scores)
        }
    }

    private static func person(from profile: FitFightProfile, isYou: Bool) -> Person {
        Person(
            id: profile.userId.uuidString,
            name: profile.atHandle,
            handle: profile.atHandle,
            initials: profile.initials,
            isYou: isYou,
            photoURL: profile.photoURL,
            companionId: profile.companionId
        )
    }

    func openFight(id: String, preserveRound: Bool = false) {
        let destination = (preserveRound ? fight(id: id) : canonicalFight(for: id))?.id ?? id
        tab = .fights
        Task { @MainActor in
            self.selectedHistoryFightID = preserveRound ? destination : nil
            self.openFightID = destination
        }
    }

    func presentDailyStatusRecap(for fightID: String) async {
        guard let session, session.authSession != nil, api.isConfigured,
              let id = UUID(uuidString: fightID) else { return }
        do {
            let recap = try await api.dailyStatusRecap(fightID: id, accessToken: try await session.freshAccessToken())
            dailyStatusRecap = DailyStatusRecap(fightID: fightID, body: recap.recap)
        } catch {
            dailyStatusRecap = nil
        }
    }

    private func consumePendingFightRoute(showDailyStatusRecap: Bool) {
        guard let route = UserDefaults.standard.string(forKey: Self.pendingFightRouteKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.pendingFightRouteKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingDailyStatusKey)
        guard let components = URLComponents(string: route) else { return }
        let parts = components.path.split(separator: "/").map(String.init)
        guard parts.count == 2, parts[0] == "fights", UUID(uuidString: parts[1]) != nil else { return }
        if components.queryItems?.contains(where: { $0.name == "activity" && $0.value == "1" }) == true {
            tab = .you
            showingActivity = true
            return
        }
        if let postID = components.queryItems?.first(where: { $0.name == "post" })?.value.flatMap(UUID.init(uuidString:)) {
            let commentID = components.queryItems?.first(where: { $0.name == "comment" })?.value.flatMap(UUID.init(uuidString:))
            tab = .feed
            openPost = FeedPostLink(id: postID, commentID: commentID)
            return
        }
        // A final-sync reminder can refer to an earlier round while the next is live.
        openFight(id: parts[1], preserveRound: true)
        if showDailyStatusRecap {
            Task { await presentDailyStatusRecap(for: parts[1]) }
        }
    }

    private static func mapFight(
        _ row: FightRow,
        members: [MemberRow],
        mine: MemberRow?,
        profiles: [UUID: FitFightProfile],
        series: SeriesRow?,
        userId: UUID,
        formatScore: (Double, MetricKind) -> String
    ) -> Fight? {
        if row.state == "draft" || mine?.state == "declined" || mine?.state == "withdrawn" { return nil }

        let starts = row.startsAtDate
        let ends = row.endsAtDate
        let lengthDays = max(1, Calendar.current.dateComponents([.day], from: starts, to: ends).day ?? 1)

        let status: FightStatus
        if mine?.state == "invited" && row.state != "final" && row.state != "cancelled" {
            status = .invited
        } else if row.state == "final" || row.state == "cancelled" {
            status = .finished
        } else if row.state == "awaiting_final_sync" || (row.state == "live" && ends < Date()) {
            status = .pending
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

        let peopleUnsorted = members.compactMap { member -> Standing? in
            switch member.state {
            case "invited", "accepted", "deferred":
                break
            default:
                return nil
            }
            let profile = profiles[member.userId]
            let person: Person
            if let profile {
                person = Self.person(from: profile, isYou: member.userId == userId)
            } else {
                person = Person(
                    id: member.userId.uuidString,
                    name: member.userId == userId ? String(appLocalized: "You") : "@user",
                    handle: "@user",
                    initials: "FF",
                    isYou: member.userId == userId
                )
            }
            let score = member.currentValue ?? member.finalValue ?? 0
            return Standing(
                person: person,
                score: member.state == "deferred" ? 0 : score,
                invited: member.state == "invited",
                deferred: member.state == "deferred",
                lastSyncedAt: member.lastSyncedAt,
                finalStepsComplete: member.finalStepsComplete,
                rank: member.rank
            )
        }
        let people = orderedStandings(peopleUnsorted, status: status)

        let joined = people.filter { !$0.invited && !$0.deferred }
        let youRow = people.first { $0.person.isYou }
        let listRank = youRow.flatMap { row in joined.firstIndex { $0.person.id == row.person.id }.map { $0 + 1 } }
            ?? mine?.rank
            ?? 0
        let rank = (status == .finished ? mine?.rank : nil) ?? listRank
        let of = max(joined.count, 1)
        let owner = profiles[row.ownerId].map { Self.person(from: $0, isYou: $0.userId == userId) }

        let actionText = row.actionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = actionText?.isEmpty == false ? (actionText ?? "") : ""

        var fight = Fight(
            id: row.id.uuidString,
            name: row.name,
            metric: .steps,
            lengthDays: lengthDays,
            daysLeft: daysLeft,
            actionText: action,
            status: status,
            rank: rank,
            of: of,
            kickerEmphasis: "",
            listSubtitle: "",
            inviter: owner,
            standings: people,
            windowStart: starts,
            windowEnd: ends,
            graceEndsAt: row.graceEndsAtDate,
            serverState: row.state,
            joinCode: series?.joinCode,
            seriesId: series?.id.uuidString,
            recurring: series?.recurring ?? false,
            visibility: series?.visibility ?? "invite_only",
            suggested: series?.suggested ?? false,
            offersJoinNext: (series?.recurring ?? false)
                && Self.isAfterFightStartDay(starts)
                && mine?.state == "invited",
            timeZone: row.timeZone
        )
        localizeFight(&fight, formatScore: formatScore)
        return fight
    }

    // Rebuild only app-owned copy from confirmed Fight data, including when refreshes fail.
    private static func localizeFight(_ fight: inout Fight, formatScore: (Double, MetricKind) -> String) {
        let status = fight.status
        let ends = fight.windowEnd
        let durationLabel = fight.durationLabel
        let remainingLabel = RemainingTime.phrase(until: ends)
        let people = fight.standings
        let joined = people.filter { !$0.invited && !$0.deferred }
        let waiting = people.filter(\.deferred)
        let youRow = people.first { $0.person.isYou }
        let rank = fight.rank
        let of = fight.of
        let tiedForFirst = fight.isTiedForFirst
        let ownerName = fight.inviter?.name ?? String(appLocalized: "Someone")

        fight.kickerEmphasis = ""
        fight.listSubtitle = ""
        fight.invitePitch = nil
        fight.endedLabel = nil

        switch status {
        case .invited:
            fight.invitePitch = String(
                appLocalized: "fight.challenged-you",
                defaultValue: "\(ownerName) challenged you"
            )
            fight.kickerEmphasis = fight.invitePitch ?? ""
            fight.listSubtitle = fight.pendingJoin
                ? "\(ownerName) · \(fight.of)"
                : "\(ownerName) · \(durationLabel)"
        case .finished:
            fight.endedLabel = String(
                appLocalized: "fight.ended-on",
                defaultValue: "Ended \(Fight.deadlineStamp(ends))"
            )
            if youRow?.deferred == true {
                fight.listSubtitle = fight.endedLabel ?? String(appLocalized: "Ended")
                fight.kickerEmphasis = String(appLocalized: "Started next round")
            } else if fight.serverState == "final" && tiedForFirst {
                fight.listSubtitle = String(
                    appLocalized: "fight.finished-tied",
                    defaultValue: "\(fight.endedLabel ?? String(appLocalized: "Ended")) · Tied"
                )
                fight.kickerEmphasis = String(appLocalized: "Tied")
            } else {
                fight.listSubtitle = String(
                    appLocalized: "fight.finished-position",
                    defaultValue: "\(fight.endedLabel ?? String(appLocalized: "Ended")) · \(Self.ordinal(rank)) of \(of)"
                )
                fight.kickerEmphasis = Self.ordinal(rank)
            }
        case .pending:
            fight.endedLabel = String(
                appLocalized: "fight.ended-on",
                defaultValue: "Ended \(Fight.deadlineStamp(ends))"
            )
            fight.listSubtitle = String(
                appLocalized: "fight.pending-ended-on",
                defaultValue: "Pending · Ended \(Fight.deadlineStamp(ends))"
            )
            if youRow?.deferred == true {
                fight.kickerEmphasis = String(appLocalized: "Started next round")
            } else if youRow?.finalStepsComplete == true {
                let submitted = people.filter { !$0.invited && !$0.deferred && $0.finalStepsComplete == true }
                let submittedRank = youRow.flatMap { you in
                    submitted.firstIndex { $0.person.id == you.person.id }.map { $0 + 1 }
                } ?? 0
                fight.kickerEmphasis = submittedRank == 1
                    ? String(appLocalized: "Tentative lead")
                    : String(appLocalized: "Tentative loss")
            } else {
                fight.kickerEmphasis = String(appLocalized: "Pending. Open the app")
            }
        case .live:
            if fight.serverState == "awaiting_final_sync" {
                fight.kickerEmphasis = String(appLocalized: "Syncing final steps")
                fight.listSubtitle = fight.kickerEmphasis
            } else if youRow?.deferred == true {
                fight.kickerEmphasis = String(appLocalized: "Starts next round")
                fight.listSubtitle = fight.kickerEmphasis
            } else if let youRow, let leader = joined.first, !youRow.invited {
                if youRow.person.id == leader.person.id, let runnerUp = joined.dropFirst().first {
                    let gap = leader.score - runnerUp.score
                    fight.kickerEmphasis = gap == 0
                        ? String(appLocalized: "Tied")
                        : String(
                            appLocalized: "fight.steps-value",
                            defaultValue: "\(formatScore(gap, .steps)) steps"
                        )
                    fight.listSubtitle = gap == 0
                        ? String(
                            appLocalized: "fight.tied-time-to-go",
                            defaultValue: "Tied with \(remainingLabel) to go"
                        )
                        : String(
                            appLocalized: "fight.leading-time-to-go",
                            defaultValue: "Leading by \(fight.kickerEmphasis) with \(remainingLabel) to go"
                        )
                } else if youRow.person.id == leader.person.id {
                    fight.kickerEmphasis = String(
                        appLocalized: "fight.time-left",
                        defaultValue: "\(remainingLabel) left"
                    )
                    fight.listSubtitle = fight.kickerEmphasis
                } else {
                    let gap = leader.score - youRow.score
                    fight.kickerEmphasis = gap == 0
                        ? String(appLocalized: "Tied")
                        : String(
                            appLocalized: "fight.steps-value",
                            defaultValue: "\(formatScore(gap, .steps)) steps"
                        )
                    fight.listSubtitle = gap == 0
                        ? String(appLocalized: "Tied")
                        : String(
                            appLocalized: "fight.steps-behind-person",
                            defaultValue: "\(fight.kickerEmphasis) behind \(leader.person.name)"
                        )
                }
            } else {
                fight.kickerEmphasis = String(
                    appLocalized: "fight.time-left",
                    defaultValue: "\(remainingLabel) left"
                )
                fight.listSubtitle = fight.kickerEmphasis
            }
        }

        fight.standingsMeta = waiting.isEmpty
            ? nil
            : String(
                appLocalized: "fight.standings-next",
                defaultValue: "\(joined.count) racing · \(waiting.count) start next"
            )
    }

    private static func isAfterFightStartDay(_ start: Date, now: Date = Date()) -> Bool {
        let calendar = Calendar.current
        return calendar.startOfDay(for: now) > calendar.startOfDay(for: start)
    }

    private static func fightStatusPriority(_ status: FightStatus) -> Int {
        switch status {
        case .live: return 4
        case .pending: return 3
        case .invited: return 2
        case .finished: return 1
        }
    }

    static func preferredCanonicalFight(_ a: Fight, _ b: Fight) -> Fight {
        let left = fightStatusPriority(a.status)
        let right = fightStatusPriority(b.status)
        if left != right { return left > right ? a : b }
        if a.windowStart != b.windowStart { return a.windowStart > b.windowStart ? a : b }
        return a
    }

    private static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocalization.locale
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? value.formatted()
    }

    private static func orderedStandings(_ standings: [Standing], status: FightStatus) -> [Standing] {
        standings.sorted { lhs, rhs in
            if status == .pending {
                let lhsOpen = !lhs.invited && !lhs.deferred && lhs.finalStepsComplete != true
                let rhsOpen = !rhs.invited && !rhs.deferred && rhs.finalStepsComplete != true
                if lhsOpen != rhsOpen { return lhsOpen && !rhsOpen }
            }
            if lhs.invited != rhs.invited { return !lhs.invited && rhs.invited }
            if lhs.deferred != rhs.deferred { return !lhs.deferred && rhs.deferred }
            if status == .finished, let lhsRank = lhs.rank, let rhsRank = rhs.rank, lhsRank != rhsRank {
                return lhsRank < rhsRank
            }
            if lhs.score == rhs.score { return lhs.person.name < rhs.person.name }
            return lhs.score > rhs.score
        }
    }
}

private func localizedDuration(hours: Int, days: Int) -> String {
    if hours <= 6 {
        return String(
            appLocalized: "duration.hours",
            defaultValue: "\(hours) hours"
        )
    }
    return String(
        appLocalized: "duration.days",
        defaultValue: "\(days) days"
    )
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
                name: isFrench ? "Défi transpiration 7 jours" : "7-Day Sweat Ladder",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 4,
                actionText: isFrench ? "Le perdant organise la prochaine balade" : "Loser plans the next walk",
                status: .live,
                rank: 2,
                of: 3,
                kickerEmphasis: "12.0k",
                listSubtitle: String(appLocalized: "12.0k behind @leo_runs"),
                inviter: you,
                standings: [
                    Standing(person: leo, score: 54_000, lastSyncedAt: syncedJustNow),
                    Standing(person: you, score: 42_000, lastSyncedAt: syncedToday),
                    Standing(person: sam, score: 37_000, lastSyncedAt: syncedYesterday)
                ],
                days: [
                    FightDay(label: String(appLocalized: "Day 1"), scores: [
                        DayScore(person: leo, value: 20_000),
                        DayScore(person: you, value: 12_000),
                        DayScore(person: sam, value: 15_000)
                    ]),
                    FightDay(label: String(appLocalized: "Day 2"), scores: [
                        DayScore(person: leo, value: 18_000),
                        DayScore(person: you, value: 16_000),
                        DayScore(person: sam, value: 10_000)
                    ]),
                    FightDay(label: String(appLocalized: "Day 3"), scores: [
                        DayScore(person: leo, value: 16_000),
                        DayScore(person: you, value: 14_000),
                        DayScore(person: sam, value: 12_000)
                    ])
                ],
                windowEnd: Date().addingTimeInterval(4 * 24 * 60 * 60)
            ),
            Fight(
                id: "derby",
                name: isFrench ? "Derby des pas" : "Step Derby",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 2,
                actionText: isFrench ? "Les perdants préparent le dîner dimanche" : "Losers cook Sunday dinner",
                status: .live,
                rank: 1,
                of: 5,
                kickerEmphasis: String(appLocalized: "1st"),
                listSubtitle: String(appLocalized: "Holding 1st with 2d to go"),
                standings: [
                    Standing(person: you, score: 61400, lastSyncedAt: syncedJustNow),
                    Standing(person: ivy, score: 59800, lastSyncedAt: syncedToday),
                    Standing(person: theo, score: 55200, lastSyncedAt: syncedYesterday),
                    Standing(person: leo, score: 40100, lastSyncedAt: syncedYesterday),
                    Standing(person: nina, score: 22000, invited: true)
                ],
                windowEnd: Date().addingTimeInterval(1 * 24 * 60 * 60 + 8 * 60 * 60)
            ),
            Fight(
                id: "club",
                name: isFrench ? "Club des 10 000" : "10K Club",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 3,
                actionText: isFrench ? "Les perdants organisent la prochaine randonnée" : "Losers organize the next hike",
                status: .live,
                rank: 2,
                of: 4,
                kickerEmphasis: String(appLocalized: "3.2k steps"),
                listSubtitle: String(appLocalized: "3.2k steps behind @sam_sweats"),
                standings: [
                    Standing(person: sam, score: 44800, lastSyncedAt: syncedToday),
                    Standing(person: you, score: 41600, lastSyncedAt: syncedJustNow),
                    Standing(person: nina, score: 31900, lastSyncedAt: syncedYesterday),
                    Standing(person: ivy, score: 28100, lastSyncedAt: syncedYesterday)
                ],
                windowEnd: Date().addingTimeInterval(3 * 24 * 60 * 60)
            ),
            Fight(
                id: "desk",
                name: isFrench ? "Revanche du bureau" : "Desk Job Revenge",
                metric: .steps,
                lengthDays: 3,
                daysLeft: 3,
                actionText: isFrench ? "Les perdants prennent les escaliers toute la journée" : "Losers take the stairs all day",
                status: .invited,
                rank: 0,
                of: 4,
                kickerEmphasis: String(appLocalized: "@theo_rows challenged you"),
                listSubtitle: String(appLocalized: "@theo_rows · 3 days"),
                inviter: theo,
                invitePitch: String(appLocalized: "@theo_rows challenged you"),
                standingsMeta: String(appLocalized: "2 in · 2 not replied"),
                standings: [
                    Standing(person: theo, score: 0),
                    Standing(person: nina, score: 0),
                    Standing(person: ivy, score: 0, invited: true)
                ]
            ),
            Fight(
                id: "sprint",
                name: isFrench ? "Sprint en ville" : "City Sprint",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 7,
                actionText: isFrench ? "Les perdants organisent une balade au parc" : "Losers plan a park walk",
                status: .invited,
                rank: 0,
                of: 3,
                kickerEmphasis: String(appLocalized: "@ivy_climbs challenged you"),
                listSubtitle: String(appLocalized: "@ivy_climbs · 7 days"),
                inviter: ivy,
                invitePitch: String(appLocalized: "@ivy_climbs challenged you"),
                standings: [
                    Standing(person: ivy, score: 0)
                ]
            ),
            Fight(
                id: "weekend",
                name: isFrench ? "Duel de pas du week-end" : "Weekend Step Duel",
                metric: .steps,
                lengthDays: 2,
                endedLabel: String(appLocalized: "Ended Jul 13"),
                actionText: isFrench ? "Le perdant choisit le prochain parcours" : "Loser plans the next route",
                status: .finished,
                rank: 1,
                of: 2,
                kickerEmphasis: String(appLocalized: "2.2k steps"),
                listSubtitle: String(appLocalized: "Ended Jul 13 · 1st of 2"),
                standingsMeta: String(appLocalized: "2 in"),
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

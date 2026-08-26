import Combine
import Foundation
import HealthKit
import Supabase

struct StepDayHistory: Identifiable, Equatable, Hashable, Codable {
    var day: String
    var date: Date
    var steps: Int
    var sources: [String]

    var id: String { day }
}

@MainActor
final class HealthKitStepsStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case reading
        case steps(count: Int, sources: [String])
        case empty
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var history: [StepDayHistory] = []
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var uploadError: String?
    @Published private(set) var isSyncing = false
    @Published private(set) var sourceId: UUID?

    private let store = HKHealthStore()
    private let askedKey = "ff.healthkit.stepsAsked"
    private let connectedKey = "ff.healthkit.appleHealthConnected"
    private let lastUploadDayKey = "ff.healthkit.lastUploadDay"
    private let lastSyncedAtKey = "ff.healthkit.lastSyncedAt"
    private let sourceIdKey = "ff.healthkit.sourceId"
    private let historyKey = "ff.healthkit.history"
    private var isUploading = false

    init() {
        let defaults = UserDefaults.standard
        if let interval = defaults.object(forKey: lastSyncedAtKey) as? TimeInterval {
            lastSyncedAt = Date(timeIntervalSince1970: interval)
        }
        if let raw = defaults.string(forKey: sourceIdKey), let id = UUID(uuidString: raw) {
            sourceId = id
        }
        if let data = defaults.data(forKey: historyKey),
           let cached = try? JSONDecoder().decode([StepDayHistory].self, from: data),
           !cached.isEmpty {
            history = cached
            applyStatus(from: cached)
        }
    }

    var hasAsked: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    var detailText: String {
        switch status {
        case .idle:
            return hasAsked ? "Tap to open" : "Tap to connect"
        case .reading:
            return "Reading…"
        case .steps(let count, _):
            return "\(Self.format(count)) steps today"
        case .empty:
            return "No accessible data"
        }
    }

    var metaText: String {
        if let lastSyncedAt {
            return "Synced \(Self.relative(lastSyncedAt))"
        }
        switch status {
        case .steps(_, let sources):
            return sources.joined(separator: ", ")
        default:
            return ""
        }
    }

    var isConnected: Bool {
        if lastSyncedAt != nil { return true }
        if UserDefaults.standard.bool(forKey: connectedKey) { return true }
        if case .steps = status { return true }
        return history.contains { $0.steps > 0 }
    }

    var todayCount: Int {
        if case .steps(let count, _) = status { return count }
        return todayHistory?.steps ?? 0
    }

    var todaySources: [String] {
        if case .steps(_, let sources) = status { return sources }
        return todayHistory?.sources ?? []
    }

    var todayHistory: StepDayHistory? {
        history.first { Calendar.current.isDateInToday($0.date) }
    }

    func refresh(requestAccess: Bool) async {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else {
            if (requestAccess || hasAsked) && history.isEmpty {
                status = .empty
            }
            return
        }

        if requestAccess {
            do {
                try await store.requestAuthorization(toShare: [], read: [stepsType])
            } catch {
                // HealthKit does not distinguish denial from an empty store.
            }
            UserDefaults.standard.set(true, forKey: askedKey)
        }

        guard requestAccess || hasAsked else { return }

        status = .reading
        do {
            let days = try await Self.collectDays(store: store, type: stepsType)
            persistHistory(days)
        } catch {
            do {
                let days = try await Self.collectDaysLegacy(store: store, type: stepsType)
                persistHistory(days)
            } catch {
                if history.isEmpty {
                    status = .empty
                } else {
                    applyStatus(from: history)
                }
            }
        }
    }

    /// Ask (if needed), read 31 civil days, upload to `step_days`, upsert `data_sources`.
    func connectAndSync(client: SupabaseClient?, userId: UUID?) async {
        await refresh(requestAccess: true)
        guard let client, let userId else { return }
        await syncToSupabase(client: client, userId: userId)
    }

    /// Upload Apple Health daily aggregates to `step_days`. Skips if Health was never asked.
    func syncToSupabase(client: SupabaseClient, userId: UUID) async {
        guard hasAsked, !isUploading else { return }
        isUploading = true
        isSyncing = true
        uploadError = nil
        defer {
            isUploading = false
            isSyncing = false
        }

        if history.isEmpty {
            await refresh(requestAccess: false)
        }

        var rows = history
        if rows.isEmpty {
            await loadServerHistory(client: client, userId: userId)
            rows = history
        }
        guard !rows.isEmpty else { return }

        do {
            let payload = rows.map {
                StepDayUpload(userId: userId, day: $0.day, steps: $0.steps)
            }
            try await client.from("step_days")
                .upsert(payload, onConflict: "user_id,day")
                .execute()

            let now = Date()
            lastSyncedAt = now
            UserDefaults.standard.set(now.timeIntervalSince1970, forKey: lastSyncedAtKey)
            if let today = rows.first(where: { Calendar.current.isDateInToday($0.date) }) {
                UserDefaults.standard.set(today.day, forKey: lastUploadDayKey)
            }

            let evidence = rows.contains { $0.steps > 0 } || rows.contains { !$0.sources.isEmpty }
            if evidence {
                UserDefaults.standard.set(true, forKey: connectedKey)
                await upsertDataSource(client: client, userId: userId, rows: rows)
            }
        } catch {
            uploadError = (error as? LocalizedError)?.errorDescription
                ?? "Couldn’t upload steps. Try Sync now."
        }
    }

    func loadServerHistory(client: SupabaseClient, userId: UUID) async {
        struct Row: Decodable {
            let day: String
            let steps: Int
        }

        do {
            let rows: [Row] = try await client.from("step_days")
                .select("day, steps")
                .eq("user_id", value: userId)
                .order("day", ascending: false)
                .limit(31)
                .execute()
                .value
            guard history.isEmpty, !rows.isEmpty else { return }
            let formatter = Self.dayFormatter()
            let days = rows.compactMap { row -> StepDayHistory? in
                guard let date = formatter.date(from: row.day) else { return nil }
                return StepDayHistory(day: row.day, date: date, steps: row.steps, sources: [])
            }
            persistHistory(days)
        } catch {
            // Local HealthKit history still shows if the table is missing.
        }
    }

    private func persistHistory(_ days: [StepDayHistory]) {
        history = days
        applyStatus(from: days)
        if let data = try? JSONEncoder().encode(days) {
            UserDefaults.standard.set(data, forKey: historyKey)
        }
    }

    private func applyStatus(from days: [StepDayHistory]) {
        let today = days.first { Calendar.current.isDateInToday($0.date) }
        let anySteps = days.contains { $0.steps > 0 }
        let anySources = days.contains { !$0.sources.isEmpty }
        if anySteps || anySources {
            status = .steps(count: today?.steps ?? 0, sources: today?.sources ?? [])
        } else if hasAsked {
            status = .empty
        } else {
            status = .idle
        }
    }

    private func upsertDataSource(
        client: SupabaseClient,
        userId: UUID,
        rows: [StepDayHistory]
    ) async {
        var seen = Set<String>()
        let labels = rows.flatMap(\.sources).filter { seen.insert($0).inserted }
        let newest = rows.map(\.date).max() ?? Date()
        let completeThrough = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: newest))
            ?? Date()
        let payload = DataSourceUpsert(
            userId: userId,
            provider: "apple_health",
            sourceLabel: "Apple Health",
            contributingSourceLabels: labels,
            connectionRoute: "healthkit",
            capabilities: ["steps"],
            status: "healthy",
            consentVersion: 1,
            lastSuccessAt: Self.isoNow(),
            completeThrough: Self.isoString(completeThrough)
        )
        do {
            let saved: [DataSourceIDRow] = try await client.from("data_sources")
                .upsert(payload, onConflict: "user_id,provider,connection_route")
                .select("id")
                .execute()
                .value
            if let id = saved.first?.id {
                sourceId = id
                UserDefaults.standard.set(id.uuidString, forKey: sourceIdKey)
            }
        } catch {
            // step_days already landed; standings still work without this row.
        }
    }

    /// One collection query for 31 civil days. Do not sum every raw sample/source.
    private static func collectDays(
        store: HKHealthStore,
        type: HKQuantityType
    ) async throws -> [StepDayHistory] {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -30, to: todayStart) else {
            return []
        }
        let end = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: end,
            options: .strictStartDate
        )
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: HKSamplePredicate.quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum, .separateBySource],
            anchorDate: todayStart,
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        let formatter = dayFormatter()
        var days: [StepDayHistory] = []
        days.reserveCapacity(31)
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            let value = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
            var seen = Set<String>()
            let labels = (stats.sources ?? []).compactMap { source -> String? in
                let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, seen.insert(name).inserted else { return nil }
                return name
            }
            days.append(
                StepDayHistory(
                    day: formatter.string(from: stats.startDate),
                    date: stats.startDate,
                    steps: Int(value.rounded()),
                    sources: labels
                )
            )
        }
        return days.sorted { $0.date > $1.date }
    }

    /// Fallback if the collection descriptor fails: one aggregate per civil day.
    private static func collectDaysLegacy(
        store: HKHealthStore,
        type: HKQuantityType
    ) async throws -> [StepDayHistory] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = dayFormatter()
        var days: [StepDayHistory] = []
        days.reserveCapacity(31)
        for offset in 0...30 {
            guard let start = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let end = offset == 0 ? Date() : calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let value = try await dayAggregate(store: store, type: type, start: start, end: end)
            days.append(
                StepDayHistory(
                    day: formatter.string(from: start),
                    date: start,
                    steps: Int(value.rounded()),
                    sources: []
                )
            )
        }
        return days
    }

    private static func dayAggregate(
        store: HKHealthStore,
        type: HKQuantityType,
        start: Date,
        end: Date
    ) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(
                withStart: start,
                end: end,
                options: .strictStartDate
            )
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let value = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: value)
            }
            store.execute(query)
        }
    }

    private static func dayFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = Calendar.current.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func isoNow() -> String {
        isoString(Date())
    }

    private static func isoString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func format(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    static func dayLabel(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE d MMM"
        return formatter.string(from: date)
    }

    static func relative(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days == 1 { return "yesterday" }
        return "\(days)d ago"
    }
}

private struct StepDayUpload: Encodable {
    let userId: UUID
    let day: String
    let steps: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case day
        case steps
    }
}

private struct DataSourceIDRow: Decodable {
    let id: UUID
}

private struct DataSourceUpsert: Encodable {
    let userId: UUID
    let provider: String
    let sourceLabel: String
    let contributingSourceLabels: [String]
    let connectionRoute: String
    let capabilities: [String]
    let status: String
    let consentVersion: Int
    let lastSuccessAt: String
    let completeThrough: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case provider
        case sourceLabel = "source_label"
        case contributingSourceLabels = "contributing_source_labels"
        case connectionRoute = "connection_route"
        case capabilities
        case status
        case consentVersion = "consent_version"
        case lastSuccessAt = "last_success_at"
        case completeThrough = "complete_through"
        case lastErrorCode = "last_error_code"
        case revokedAt = "revoked_at"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userId, forKey: .userId)
        try container.encode(provider, forKey: .provider)
        try container.encode(sourceLabel, forKey: .sourceLabel)
        try container.encode(contributingSourceLabels, forKey: .contributingSourceLabels)
        try container.encode(connectionRoute, forKey: .connectionRoute)
        try container.encode(capabilities, forKey: .capabilities)
        try container.encode(status, forKey: .status)
        try container.encode(consentVersion, forKey: .consentVersion)
        try container.encode(lastSuccessAt, forKey: .lastSuccessAt)
        try container.encode(completeThrough, forKey: .completeThrough)
        try container.encodeNil(forKey: .lastErrorCode)
        try container.encodeNil(forKey: .revokedAt)
    }
}

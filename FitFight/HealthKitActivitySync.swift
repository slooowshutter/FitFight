import Foundation
import HealthKit

@MainActor
enum HealthKitActivitySync {
    // Finished days stopped changing within 6 days of midnight in staging Fight data (14 Oct 2026).
    private static let recentDayCount = 7
    private static let historyPageDays = 1_000

    private struct MetricProgress: Codable {
        var historyCursor: Date?
        var historyComplete = false
        var acknowledgedThrough: Date?
    }

    private struct Progress: Codable {
        var timeZoneIdentifier: String
        var metrics: [String: MetricProgress] = [:]
    }

    static func clear(userId: UUID) {
        let prefix = "ff.healthkit.activity.\(userId.uuidString.lowercased())."
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    /// Uploads daily Steps only. Other activity stays in Apple Health; Profile reads it on the phone.
    static func synchronize(
        store: HKHealthStore,
        api: FitFightAPI,
        session: SessionStore,
        userId: UUID,
        context: FitFightHealthKitContext,
        timeZone: TimeZone,
        trace: HealthKitSyncTrace
    ) async throws -> Bool {
        guard let kind = HealthKitActivityAggregates.totalKinds.first(where: { $0.metric == "steps" }) else {
            return true
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let cutoff = context.serverNow
        let today = calendar.startOfDay(for: cutoff)
        let key = stateKey(userId: userId, api: api)
        var progress = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Progress.self, from: $0) }
            ?? Progress(timeZoneIdentifier: timeZone.identifier)
        if progress.timeZoneIdentifier != timeZone.identifier {
            progress = Progress(timeZoneIdentifier: timeZone.identifier)
        }
        var metric = progress.metrics[kind.metric] ?? MetricProgress()
        // A week before the last upload, so a phone that missed syncs for days leaves no gap.
        let recentStart = min(
            calendar.date(byAdding: .day, value: 1 - recentDayCount, to: today) ?? today,
            metric.acknowledgedThrough.flatMap {
                calendar.date(byAdding: .day, value: -recentDayCount, to: calendar.startOfDay(for: $0))
            } ?? today
        )
        var processingComplete = true

        // Current readings lead the upload, so an initial history import never delays live totals.
        let recent = try await HealthKitActivityAggregates.mergedDays(
            store: store, kind: kind, start: recentStart, end: cutoff,
            calendar: calendar, zeroDays: []
        )
        for offset in stride(from: 0, to: recent.count, by: 1_000) {
            let pageProcessed = try await upload(
                totals: Array(recent[offset..<min(offset + 1_000, recent.count)]), cutoff: cutoff,
                timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
            )
            processingComplete = pageProcessed && processingComplete
        }
        metric.acknowledgedThrough = cutoff
        progress.metrics[kind.metric] = metric
        try save(progress, key: key)

        if !metric.historyComplete {
            if metric.historyCursor == nil {
                metric.historyCursor = try await earliestSample(store: store, type: kind.type)
                    .map { calendar.startOfDay(for: $0) }
            }
            if metric.historyCursor == nil {
                metric.historyComplete = true
            }
            if var cursor = metric.historyCursor {
                while cursor < cutoff {
                    try Task.checkCancellation()
                    let next = min(calendar.date(byAdding: .day, value: historyPageDays, to: cursor) ?? cutoff, cutoff)
                    let rows = try await HealthKitActivityAggregates.mergedDays(
                        store: store, kind: kind, start: cursor, end: next,
                        calendar: calendar, zeroDays: []
                    )
                    let pageProcessed = try await upload(
                        totals: rows, cutoff: cutoff,
                        timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
                    )
                    processingComplete = pageProcessed && processingComplete
                    cursor = next
                    metric.historyCursor = cursor
                    progress.metrics[kind.metric] = metric
                    try save(progress, key: key)
                }
                metric.historyComplete = true
            }
            progress.metrics[kind.metric] = metric
            try save(progress, key: key)
        }

        return processingComplete
    }

    private static func upload(
        totals: [FitFightHealthKitStepSync.ActivityDay],
        cutoff: Date,
        timeZone: TimeZone,
        api: FitFightAPI,
        session: SessionStore,
        trace: HealthKitSyncTrace,
        userId: UUID
    ) async throws -> Bool {
        guard !totals.isEmpty else { return true }
        try Task.checkCancellation()
        guard session.authSession?.user.id == userId else { throw CancellationError() }
        let token = try await session.freshAccessToken()
        guard session.authSession?.user.id == userId else { throw CancellationError() }
        let batch = FitFightHealthKitActivityBatch(
            collectedAt: HealthKitStepAggregates.iso8601(cutoff),
            timeZone: timeZone.identifier,
            totals: totals,
            workouts: [],
            deletedWorkouts: []
        )
        let result = try await api.syncHealthKitActivity(batch, accessToken: token, trace: trace)
        return result.processing == "processed"
    }

    private static func earliestSample(store: HKHealthStore, type: HKSampleType) async throws -> Date? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: nil, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first?.startDate) }
            }
            store.execute(query)
        }
    }

    private static func stateKey(userId: UUID, api: FitFightAPI) -> String {
        "ff.healthkit.activity.\(userId.uuidString.lowercased()).\(api.baseURL?.host ?? "unconfigured")"
    }

    private static func save(_ progress: Progress, key: String) throws {
        // A cancelled import must not restore progress that was just cleared.
        try Task.checkCancellation()
        UserDefaults.standard.set(try JSONEncoder().encode(progress), forKey: key)
    }
}

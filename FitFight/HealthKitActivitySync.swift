import Foundation
import HealthKit

@MainActor
enum HealthKitActivitySync {
    private static let recentDayCount = 40
    private static let historyPageDays = 1_000
    private static let anchorPageSize = 100

    private struct MetricProgress: Codable {
        var historyCursor: Date?
        var historyComplete = false
        var acknowledgedThrough: Date?
        var anchorData: Data?
        var sampleBootstrapComplete = false
    }

    private struct Progress: Codable {
        var timeZoneIdentifier: String
        var metrics: [String: MetricProgress] = [:]
        var workoutAnchorData: Data?
    }

    static func clear(userId: UUID) {
        let prefix = "ff.healthkit.activity.\(userId.uuidString.lowercased())."
        for key in UserDefaults.standard.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    static func synchronize(
        store: HKHealthStore,
        api: FitFightAPI,
        session: SessionStore,
        userId: UUID,
        context: FitFightHealthKitContext,
        timeZone: TimeZone,
        trace: HealthKitSyncTrace
    ) async throws -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let cutoff = context.serverNow
        let today = calendar.startOfDay(for: cutoff)
        let recentStart = calendar.date(byAdding: .day, value: 1 - recentDayCount, to: today) ?? today
        let key = stateKey(userId: userId, api: api)
        var progress = UserDefaults.standard.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(Progress.self, from: $0) }
            ?? Progress(timeZoneIdentifier: timeZone.identifier)
        if progress.timeZoneIdentifier != timeZone.identifier {
            progress = Progress(timeZoneIdentifier: timeZone.identifier)
        }

        for kind in HealthKitActivityAggregates.sampleKinds where progress.metrics[kind.metric] == nil {
            progress.metrics[kind.metric] = MetricProgress()
        }
        try save(progress, key: key)
        var processingComplete = true

        // Current readings lead the upload, so an initial history import never delays live totals.
        var recent: [FitFightHealthKitStepSync.ActivityDay] = []
        for kind in HealthKitActivityAggregates.totalKinds {
            try Task.checkCancellation()
            recent.append(contentsOf: try await HealthKitActivityAggregates.mergedDays(
                store: store, kind: kind, start: recentStart, end: cutoff,
                calendar: calendar, zeroDays: []
            ))
        }
        for offset in stride(from: 0, to: recent.count, by: 1_000) {
            let page = Array(recent[offset..<min(offset + 1_000, recent.count)])
            let pageProcessed = try await upload(
                totals: page, workouts: [], deletions: [], cutoff: cutoff,
                timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
            )
            processingComplete = pageProcessed.processed && processingComplete
            try save(progress, key: key)
        }

        for kind in HealthKitActivityAggregates.totalKinds {
            progress.metrics[kind.metric]?.acknowledgedThrough = cutoff
        }
        try save(progress, key: key)

        var workoutAnchor = readAnchor(progress.workoutAnchorData)
        while true {
            try Task.checkCancellation()
            let page = try await changes(
                store: store, type: .workoutType(), predicate: nil,
                anchor: workoutAnchor, limit: anchorPageSize
            )
            let deletions = page.deleted.map { $0.uuid.uuidString.lowercased() }
            let deleted = Set(deletions)
            let workouts = page.added.compactMap { $0 as? HKWorkout }
                .filter { !deleted.contains($0.uuid.uuidString.lowercased()) }
                .compactMap { HealthKitActivityAggregates.workoutRecord($0, end: cutoff) }
            let pageProcessed = try await upload(
                totals: [], workouts: workouts, deletions: deletions, cutoff: cutoff,
                timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
            )
            processingComplete = pageProcessed.processed && processingComplete
            workoutAnchor = page.anchor
            progress.workoutAnchorData = try archiveAnchor(workoutAnchor)
            try save(progress, key: key)
            if page.added.count + page.deleted.count < anchorPageSize { break }
        }

        let recentWorkouts = try await HealthKitActivityAggregates.workouts(
            store: store, start: recentStart, end: cutoff, limit: HKObjectQueryNoLimit
        )
        for offset in stride(from: 0, to: recentWorkouts.count, by: 200) {
            let pageProcessed = try await upload(
                totals: [], workouts: Array(recentWorkouts[offset..<min(offset + 200, recentWorkouts.count)]),
                deletions: [], cutoff: cutoff, timeZone: timeZone,
                api: api, session: session, trace: trace, userId: userId
            )
            processingComplete = pageProcessed.processed && processingComplete
        }

        for kind in HealthKitActivityAggregates.totalKinds {
            try Task.checkCancellation()
            var metric = progress.metrics[kind.metric]!
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
                            totals: rows, workouts: [], deletions: [], cutoff: cutoff,
                            timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
                        )
                        processingComplete = pageProcessed.processed && processingComplete
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

        }

        let affectedDateFormatter = ISO8601DateFormatter()
        affectedDateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        for kind in HealthKitActivityAggregates.sampleKinds {
            try Task.checkCancellation()
            var metric = progress.metrics[kind.metric]!
            var anchor = readAnchor(metric.anchorData)
            while true {
                try Task.checkCancellation()
                // No date predicate: an anchored change can concern any accessible historical day.
                let page = try await changes(
                    store: store, type: kind.type, predicate: nil,
                    anchor: anchor, limit: anchorPageSize
                )
                let deleted = Set(page.deleted.map { $0.uuid.uuidString.lowercased() })
                let samples = try page.added
                    .filter { !deleted.contains($0.uuid.uuidString.lowercased()) }
                    .map { try HealthKitActivityAggregates.sampleRecord($0, kind: kind) }
                let deletions = page.deleted.map {
                    FitFightHealthKitActivityBatch.DeletedSample(
                        healthkitUuid: $0.uuid.uuidString.lowercased(), metric: kind.metric
                    )
                }
                let pageResult = try await upload(
                    totals: [], workouts: [], deletions: [], samples: samples,
                    deletedSamples: deletions, cutoff: cutoff, timeZone: timeZone,
                    api: api, session: session, trace: trace, userId: userId
                )
                processingComplete = pageResult.processed && processingComplete

                if metric.sampleBootstrapComplete,
                   let totalKind = HealthKitActivityAggregates.totalKinds.first(where: { $0.metric == kind.metric }) {
                    var first = page.added.map(\.startDate).min()
                    var last = page.added.map(\.endDate).max()
                    for interval in pageResult.affectedSamples where interval.metric == kind.metric {
                        guard let start = affectedDateFormatter.date(from: interval.startsAt),
                              let end = affectedDateFormatter.date(from: interval.endsAt) else {
                            throw HealthKitActivityAggregates.SampleReadError.invalidSample
                        }
                        first = min(first ?? start, start)
                        last = max(last ?? end, end)
                    }
                    if !page.deleted.isEmpty && pageResult.affectedSamples.isEmpty {
                        first = metric.historyCursor ?? recentStart
                        last = cutoff
                    }
                    if let first, let last {
                        var cursor = calendar.startOfDay(for: first)
                        let lastDay = calendar.startOfDay(for: min(last, cutoff))
                        let affectedEnd = min(
                            calendar.date(byAdding: .day, value: 1, to: lastDay) ?? cutoff, cutoff
                        )
                        while cursor < affectedEnd {
                            try Task.checkCancellation()
                            let next = min(
                                calendar.date(byAdding: .day, value: historyPageDays, to: cursor) ?? affectedEnd,
                                affectedEnd
                            )
                            // An empty HealthKit read can mean revoked permission, so never infer zero.
                            let rows = try await HealthKitActivityAggregates.mergedDays(
                                store: store, kind: totalKind, start: cursor, end: next,
                                calendar: calendar, zeroDays: []
                            )
                            let totalResult = try await upload(
                                totals: rows, workouts: [], deletions: [], cutoff: cutoff,
                                timeZone: timeZone, api: api, session: session,
                                trace: trace, userId: userId
                            )
                            processingComplete = totalResult.processed && processingComplete
                            cursor = next
                        }
                    }
                }
                anchor = page.anchor
                metric.anchorData = try archiveAnchor(anchor)
                let caughtUp = page.added.count + page.deleted.count < anchorPageSize
                if caughtUp { metric.sampleBootstrapComplete = true }
                progress.metrics[kind.metric] = metric
                try save(progress, key: key)
                if caughtUp { break }
            }
        }
        return processingComplete
    }

    private static func upload(
        totals: [FitFightHealthKitStepSync.ActivityDay],
        workouts: [FitFightHealthKitStepSync.Workout],
        deletions: [String],
        samples: [FitFightHealthKitActivityBatch.Sample] = [],
        deletedSamples: [FitFightHealthKitActivityBatch.DeletedSample] = [],
        cutoff: Date,
        timeZone: TimeZone,
        api: FitFightAPI,
        session: SessionStore,
        trace: HealthKitSyncTrace,
        userId: UUID
    ) async throws -> (processed: Bool, affectedSamples: [FitFightHealthKitActivityResult.AffectedSample]) {
        guard !totals.isEmpty || !workouts.isEmpty || !deletions.isEmpty ||
              !samples.isEmpty || !deletedSamples.isEmpty else { return (true, []) }
        try Task.checkCancellation()
        guard session.authSession?.user.id == userId else { throw CancellationError() }
        let token = try await session.freshAccessToken()
        guard session.authSession?.user.id == userId else { throw CancellationError() }
        let batch = FitFightHealthKitActivityBatch(
            collectedAt: HealthKitStepAggregates.iso8601(cutoff),
            timeZone: timeZone.identifier,
            totals: totals,
            workouts: workouts,
            deletedWorkouts: deletions,
            samples: samples,
            deletedSamples: deletedSamples
        )
        let result = try await api.syncHealthKitActivity(batch, accessToken: token, trace: trace)
        return (result.processing == "processed", result.affectedSamples ?? [])
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

    private static func changes(
        store: HKHealthStore,
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?,
        limit: Int
    ) async throws -> (added: [HKSample], deleted: [HKDeletedObject], anchor: HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type, predicate: predicate, anchor: anchor, limit: limit
            ) { _, added, deleted, nextAnchor, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (added ?? [], deleted ?? [], nextAnchor)) }
            }
            store.execute(query)
        }
    }

    private static func readAnchor(_ data: Data?) -> HKQueryAnchor? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private static func archiveAnchor(_ anchor: HKQueryAnchor?) throws -> Data? {
        guard let anchor else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
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

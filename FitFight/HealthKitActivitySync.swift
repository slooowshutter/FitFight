import Foundation
import HealthKit

@MainActor
enum HealthKitActivitySync {
    private static let recentDayCount = 40
    private static let historyPageDays = 1_000
    private static let anchorPageSize = 100

    private struct MetricProgress: Codable {
        var predicateStart: Date
        var historyCursor: Date?
        var historyComplete = false
        var acknowledgedThrough: Date?
        var anchorData: Data?
        var knownDays: Set<String> = []
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
    ) async throws {
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

        for kind in HealthKitActivityAggregates.totalKinds where progress.metrics[kind.metric] == nil {
            progress.metrics[kind.metric] = MetricProgress(predicateStart: recentStart)
        }
        try save(progress, key: key)

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
            try await upload(
                totals: page, workouts: [], deletions: [], cutoff: cutoff,
                timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
            )
            for row in page {
                var metric = progress.metrics[row.metric]!
                metric.knownDays.insert(row.day)
                progress.metrics[row.metric] = metric
            }
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
            try await upload(
                totals: [], workouts: workouts, deletions: deletions, cutoff: cutoff,
                timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
            )
            workoutAnchor = page.anchor
            progress.workoutAnchorData = try archiveAnchor(workoutAnchor)
            try save(progress, key: key)
            if page.added.count + page.deleted.count < anchorPageSize { break }
        }

        let recentWorkouts = try await HealthKitActivityAggregates.workouts(
            store: store, start: recentStart, end: cutoff, limit: HKObjectQueryNoLimit
        )
        for offset in stride(from: 0, to: recentWorkouts.count, by: 200) {
            try await upload(
                totals: [], workouts: Array(recentWorkouts[offset..<min(offset + 200, recentWorkouts.count)]),
                deletions: [], cutoff: cutoff, timeZone: timeZone,
                api: api, session: session, trace: trace, userId: userId
            )
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
                        try await upload(
                            totals: rows, workouts: [], deletions: [], cutoff: cutoff,
                            timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
                        )
                        metric.knownDays.formUnion(rows.map(\.day))
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

            var anchor = readAnchor(metric.anchorData)
            while true {
                try Task.checkCancellation()
                let predicate = HKQuery.predicateForSamples(withStart: metric.predicateStart, end: nil)
                let page = try await changes(
                    store: store, type: kind.type, predicate: predicate,
                    anchor: anchor, limit: anchorPageSize
                )
                var first = page.added.map(\.startDate).min()
                var last = page.added.map(\.endDate).max()
                if !page.deleted.isEmpty {
                    first = metric.predicateStart
                    last = cutoff
                }
                if let first, let last {
                    var cursor = calendar.startOfDay(for: max(first, metric.predicateStart))
                    let lastDay = calendar.startOfDay(for: min(last, cutoff))
                    let affectedEnd = min(calendar.date(byAdding: .day, value: 1, to: lastDay) ?? cutoff, cutoff)
                    while cursor < affectedEnd {
                        try Task.checkCancellation()
                        let next = min(calendar.date(byAdding: .day, value: historyPageDays, to: cursor) ?? affectedEnd, affectedEnd)
                        let firstDay = HealthKitStepAggregates.dayStamp(cursor, calendar: calendar)
                        let finalDay = HealthKitStepAggregates.dayStamp(next.addingTimeInterval(-0.001), calendar: calendar)
                        let zeros = page.deleted.isEmpty ? Set<String>() : Set(metric.knownDays.filter {
                            $0 >= firstDay && $0 <= finalDay
                        })
                        let rows = try await HealthKitActivityAggregates.mergedDays(
                            store: store, kind: kind, start: cursor, end: next,
                            calendar: calendar, zeroDays: zeros
                        )
                        try await upload(
                            totals: rows, workouts: [], deletions: [], cutoff: cutoff,
                            timeZone: timeZone, api: api, session: session, trace: trace, userId: userId
                        )
                        metric.knownDays.formUnion(rows.map(\.day))
                        cursor = next
                    }
                }
                anchor = page.anchor
                metric.anchorData = try archiveAnchor(anchor)
                progress.metrics[kind.metric] = metric
                try save(progress, key: key)
                if page.added.count + page.deleted.count < anchorPageSize { break }
            }
        }
    }

    private static func upload(
        totals: [FitFightHealthKitStepSync.ActivityDay],
        workouts: [FitFightHealthKitStepSync.Workout],
        deletions: [String],
        cutoff: Date,
        timeZone: TimeZone,
        api: FitFightAPI,
        session: SessionStore,
        trace: HealthKitSyncTrace,
        userId: UUID
    ) async throws {
        guard !totals.isEmpty || !workouts.isEmpty || !deletions.isEmpty else { return }
        try Task.checkCancellation()
        guard session.authSession?.user.id == userId else { throw CancellationError() }
        let token = try await session.freshAccessToken()
        guard session.authSession?.user.id == userId else { throw CancellationError() }
        let batch = FitFightHealthKitActivityBatch(
            collectedAt: HealthKitStepAggregates.iso8601(cutoff),
            timeZone: timeZone.identifier,
            totals: totals,
            workouts: workouts,
            deletedWorkouts: deletions
        )
        _ = try await api.syncHealthKitActivity(batch, accessToken: token, trace: trace)
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
        UserDefaults.standard.set(try JSONEncoder().encode(progress), forKey: key)
    }
}

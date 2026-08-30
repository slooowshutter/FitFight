import Combine
import Foundation
import HealthKit

@MainActor
final class HealthKitStepsStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case reading
        case steps(count: Int, sources: [String])
        case empty
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var connection = HealthKitConnectionState.notConnected
    @Published private(set) var backgroundDeliveryUnavailable = false

    private let store = HKHealthStore()
    private let api = FitFightAPI()
    private let uploader = HealthKitTUSUploader()
    private let askedKey = "ff.healthkit.stepsAsked"
    private var isUploading = false
    private var observerQuery: HKObserverQuery?
    private weak var session: SessionStore?
    private var failureContext = "Apple Health sync failed"

    var hasAsked: Bool {
        UserDefaults.standard.bool(forKey: askedKey)
    }

    var detailText: String {
        switch connection {
        case .notConnected: return "Not connected"
        case .syncing: return "Syncing history…"
        case .upToDate:
            return backgroundDeliveryUnavailable
                ? "Up to date · Background sync unavailable"
                : "Up to date"
        case .noAccessibleSteps: return "No accessible Steps"
        case .syncFailed: return "\(failureContext) — tap to retry"
        case .archiveTooLarge: return "Archive too large"
        }
    }

    var metaText: String {
        switch status {
        case .steps(let count, let sources):
            let sourceText = sources.isEmpty ? "" : " · \(sources.joined(separator: ", "))"
            return "\(Self.format(count)) steps today\(sourceText)"
        default:
            return ""
        }
    }

    var isConnected: Bool {
        connection != .notConnected
    }

    func configure(session: SessionStore) {
        self.session = session
        registerObserverIfPossible()
    }

    func refresh(requestAccess: Bool) async {
        guard
            HKHealthStore.isHealthDataAvailable(),
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else {
            if requestAccess || hasAsked { status = .empty }
            return
        }

        if requestAccess {
            do {
                try await store.requestAuthorization(toShare: [], read: [stepsType])
            } catch {
                status = .empty
            }
            UserDefaults.standard.set(true, forKey: askedKey)
        }
        guard requestAccess || hasAsked else { return }

        status = .reading
        do {
            if let result = try await Self.todayAggregate(store: store, type: stepsType) {
                status = .steps(count: result.count, sources: result.sources)
            } else {
                status = .empty
            }
        } catch {
            status = .empty
        }
        registerObserverIfPossible()
    }

    @discardableResult
    func syncToBackend(session: SessionStore) async -> Bool {
        guard hasAsked, !isUploading, api.isConfigured else { return false }
        guard
            HKHealthStore.isHealthDataAvailable(),
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount),
            let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        else { return false }

        isUploading = true
        connection = .syncing
        failureContext = "Apple Health sync failed"
        defer { isUploading = false }

        do {
            failureContext = "Couldn’t load saved Apple Health sync"
            var state = try HealthKitUploadState.load(userId: userId)
            if state.uploadId == nil {
                failureContext = "Couldn’t load sync details from FitFight"
                let accessToken = try await session.freshAccessToken()
                let context = try await api.healthKitUploadContext(accessToken: accessToken)
                let uploadId = UUID()
                failureContext = "Couldn’t prepare Apple Health data"
                guard let archive = try await HealthKitStepArchive.prepare(
                    store: store,
                    type: stepsType,
                    userId: userId,
                    uploadId: uploadId,
                    activeAnchorData: state.activeAnchor,
                    previousEarliestSample: state.earliestSample,
                    fightWindows: context.fightWindows
                ) else {
                    state.connection = .noAccessibleSteps
                    try state.save(userId: userId)
                    connection = .noAccessibleSteps
                    return true
                }
                state.connection = .syncing
                state.candidateAnchor = archive.candidateAnchor
                state.uploadId = uploadId
                state.archivePath = archive.url.path
                state.byteSize = archive.byteSize
                state.sha256 = archive.sha256
                state.phase = .archived
                state.earliestSample = archive.earliestSample
                failureContext = "Couldn’t save Apple Health sync progress"
                try state.save(userId: userId)
            }

            try await resume(state: &state, userId: userId, session: session)
            return true
        } catch HealthKitStepArchiveError.archiveTooLarge {
            connection = .archiveTooLarge
            var state = try? HealthKitUploadState.load(userId: userId)
            state?.connection = .archiveTooLarge
            try? state?.save(userId: userId)
            return false
        } catch {
            if let apiError = error as? FitFightAPIError {
                switch apiError {
                case .notConfigured:
                    failureContext = "FitFight sync server isn’t configured"
                case .http(let status, _):
                    if status == 401 {
                        failureContext = "Your FitFight session expired"
                    } else {
                        failureContext += " (server \(status))"
                    }
                case .decoding:
                    failureContext += ": unreadable server response"
                }
            } else if error is URLError {
                failureContext += ": network unavailable"
            }
            connection = .syncFailed
            var state = try? HealthKitUploadState.load(userId: userId)
            state?.connection = .syncFailed
            try? state?.save(userId: userId)
            return state?.uploadId != nil
        }
    }

    private func resume(
        state: inout HealthKitUploadState,
        userId: UUID,
        session: SessionStore
    ) async throws {
        guard let uploadId = state.uploadId,
              let archivePath = state.archivePath,
              let byteSize = state.byteSize,
              let sha256 = state.sha256 else {
            failureContext = "Saved Apple Health sync is incomplete"
            throw FitFightProviderUploadError.invalidLocalState
        }

        if state.phase != .archived {
            failureContext = "Couldn’t check Apple Health upload status"
            let token = try await session.freshAccessToken()
            let status = try await api.providerUploadStatus(
                uploadId: uploadId,
                accessToken: token
            )
            if status.status == "completed" {
                try state.complete(userId: userId)
                connection = .upToDate
                return
            }
            if status.status == "rejected" {
                uploader.discard(taskId: state.tusTaskId)
                try state.discardPending(userId: userId)
                throw FitFightProviderUploadError.serverRejected(status.errorCode)
            }
            if status.status == "processing" {
                state.phase = .processing
                try state.save(userId: userId)
                connection = .syncing
                return
            }
            if status.status == "committed" {
                state.phase = .committed
                try state.save(userId: userId)
            } else if status.status == "retryable_failure" {
                if status.errorCode == "archive_not_found" {
                    uploader.discard(taskId: state.tusTaskId)
                    state.tusTaskId = nil
                    state.phase = .issued
                } else {
                    state.phase = .uploaded
                }
                try state.save(userId: userId)
            }
        }

        if state.phase == .archived || state.phase == .issued || state.phase == .uploading {
            failureContext = "Couldn’t authorize Apple Health upload"
            let token = try await session.freshAccessToken()
            let capability = try await api.createProviderUpload(
                FitFightProviderUploadCreate(
                    uploadId: uploadId,
                    byteSize: byteSize,
                    sha256: sha256
                ),
                accessToken: token
            )
            state.phase = .issued
            try state.save(userId: userId)
            do {
                failureContext = "Couldn’t upload Apple Health data"
                try await uploader.upload(
                    fileURL: URL(fileURLWithPath: archivePath),
                    capability: capability,
                    userId: userId,
                    existingTaskId: state.tusTaskId
                ) { taskId in
                    state.tusTaskId = taskId
                    state.phase = .uploading
                    try state.save(userId: userId)
                }
            } catch HealthKitTUSError.missingResumeState {
                let recoveryToken = try await session.freshAccessToken()
                var recovered = try? await api.processProviderUpload(
                    uploadId: uploadId,
                    accessToken: recoveryToken
                )
                if recovered?.status == "committed" {
                    let cleanupToken = try await session.freshAccessToken()
                    recovered = try? await api.processProviderUpload(
                        uploadId: uploadId,
                        accessToken: cleanupToken
                    )
                }
                if recovered?.status == "completed", recovered?.receipt != nil {
                    try state.complete(userId: userId)
                    connection = .upToDate
                    return
                }
                state.tusTaskId = nil
                try state.save(userId: userId)
                failureContext = "Couldn’t restart Apple Health upload"
                try await uploader.upload(
                    fileURL: URL(fileURLWithPath: archivePath),
                    capability: capability,
                    userId: userId,
                    existingTaskId: nil
                ) { taskId in
                    state.tusTaskId = taskId
                    state.phase = .uploading
                    try state.save(userId: userId)
                }
            }
            state.phase = .uploaded
            try state.save(userId: userId)
        }

        state.phase = .processing
        try state.save(userId: userId)
        failureContext = "Couldn’t process Apple Health data"
        var token = try await session.freshAccessToken()
        var processed = try await api.processProviderUpload(
            uploadId: uploadId,
            accessToken: token
        )
        if processed.status == "committed" {
            state.phase = .committed
            try state.save(userId: userId)
            token = try await session.freshAccessToken()
            processed = try await api.processProviderUpload(
                uploadId: uploadId,
                accessToken: token
            )
        }
        guard processed.status == "completed", processed.receipt != nil else {
            throw FitFightProviderUploadError.notCompleted(processed.status, processed.errorCode)
        }
        state.phase = .completed
        try state.complete(userId: userId)
        connection = .upToDate
    }

    private func registerObserverIfPossible() {
        guard hasAsked, observerQuery == nil,
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let query = HKObserverQuery(sampleType: stepsType, predicate: nil) { [weak self] _, completion, _ in
            Task { @MainActor [weak self] in
                guard let self, let session = self.session else {
                    completion()
                    return
                }
                while self.isUploading {
                    try? await Task.sleep(for: .milliseconds(250))
                }
                _ = await self.syncToBackend(session: session)
                completion()
            }
        }
        observerQuery = query
        store.execute(query)
        store.enableBackgroundDelivery(for: stepsType, frequency: .immediate) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                self?.backgroundDeliveryUnavailable = !success
            }
        }
    }

    private struct TodayAggregate {
        var count: Int
        var sources: [String]
    }

    private static func todayAggregate(
        store: HKHealthStore,
        type: HKQuantityType
    ) async throws -> TodayAggregate? {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(
            withStart: start,
            end: now,
            options: .strictStartDate
        )
        let samplePredicate = HKSamplePredicate.quantitySample(type: type, predicate: predicate)
        let mergedDescriptor = HKStatisticsQueryDescriptor(
            predicate: samplePredicate,
            options: [.cumulativeSum]
        )
        let sourceDescriptor = HKStatisticsQueryDescriptor(
            predicate: samplePredicate,
            options: [.cumulativeSum, .separateBySource]
        )
        guard let mergedStats = try await mergedDescriptor.result(for: store) else { return nil }
        let sourceStats = try await sourceDescriptor.result(for: store)
        let value = mergedStats.sumQuantity()?.doubleValue(for: .count()) ?? 0
        var seen = Set<String>()
        let labels = (sourceStats?.sources ?? []).compactMap { source -> String? in
            let name = source.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return name
        }
        if value <= 0 && labels.isEmpty { return nil }
        return TodayAggregate(count: Int(value.rounded()), sources: labels)
    }

    private static func format(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }
}

private enum FitFightProviderUploadError: Error {
    case invalidLocalState
    case serverRejected(String?)
    case notCompleted(String, String?)
}

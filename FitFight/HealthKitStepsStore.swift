import Combine
import Foundation
import HealthKit
import OSLog
import UIKit

@MainActor
final class HealthKitStepsStore: ObservableObject {
    enum Status: Equatable { case idle, reading, steps(count: Int), empty }
    enum SyncTrigger: String, Codable { case observer, foreground, manual }
    enum BackgroundRefreshStatus: String, Codable { case available, denied, restricted }
    enum DeliveryRegistrationStatus: String, Codable { case enabled, unavailable }
    enum SyncErrorCode: String, Codable {
        case authenticationUnavailable = "authentication_unavailable"
        case networkUnavailable = "network_unavailable"
        case protectedDataUnavailable = "protected_data_unavailable"
        case attemptExpired = "attempt_expired"
        case healthKitUnavailable = "healthkit_unavailable"
        case backgroundDeliveryUnavailable = "background_delivery_unavailable"
        case syncFailed = "sync_failed"
    }

    struct Diagnostics: Codable, Equatable {
        var backgroundRefreshStatus: BackgroundRefreshStatus
        var deliveryRegistrationStatus: DeliveryRegistrationStatus
        var lastObserverWake: Date?
        var lastSyncAttempt: Date?
        var lastAutomaticSync: Date?
        var lastManualSync: Date?
        var lastTrigger: SyncTrigger?
        var errorCode: SyncErrorCode?
        var failureReference: String?
        var failureDetail: String?

        @MainActor static var current: Diagnostics {
            Diagnostics(
                backgroundRefreshStatus: HealthKitStepsStore.backgroundRefreshStatus,
                deliveryRegistrationStatus: .unavailable,
                lastObserverWake: nil,
                lastSyncAttempt: nil,
                lastAutomaticSync: nil,
                lastManualSync: nil,
                lastTrigger: nil,
                errorCode: nil,
                failureReference: nil,
                failureDetail: nil
            )
        }
    }

    static let shared = HealthKitStepsStore()

    @Published private(set) var status: Status = .idle
    @Published private(set) var connection = HealthKitConnectionState.notConnected
    @Published private(set) var diagnostics = Diagnostics.current

    private let store = HKHealthStore()
    private let api = FitFightAPI()
    private let uploader = HealthKitTUSUploader()
    private var inFlightSync: Task<Bool, Never>?
    private var observerQuery: HKObserverQuery?
    private weak var session: SessionStore?
    var onBackendSync: (@MainActor () async -> Void)?
    private var activeUserId: UUID?
    private static let pendingLocalDeletionKey = "ff.healthkit.pendingLocalDeletion"
    private static let pendingSyncKey = "ff.healthkit.pendingSync"
    private static let diagnosticsPrefix = "ff.healthkit.diagnostics."
    private static let logger = Logger(subsystem: "com.fitfight.mvp", category: "HealthKitDiagnostics")

    var hasAsked: Bool {
        guard let activeUserId else { return false }
        return UserDefaults.standard.bool(forKey: Self.askedKey(userId: activeUserId))
    }

    #if DEBUG && targetEnvironment(simulator)
    func setCompanionPreviewStatus(_ value: Status) {
        guard CompanionPreview.isEnabled else { return }
        status = value
    }
    #endif

    var detailText: String {
        switch connection {
        case .notConnected: return String(appLocalized: "Not connected")
        case .syncing: return String(appLocalized: "Syncing Steps…")
        case .upToDate:
            return diagnostics.deliveryRegistrationStatus == .unavailable
                ? String(appLocalized: "Up to date · Background sync unavailable")
                : String(appLocalized: "Up to date")
        case .noAccessibleSteps: return String(appLocalized: "No accessible Steps")
        case .syncFailed:
            return diagnostics.failureDetail ?? String(appLocalized: "Sync failed. Tap to retry.")
        }
    }

    var metaText: String {
        switch status {
        case .steps(let count):
            // NOTE: The catalog string uses %lld and pluralizes on the integer.
            // `format: .number` passes a FormatStyle value, so %lld printed garbage.
            return String(
                appLocalized: "health.steps-today",
                defaultValue: "\(count) steps today"
            )
        default:
            return ""
        }
    }

    var isConnected: Bool { connection != .notConnected }

    var backgroundRefreshText: String {
        switch diagnostics.backgroundRefreshStatus {
        case .available: return String(appLocalized: "Available")
        case .denied: return String(appLocalized: "Denied")
        case .restricted: return String(appLocalized: "Restricted by this device")
        }
    }

    var backgroundDeliveryText: String {
        diagnostics.deliveryRegistrationStatus == .enabled
            ? String(appLocalized: "Enabled")
            : String(appLocalized: "Unavailable")
    }

    var currentFailureText: String? {
        if let detail = diagnostics.failureDetail, !detail.isEmpty {
            return detail
        }
        return diagnostics.errorCode.map(Self.fallbackMessage)
    }

    func installObserverAtLaunch() {
        guard !CompanionPreview.isEnabled else { return }
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else {
            if !HKHealthStore.isHealthDataAvailable() {
                updateDiagnostics { $0.errorCode = .healthKitUnavailable }
            }
            return
        }

        if observerQuery == nil {
            let query = HKObserverQuery(sampleType: stepsType, predicate: nil) { [weak self] _, completion, _ in
                let gate = ObserverCompletion(completion)
                Task { @MainActor [weak self] in
                    guard let self else { gate.finish(); return }
                    let trace = HealthKitSyncTrace(trigger: .observer)
                    UserDefaults.standard.set(true, forKey: Self.pendingSyncKey)
                    self.updateDiagnostics {
                        $0.lastObserverWake = Date()
                        $0.lastTrigger = .observer
                    }
                    guard UIApplication.shared.isProtectedDataAvailable else {
                        self.updateDiagnostics { $0.errorCode = .protectedDataUnavailable }
                        trace.fail(.protectedDataUnavailable)
                        _ = trace.finish()
                        gate.finish()
                        return
                    }
                    guard self.hasAsked else { _ = trace.finish(); gate.finish(); return }
                    guard let session = self.session,
                          session.authSession != nil || session.client.auth.currentUser != nil else {
                        self.updateDiagnostics { $0.errorCode = .authenticationUnavailable }
                        trace.fail(.authenticationUnavailable)
                        _ = trace.finish()
                        gate.finish()
                        return
                    }
                    let userID = self.activeUserId
                    let operation = Task { @MainActor in
                        _ = await self.syncToBackend(session: session, trigger: .observer, trace: trace)
                        self.completeAttempt(trace, session: session, userID: userID)
                        gate.finish()
                    }
                    Task { @MainActor in
                        do { try await Task.sleep(for: .seconds(25)) } catch { return }
                        guard !gate.isFinished else { return }
                        operation.cancel()
                        if self.activeUserId == userID {
                            UserDefaults.standard.set(true, forKey: Self.pendingSyncKey)
                            self.updateDiagnostics { $0.errorCode = .attemptExpired }
                        }
                        self.completeAttempt(trace, session: session, userID: userID, cancelled: true)
                        gate.finish()
                    }
                }
            }
            observerQuery = query
            store.execute(query)
        }
        store.enableBackgroundDelivery(for: stepsType, frequency: .immediate) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                self?.updateDiagnostics {
                    $0.deliveryRegistrationStatus = success ? .enabled : .unavailable
                    if success, $0.errorCode == .backgroundDeliveryUnavailable {
                        $0.errorCode = nil
                    } else if !success {
                        $0.errorCode = .backgroundDeliveryUnavailable
                    }
                }
            }
        }
    }

    func configure(session: SessionStore) {
        guard !CompanionPreview.isEnabled else { return }
        self.session = session
        if let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id {
            activate(userId: userId)
        }
        if let rawUserId = UserDefaults.standard.string(forKey: Self.pendingLocalDeletionKey),
           let userId = UUID(uuidString: rawUserId) {
            Task { _ = await deleteLocalData(userId: userId) }
        }
    }

    func activate(userId: UUID?) {
        guard !CompanionPreview.isEnabled else { return }
        guard activeUserId != userId else { refreshBackgroundStatus(); return }
        activeUserId = userId
        status = .idle
        connection = .notConnected
        if let userId,
           let data = UserDefaults.standard.data(forKey: Self.diagnosticsKey(userId: userId)),
           let saved = try? JSONDecoder().decode(Diagnostics.self, from: data) {
            diagnostics = saved
            refreshBackgroundStatus()
        } else {
            diagnostics = .current
        }
    }

    func deleteLocalData(userId: UUID) async -> Bool {
        UserDefaults.standard.set(userId.uuidString, forKey: Self.pendingLocalDeletionKey)
        await uploader.discardLegacy(userId: userId)
        do { try HealthKitUploadState.discardLegacy(userId: userId) } catch { return false }
        UserDefaults.standard.removeObject(forKey: Self.askedKey(userId: userId))
        UserDefaults.standard.removeObject(forKey: Self.diagnosticsKey(userId: userId))
        UserDefaults.standard.removeObject(forKey: Self.pendingSyncKey)
        UserDefaults.standard.removeObject(forKey: Self.pendingLocalDeletionKey)
        let cleanupActiveUserId = activeUserId
        if cleanupActiveUserId == userId || cleanupActiveUserId == nil {
            if let observerQuery {
                store.stop(observerQuery)
                self.observerQuery = nil
            }
            if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
                await withCheckedContinuation { continuation in
                    store.disableBackgroundDelivery(for: stepsType) { _, _ in continuation.resume() }
                }
            }
            guard activeUserId == cleanupActiveUserId else { installObserverAtLaunch(); return true }
            status = .idle
            connection = .notConnected
            diagnostics = .current
        }
        return true
    }

    func refresh(requestAccess: Bool, trace: HealthKitSyncTrace) async {
        let userID = activeUserId
        refreshBackgroundStatus()
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount)
        else {
            updateDiagnostics { $0.errorCode = .healthKitUnavailable }
            trace.fail(.healthKitUnavailable)
            if requestAccess || hasAsked { status = .empty }
            return
        }
        if requestAccess {
            do {
                try await trace.measure(.authorization) {
                    try await store.requestAuthorization(
                    toShare: [],
                    read: HealthKitActivityAggregates.readTypes
                )
                }
            } catch {
                trace.fail(Self.errorCode(for: error))
                if activeUserId == userID { status = .empty }
            }
            guard activeUserId == userID else { trace.fail(.attemptExpired); return }
            if let activeUserId {
                UserDefaults.standard.set(true, forKey: Self.askedKey(userId: activeUserId))
            }
            installObserverAtLaunch()
        }
        guard requestAccess || hasAsked else { return }
        status = .reading
        do {
            try Task.checkCancellation()
            let count = try await trace.measure(.todayTotal) {
                try await Self.todayTotal(store: store, type: stepsType)
            }
            try Task.checkCancellation()
            guard activeUserId == userID else { trace.fail(.attemptExpired); return }
            if let count {
                status = .steps(count: count)
            } else {
                status = .empty
            }
        } catch {
            trace.fail(Self.errorCode(for: error))
            if activeUserId == userID { status = .empty }
        }
    }

    @discardableResult
    func syncToBackend(
        session: SessionStore,
        trigger: SyncTrigger,
        trace: HealthKitSyncTrace,
        coalesceInFlight: Bool = true
    ) async -> Bool {
        guard !CompanionPreview.isEnabled else { return false }
        if let inFlightSync {
            if coalesceInFlight {
                return await inFlightSync.value
            }
            _ = await inFlightSync.value
        }
        let work = Task { @MainActor in
            defer { self.inFlightSync = nil }
            return await self.performSyncToBackend(session: session, trigger: trigger, trace: trace)
        }
        inFlightSync = work
        return await work.value
    }

    private func performSyncToBackend(
        session: SessionStore,
        trigger: SyncTrigger,
        trace: HealthKitSyncTrace
    ) async -> Bool {
        guard hasAsked, api.isConfigured else {
            if trigger == .observer { updateDiagnostics { $0.errorCode = .authenticationUnavailable } }
            return false
        }
        guard UIApplication.shared.isProtectedDataAvailable else {
            updateDiagnostics { $0.errorCode = .protectedDataUnavailable }
            trace.fail(.protectedDataUnavailable)
            return false
        }
        guard HKHealthStore.isHealthDataAvailable(),
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount),
              let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        else {
            updateDiagnostics { $0.errorCode = .healthKitUnavailable }
            trace.fail(.healthKitUnavailable)
            return false
        }

        connection = .syncing
        updateDiagnostics { $0.lastSyncAttempt = Date(); $0.lastTrigger = trigger }
        do {
            try await trace.measure(.localState) {
                await uploader.discardLegacy(userId: userId)
                try HealthKitUploadState.discardLegacy(userId: userId)
            }
            try Task.checkCancellation()
            let contextToken = try await trace.measure(.session) { try await session.freshAccessToken() }
            guard activeUserId == userId, session.authSession?.user.id == userId else { throw CancellationError() }
            let context = try await api.healthKitUploadContext(accessToken: contextToken, trace: trace)
            var sync = try await HealthKitStepAggregates.read(
                store: store,
                type: stepsType,
                context: context,
                trace: trace
            )
            let activity = await trace.measure(.healthKitActivity) {
                await HealthKitActivityAggregates.read(store: store, context: context)
            }
            sync.activityDays = activity.days
            sync.workouts = activity.workouts
            try Task.checkCancellation()
            let syncToken = try await trace.measure(.session) { try await session.freshAccessToken() }
            guard activeUserId == userId, session.authSession?.user.id == userId else { throw CancellationError() }
            do {
                _ = try await api.syncHealthKitSteps(sync, accessToken: syncToken, trace: trace)
            } catch {
                guard sync.activityDays != nil || sync.workouts != nil else { throw error }
                Self.logger.error("healthkit_extras_dropped retrying_steps_only")
                var stepsOnly = sync
                stepsOnly.activityDays = nil
                stepsOnly.workouts = nil
                _ = try await api.syncHealthKitSteps(stepsOnly, accessToken: syncToken, trace: trace)
            }
            try Task.checkCancellation()
            guard activeUserId == userId else { throw CancellationError() }
            connection = .upToDate
            UserDefaults.standard.removeObject(forKey: Self.pendingSyncKey)
            updateDiagnostics {
                if trigger == .observer { $0.lastAutomaticSync = Date() }
                else { $0.lastManualSync = Date() }
                $0.errorCode = nil
                $0.failureReference = nil
                $0.failureDetail = nil
            }
            if trigger == .observer {
                await onBackendSync?()
            }
            return true
        } catch {
            let code = Self.errorCode(for: error)
            let detail = Self.failureDetail(for: error)
            trace.fail(code)
            guard activeUserId == userId else { return false }
            if case HealthKitStepAggregates.ReadError.noAccessibleSteps = error {
                connection = .noAccessibleSteps
            } else {
                connection = .syncFailed
            }
            UserDefaults.standard.set(true, forKey: Self.pendingSyncKey)
            updateDiagnostics {
                $0.errorCode = code
                $0.failureDetail = detail
            }
            Self.logger.error("healthkit_sync_failed code=\(code.rawValue, privacy: .public) detail=\(detail, privacy: .public)")
            return false
        }
    }

    private func refreshBackgroundStatus() {
        updateDiagnostics { $0.backgroundRefreshStatus = Self.backgroundRefreshStatus }
    }

    private func updateDiagnostics(_ update: (inout Diagnostics) -> Void) {
        var next = diagnostics
        update(&next)
        diagnostics = next
        guard let activeUserId, let data = try? JSONEncoder().encode(next) else { return }
        UserDefaults.standard.set(data, forKey: Self.diagnosticsKey(userId: activeUserId))
    }

    func completeAttempt(
        _ trace: HealthKitSyncTrace,
        session: SessionStore,
        userID: UUID?,
        cancelled: Bool = false
    ) {
        guard let attempt = trace.finish(cancelled: cancelled || Task.isCancelled), let userID,
              activeUserId == userID, session.authSession?.user.id == userID else { return }
        if attempt.outcome != .succeeded {
            let stage = attempt.stages.last(where: { $0.outcome != .succeeded })
            let reference = [
                String(attempt.attemptId.uuidString.prefix(8)).lowercased(),
                stage?.stage.rawValue,
                stage?.error?.reference ?? attempt.errorCode?.rawValue,
            ].compactMap { $0 }.joined(separator: " · ")
            updateDiagnostics {
                $0.errorCode = attempt.errorCode ?? .syncFailed
                $0.failureReference = reference
                if $0.failureDetail == nil || $0.failureDetail?.isEmpty == true {
                    $0.failureDetail = Self.fallbackMessage(for: attempt.errorCode ?? .syncFailed)
                }
            }
        }
        let snapshot = FitFightHealthKitDiagnosticSnapshot(diagnostics, attempts: [attempt])
        Task { await reportDiagnostics(snapshot, session: session, userID: userID) }
    }

    private func reportDiagnostics(
        _ snapshot: FitFightHealthKitDiagnosticSnapshot,
        session: SessionStore,
        userID: UUID
    ) async {
        guard api.isConfigured, activeUserId == userID, session.authSession?.user.id == userID else { return }
        do {
            let token = try await session.freshAccessToken()
            guard activeUserId == userID, session.authSession?.user.id == userID else { return }
            _ = try await api.saveHealthKitDiagnostics(snapshot, accessToken: token)
        } catch {
            let failure = HealthKitSyncTrace.Failure(error)
            let reference = snapshot.attempts.first?.attemptId.uuidString.lowercased() ?? "snapshot"
            Self.logger.error("diagnostics_delivery_failed trace_id=\(reference, privacy: .public) error=\(failure.reference, privacy: .public)")
        }
    }

    private static var backgroundRefreshStatus: BackgroundRefreshStatus {
        switch UIApplication.shared.backgroundRefreshStatus {
        case .available: return .available
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .restricted
        }
    }

    static func fallbackMessage(for code: SyncErrorCode) -> String {
        switch code {
        case .authenticationUnavailable: return String(appLocalized: "Sign in, then open FitFight to sync.")
        case .networkUnavailable: return String(appLocalized: "Connect to the internet, then open FitFight.")
        case .protectedDataUnavailable: return String(appLocalized: "Unlock your iPhone, then open FitFight.")
        case .attemptExpired: return String(appLocalized: "Open FitFight to finish syncing.")
        case .healthKitUnavailable: return String(appLocalized: "Apple Health isn’t available on this device.")
        case .backgroundDeliveryUnavailable: return String(appLocalized: "Open FitFight to sync your Steps.")
        case .syncFailed: return String(appLocalized: "Sync failed. Tap to retry.")
        }
    }

    static func errorCode(for error: Error) -> SyncErrorCode {
        if error is CancellationError { return .attemptExpired }
        if let urlError = error as? URLError,
           [.notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost,
            .cannotFindHost, .timedOut].contains(urlError.code) { return .networkUnavailable }
        if case FitFightAPIError.http(let status, _, _) = error, status == 401 {
            return .authenticationUnavailable
        }
        return .syncFailed
    }

    private static func failureDetail(for error: Error) -> String {
        if case HealthKitStepAggregates.ReadError.noAccessibleSteps = error {
            return String(appLocalized: "No accessible Steps")
        }
        let retry = String(appLocalized: "Tap to retry")
        if case FitFightAPIError.http(let status, _, _) = error, status >= 500 {
            let saved = String(
                appLocalized: "health.sync-server-failed",
                defaultValue: "FitFight's server could not save your Steps (error \(status))."
            )
            return "\(saved) \(retry)"
        }
        if let api = error as? FitFightAPIError, let description = api.errorDescription, !description.isEmpty {
            var text = description.trimmingCharacters(in: .whitespaces)
            if let last = text.last, !".!?".contains(last) {
                text += "."
            }
            return "\(text) \(retry)"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return String(appLocalized: "No internet connection. Tap to retry.")
            case .timedOut:
                return String(appLocalized: "The server took too long. Tap to retry.")
            default:
                break
            }
        }
        return String(appLocalized: "Sync failed. Tap to retry.")
    }

    private static func todayTotal(store: HKHealthStore, type: HKQuantityType) async throws -> Int? {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate), options: [.cumulativeSum]
        )
        guard let statistics = try await descriptor.result(for: store) else { return nil }
        guard let count = HealthKitStepAggregates.integerCount(from: statistics.sumQuantity()),
              count > 0 else { return nil }
        return count
    }

    private static func askedKey(userId: UUID) -> String {
        "ff.healthkit.stepsAsked.\(userId.uuidString.lowercased())"
    }

    private static func diagnosticsKey(userId: UUID) -> String {
        diagnosticsPrefix + userId.uuidString.lowercased()
    }
}

private final class ObserverCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false
    private let completion: () -> Void

    init(_ completion: @escaping () -> Void) { self.completion = completion }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    func finish() {
        lock.lock()
        guard !completed else { lock.unlock(); return }
        completed = true
        lock.unlock()
        completion()
    }
}

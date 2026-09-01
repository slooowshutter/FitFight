import Combine
import Foundation
import HealthKit

@MainActor
final class HealthKitStepsStore: ObservableObject {
    enum Status: Equatable {
        case idle
        case reading
        case steps(count: Int)
        case empty
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var connection = HealthKitConnectionState.notConnected
    @Published private(set) var backgroundDeliveryUnavailable = false

    private let store = HKHealthStore()
    private let api = FitFightAPI()
    private let uploader = HealthKitTUSUploader()
    private var isSyncing = false
    private var observerQuery: HKObserverQuery?
    private weak var session: SessionStore?
    private var activeUserId: UUID?
    private static let pendingLocalDeletionKey = "ff.healthkit.pendingLocalDeletion"

    var hasAsked: Bool {
        guard let activeUserId else { return false }
        return UserDefaults.standard.bool(forKey: Self.askedKey(userId: activeUserId))
    }

    var detailText: String {
        switch connection {
        case .notConnected: return "Not connected"
        case .syncing: return "Syncing Steps…"
        case .upToDate:
            return backgroundDeliveryUnavailable
                ? "Up to date · Background sync unavailable"
                : "Up to date"
        case .noAccessibleSteps: return "No accessible Steps"
        case .syncFailed: return "Sync failed — tap to retry"
        }
    }

    var metaText: String {
        switch status {
        case .steps(let count):
            return "\(Self.format(count)) steps today"
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
        if let rawUserId = UserDefaults.standard.string(forKey: Self.pendingLocalDeletionKey),
           let userId = UUID(uuidString: rawUserId) {
            Task { _ = await deleteLocalData(userId: userId) }
        }
    }

    func activate(userId: UUID?) {
        guard activeUserId != userId else { return }
        activeUserId = userId
        status = .idle
        connection = .notConnected
    }

    func deleteLocalData(userId: UUID) async -> Bool {
        UserDefaults.standard.set(userId.uuidString, forKey: Self.pendingLocalDeletionKey)
        await uploader.discardLegacy(userId: userId)
        do {
            try HealthKitUploadState.discardLegacy(userId: userId)
        } catch {
            return false
        }
        UserDefaults.standard.removeObject(forKey: Self.askedKey(userId: userId))
        UserDefaults.standard.removeObject(forKey: Self.pendingLocalDeletionKey)
        let cleanupActiveUserId = activeUserId
        if cleanupActiveUserId == userId || cleanupActiveUserId == nil {
            if let observerQuery {
                store.stop(observerQuery)
                self.observerQuery = nil
            }
            if let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) {
                await withCheckedContinuation { continuation in
                    store.disableBackgroundDelivery(for: stepsType) { _, _ in
                        continuation.resume()
                    }
                }
            }
            guard activeUserId == cleanupActiveUserId else {
                registerObserverIfPossible()
                return true
            }
            status = .idle
            connection = .notConnected
        }
        return true
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
            if let activeUserId {
                UserDefaults.standard.set(true, forKey: Self.askedKey(userId: activeUserId))
            }
        }
        guard requestAccess || hasAsked else { return }

        status = .reading
        do {
            if let count = try await Self.todayTotal(store: store, type: stepsType) {
                status = .steps(count: count)
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
        guard hasAsked, !isSyncing, api.isConfigured else { return false }
        guard
            HKHealthStore.isHealthDataAvailable(),
            let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount),
            let userId = session.authSession?.user.id ?? session.client.auth.currentUser?.id
        else { return false }

        isSyncing = true
        connection = .syncing
        defer { isSyncing = false }

        do {
            await uploader.discardLegacy(userId: userId)
            try HealthKitUploadState.discardLegacy(userId: userId)
            let contextToken = try await session.freshAccessToken()
            let context = try await api.healthKitUploadContext(accessToken: contextToken)
            let sync = try await HealthKitStepAggregates.read(
                store: store,
                type: stepsType,
                context: context
            )
            let syncToken = try await session.freshAccessToken()
            _ = try await api.syncHealthKitSteps(sync, accessToken: syncToken)
            connection = .upToDate
            return true
        } catch {
            connection = .syncFailed
            return false
        }
    }

    private func registerObserverIfPossible() {
        guard hasAsked,
              let stepsType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        if observerQuery == nil {
            let query = HKObserverQuery(sampleType: stepsType, predicate: nil) { [weak self] _, completion, _ in
                Task { @MainActor [weak self] in
                    guard let self, let session = self.session else {
                        completion()
                        return
                    }
                    while self.isSyncing {
                        try? await Task.sleep(for: .milliseconds(250))
                    }
                    _ = await self.syncToBackend(session: session)
                    completion()
                }
            }
            observerQuery = query
            store.execute(query)
        }
        store.enableBackgroundDelivery(for: stepsType, frequency: .immediate) { [weak self] success, _ in
            Task { @MainActor [weak self] in
                self?.backgroundDeliveryUnavailable = !success
            }
        }
    }

    private static func todayTotal(
        store: HKHealthStore,
        type: HKQuantityType
    ) async throws -> Int? {
        let now = Date()
        let predicate = HKQuery.predicateForSamples(
            withStart: Calendar.current.startOfDay(for: now),
            end: now,
            options: .strictStartDate
        )
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: type, predicate: predicate),
            options: [.cumulativeSum]
        )
        guard let statistics = try await descriptor.result(for: store) else { return nil }
        let steps = statistics.sumQuantity()?.doubleValue(for: .count()) ?? 0
        guard steps > 0 else { return nil }
        return Int(steps.rounded())
    }

    private static func format(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private static func askedKey(userId: UUID) -> String {
        "ff.healthkit.stepsAsked.\(userId.uuidString.lowercased())"
    }
}

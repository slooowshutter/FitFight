import Combine
import Foundation
import StoreKit
import UIKit

struct SpecialStoreSnapshot: Decodable {
    struct Edition: Decodable, Identifiable {
        enum Status: String, Decodable { case available, reserved, yours, taken, refunded }
        let id: String
        let productId: String
        let status: Status
        enum CodingKeys: String, CodingKey { case id, status; case productId = "product_id" }
    }
    let appAccountToken: UUID
    let environment: String
    let purchasesEnabled: Bool
    let editions: [Edition]
    let conflicts: [SpecialClaimResult]
    enum CodingKeys: String, CodingKey {
        case environment, editions, conflicts
        case appAccountToken = "app_account_token", purchasesEnabled = "purchases_enabled"
    }
}

struct SpecialClaimResult: Decodable {
    enum Outcome: String, Decodable { case owned, refunded, conflict }
    let outcome: Outcome
    let transactionId: String
    let companionId: String
    enum CodingKeys: String, CodingKey {
        case outcome
        case transactionId = "transaction_id", companionId = "companion_id"
    }
}

private struct SpecialPurchaseAttempt: Codable {
    enum Phase: String, Codable { case ready, submitted, cancelled }
    let id: UUID
    let companionId: String
    var phase: Phase
}

@MainActor
final class SpecialPurchases: ObservableObject {
    @Published private(set) var snapshot: SpecialStoreSnapshot?
    @Published private(set) var products: [String: Product] = [:]
    @Published private(set) var isBusy = false
    @Published var message = ""
    @Published private var pendingAttempt: SpecialPurchaseAttempt?
    private let api = FitFightAPI()
    private var ownerId: UUID?
    private var processing: Set<UInt64> = []
    var canCancelCheckout: Bool { pendingAttempt.map { $0.phase != .submitted } ?? false }

    func observe(session: SessionStore) async {
        ownerId = session.profile?.userId
        snapshot = nil
        products = [:]
        message = ""
        pendingAttempt = nil
        guard let userId = ownerId else { return }
        do {
            if let data = UserDefaults.standard.data(forKey: "ff.special.purchase.\(userId.uuidString)") {
                pendingAttempt = try JSONDecoder().decode(SpecialPurchaseAttempt.self, from: data)
            }
        } catch { message = error.localizedDescription }
        let updates = Task {
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                do {
                    _ = try await deliver(result, session: session)
                    try await refresh(session: session)
                    await session.loadProfile()
                } catch is CancellationError {
                    if Task.isCancelled || ownerId != userId { return }
                }
                catch { message = error.localizedDescription }
            }
        }
        defer { updates.cancel() }
        do {
            try await refresh(session: session)
            try await reconcile(session: session)
        } catch is CancellationError {
            if Task.isCancelled || ownerId != userId { return }
        }
        catch { message = error.localizedDescription }
        await withTaskCancellationHandler {
            await updates.value
        } onCancel: {
            updates.cancel()
        }
    }

    func refresh(session: SessionStore) async throws {
        let userId = session.profile?.userId
        let settled = pendingAttempt.flatMap { $0.phase == .ready ? nil : $0.id }
        let loaded = try await api.specials(accessToken: session.freshAccessToken())
        try Task.checkCancellation()
        guard userId == session.profile?.userId, userId == ownerId else { throw CancellationError() }
        snapshot = loaded
        // The server lets an unpaid hold lapse; a late charge still arrives through Transaction.updates.
        if let userId, let attempt = pendingAttempt, attempt.id == settled,
           loaded.editions.first(where: { $0.id == attempt.companionId })?.status != .reserved {
            try persistAttempt(nil, userId: userId)
        }
        if products.isEmpty && loaded.purchasesEnabled {
            let fetched = try await Product.products(for: loaded.editions.map(\.productId))
            try Task.checkCancellation()
            guard userId == ownerId else { throw CancellationError() }
            products = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
        }
    }

    func canBuy(_ animal: StockCompanion) -> Bool {
        guard let snapshot, snapshot.purchasesEnabled,
              let edition = snapshot.editions.first(where: { $0.id == animal.rawValue }),
              products[edition.productId] != nil else { return false }
        if let attempt = pendingAttempt,
           attempt.phase != .ready || attempt.companionId != animal.rawValue { return false }
        return (edition.status == .available || (edition.status == .reserved && pendingAttempt?.phase == .ready))
            && !snapshot.editions.contains(where: {
                $0.status == .yours || $0.status == .refunded || ($0.status == .reserved && $0.id != animal.rawValue)
            })
    }

    private func persistAttempt(_ attempt: SpecialPurchaseAttempt?, userId: UUID) throws {
        let key = "ff.special.purchase.\(userId.uuidString)"
        if let attempt {
            UserDefaults.standard.set(try JSONEncoder().encode(attempt), forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
        if ownerId == userId { pendingAttempt = attempt }
    }

    func buy(_ animal: StockCompanion, session: SessionStore) async -> Bool {
        guard !isBusy, canBuy(animal), let userId = ownerId, userId == session.profile?.userId,
              let snapshot, let product = products[animal.productId] else { return false }
        isBusy = true
        message = ""
        defer { isBusy = false }
        var attempt = pendingAttempt ?? SpecialPurchaseAttempt(id: UUID(), companionId: animal.rawValue, phase: .ready)
        do {
            try persistAttempt(attempt, userId: userId)
            try await api.specialCheckout(action: "reserve", companionId: animal.rawValue, attemptId: attempt.id,
                                          accessToken: session.freshAccessToken())
            try Task.checkCancellation()
            guard ownerId == userId, session.profile?.userId == userId else { throw CancellationError() }
            // Persist before presenting Apple: a crash must never free a potentially paid hold.
            attempt.phase = .submitted
            try persistAttempt(attempt, userId: userId)
            var result = Product.PurchaseResult.userCancelled
            var purchaseError: Error?
            do {
                result = try await product.purchase(options: [.appAccountToken(snapshot.appAccountToken)])
            } catch StoreKitError.userCancelled {
                // The person dismissed Apple's sign-in; nothing was charged.
            } catch let error as Product.PurchaseError {
                // Apple refused before charging (for example Screen Time), so release the hold like a cancel.
                // Other errors keep the hold until it lapses, in case Apple charges later.
                purchaseError = error
            }
            switch result {
            case .success(let verification):
                let claim = try await deliver(verification, session: session)
                try await refresh(session: session)
                return claim?.outcome == .owned || self.snapshot?.editions.first(where: { $0.id == animal.rawValue })?.status == .yours
            case .userCancelled:
                attempt.phase = .cancelled
                try persistAttempt(attempt, userId: userId)
                guard session.profile?.userId == userId else { throw CancellationError() }
                try await api.specialCheckout(action: "cancel", companionId: animal.rawValue, attemptId: attempt.id,
                                              accessToken: session.freshAccessToken())
                try persistAttempt(nil, userId: userId)
                try await refresh(session: session)
                if let purchaseError { throw purchaseError }
            case .pending:
                message = String(appLocalized: "Apple is processing your purchase. Your Special is held for 30 minutes.")
                try await refresh(session: session)
            @unknown default:
                message = String(appLocalized: "Purchase status is unknown. Restore purchases before trying again.")
            }
        } catch is CancellationError { return false }
        catch { message = error.localizedDescription }
        return false
    }

    func restore(session: SessionStore) async {
        guard !isBusy else { return }
        isBusy = true
        message = ""
        defer { isBusy = false }
        do {
            try await AppStore.sync()
            try await refresh(session: session)
            try await reconcile(session: session)
            if message.isEmpty {
                message = snapshot?.editions.contains(where: { $0.status == .yours }) == true
                    ? String(appLocalized: "Purchases checked. Your owned Special is ready to use.")
                    : String(appLocalized: "Purchases checked. No completed purchase was found for this account.")
            }
        } catch is CancellationError { return }
        catch { message = error.localizedDescription }
    }

    func cancelCheckout(session: SessionStore) async {
        guard !isBusy, let attempt = pendingAttempt, attempt.phase != .submitted,
              let userId = ownerId, userId == session.profile?.userId else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await api.specialCheckout(action: "cancel", companionId: attempt.companionId, attemptId: attempt.id,
                                          accessToken: session.freshAccessToken())
            try persistAttempt(nil, userId: userId)
            try await refresh(session: session)
        } catch is CancellationError { return }
        catch { message = error.localizedDescription }
    }

    private func reconcile(session: SessionStore) async throws {
        guard let userId = ownerId else { return }
        if let attempt = pendingAttempt {
            if attempt.phase == .cancelled {
                try await api.specialCheckout(action: "cancel", companionId: attempt.companionId, attemptId: attempt.id,
                                              accessToken: session.freshAccessToken())
                try persistAttempt(nil, userId: userId)
            }
        }
        // Includes revoked purchases, so missed refund notifications reconcile on launch.
        var seen: Set<UInt64> = []
        for await result in Transaction.all {
            try Task.checkCancellation()
            guard case .verified(let transaction) = result,
                  transaction.productID.hasPrefix("com.fitfight.mvp.special."),
                  seen.insert(transaction.originalID).inserted else { continue }
            _ = try await deliver(result, session: session)
        }
        try await refresh(session: session)
        await session.loadProfile()
    }

    private func deliver(_ result: VerificationResult<Transaction>, session: SessionStore) async throws -> SpecialClaimResult? {
        guard case .verified(let transaction) = result else {
            throw NSError(domain: "SpecialPurchase", code: 1, userInfo: [NSLocalizedDescriptionKey: String(appLocalized: "Apple could not verify this purchase.")])
        }
        guard let animal = StockCompanion.allCases.first(where: { $0.isLimited && $0.productId == transaction.productID }) else { return nil }
        guard let userId = ownerId, session.profile?.userId == userId else { throw CancellationError() }
        if snapshot == nil { try await refresh(session: session) }
        guard let snapshot, ownerId == userId else { throw CancellationError() }
        guard transaction.appAccountToken == snapshot.appAccountToken else {
            message = String(appLocalized: "This purchase belongs to another FitFight account. Sign in to that account or contact support.")
            return nil
        }
        guard processing.insert(transaction.id).inserted else { return nil }
        defer { processing.remove(transaction.id) }
        let claim = try await api.claimSpecial(companionId: animal.rawValue, signedTransaction: result.jwsRepresentation,
                                               accessToken: session.freshAccessToken())
        try Task.checkCancellation()
        guard ownerId == userId, session.profile?.userId == userId else { throw CancellationError() }
        if claim.outcome != .conflict {
            await transaction.finish()
            if pendingAttempt?.companionId == animal.rawValue {
                try persistAttempt(nil, userId: userId)
            }
        } else {
            message = String(appLocalized: "This purchase could not be assigned. Request a refund from Apple below.")
        }
        return claim
    }

    func requestRefund(_ claim: SpecialClaimResult) async {
        guard let transactionId = UInt64(claim.transactionId),
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }) else { return }
        do {
            let status = try await Transaction.beginRefundRequest(for: transactionId, in: scene)
            if status == .success { message = String(appLocalized: "Refund requested. Apple will decide and notify you.") }
        } catch { message = error.localizedDescription }
    }
}

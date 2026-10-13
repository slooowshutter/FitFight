import Combine
import Foundation
import PostHog
import StoreKit
import UIKit

struct SpecialStoreSnapshot: Decodable {
    struct Edition: Decodable, Identifiable {
        /// The server now sends only available and yours; servers before 12 Oct 2026 also sent the other three.
        enum Status: String, Decodable { case available, reserved, yours, taken, refunded }
        let id: String
        let status: Status
    }
    let appAccountToken: UUID
    let environment: String
    let purchasesEnabled: Bool
    /// The one consumable every Special is bought with. Missing from a server that still sold one-of-a-kind editions.
    let productId: String?
    let editions: [Edition]
    let conflicts: [SpecialClaimResult]
    enum CodingKeys: String, CodingKey {
        case environment, editions, conflicts
        case appAccountToken = "app_account_token", purchasesEnabled = "purchases_enabled", productId = "product_id"
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

@MainActor
final class SpecialPurchases: ObservableObject {
    /// Every Special is this one consumable; the server records which Special each charge unlocked.
    static let productID = "com.fitfight.mvp.special"

    @Published private(set) var snapshot: SpecialStoreSnapshot?
    @Published private(set) var product: Product?
    @Published private(set) var isBusy = false
    /// Apple is still processing a charge, for example Ask to Buy, so a second purchase waits for it.
    @Published private(set) var pendingPurchase = false
    /// A paid charge whose chosen Special was lost on this phone; the next Special picked unlocks without paying again.
    @Published private(set) var hasUnclaimedCharge = false
    @Published var message = ""
    private let api = FitFightAPI()
    private var ownerId: UUID?
    private var processing: Set<UInt64> = []

    private func draftKey(_ userId: UUID) -> String { "ff.special.draft.\(userId.uuidString)" }
    private func pendingSinceKey(_ userId: UUID) -> String { "ff.special.pending.since.\(userId.uuidString)" }

    func observe(session: SessionStore) async {
        ownerId = session.profile?.userId
        snapshot = nil
        product = nil
        message = ""
        pendingPurchase = false
        hasUnclaimedCharge = false
        guard let userId = ownerId else { return }
        pendingPurchase = UserDefaults.standard.object(forKey: pendingSinceKey(userId)) != nil
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
        let loaded = try await api.specials(accessToken: session.freshAccessToken())
        try Task.checkCancellation()
        guard userId == session.profile?.userId, userId == ownerId else { throw CancellationError() }
        snapshot = loaded
        if product == nil && loaded.purchasesEnabled, let productId = loaded.productId {
            let fetched = try await Product.products(for: [productId])
            try Task.checkCancellation()
            guard userId == ownerId else { throw CancellationError() }
            product = fetched.first { $0.id == productId && $0.type == .consumable }
        }
    }

    func canBuy(_ animal: StockCompanion) -> Bool {
        guard let snapshot, snapshot.purchasesEnabled, product != nil, !pendingPurchase,
              let edition = snapshot.editions.first(where: { $0.id == animal.rawValue }) else { return false }
        return edition.status != .yours
    }

    private func setPending(_ pending: Bool, userId: UUID) {
        if pending {
            UserDefaults.standard.set(Date(), forKey: pendingSinceKey(userId))
        } else {
            UserDefaults.standard.removeObject(forKey: pendingSinceKey(userId))
        }
        if ownerId == userId { pendingPurchase = pending }
    }

    private func abandon(userId: UUID) {
        UserDefaults.standard.removeObject(forKey: draftKey(userId))
        setPending(false, userId: userId)
    }

    func buy(_ animal: StockCompanion, session: SessionStore) async -> Bool {
        guard !isBusy, canBuy(animal), let userId = ownerId, userId == session.profile?.userId,
              let snapshot, let product else { return false }
        isBusy = true
        message = ""
        defer { isBusy = false }
        do {
            // An earlier charge still waiting for the server claims its own Special first; one that lost its
            // Special unlocks this one instead of charging again.
            if UserDefaults.standard.string(forKey: draftKey(userId)) == nil {
                UserDefaults.standard.set(animal.rawValue, forKey: draftKey(userId))
            }
            for await result in Transaction.unfinished {
                try Task.checkCancellation()
                guard case .verified(let transaction) = result, transaction.productID == Self.productID else { continue }
                if let claim = try await deliver(result, session: session), claim.companionId == animal.rawValue {
                    try await refresh(session: session)
                    return claim.outcome == .owned
                }
            }
            // Saved before Apple's sheet, so a charge interrupted by a crash still unlocks this Special later.
            UserDefaults.standard.set(animal.rawValue, forKey: draftKey(userId))
            setPending(true, userId: userId)
            let result = try await product.purchase(options: [.appAccountToken(snapshot.appAccountToken)])
            switch result {
            case .success(let verification):
                let claim = try await deliver(verification, session: session)
                PostHogSDK.shared.capture("purchase_completed", properties: ["product": "special"])
                try await refresh(session: session)
                return claim?.outcome == .owned && claim?.companionId == animal.rawValue
            case .userCancelled:
                abandon(userId: userId)
            case .pending:
                message = String(appLocalized: "Apple is processing your purchase. Your Special unlocks when it completes.")
            @unknown default:
                message = String(appLocalized: "Purchase status is unknown. Restore purchases before trying again.")
            }
        } catch StoreKitError.userCancelled {
            // The person dismissed Apple's sign-in; nothing was charged.
            abandon(userId: userId)
        } catch let error as Product.PurchaseError {
            // Apple refused before charging, for example Screen Time.
            abandon(userId: userId)
            message = error.localizedDescription
        } catch is CancellationError { return false }
        catch { message = error.localizedDescription }
        return false
    }

    /// Consumables never come back from Apple, so the server ledger is the record; this finishes unclaimed charges.
    func restore(session: SessionStore) async {
        guard !isBusy else { return }
        isBusy = true
        message = ""
        defer { isBusy = false }
        do {
            var appleSyncFailed = false
            do { try await AppStore.sync() }
            catch is CancellationError { return }
            catch { appleSyncFailed = true }
            try await reconcile(session: session)
            // A pending Ask to Buy has no transaction yet, so an empty reconcile proves nothing until
            // Apple's 24 hour approval window has passed. After that, Restore is the way out.
            if !appleSyncFailed, processing.isEmpty, let userId = ownerId,
               Date().timeIntervalSince(UserDefaults.standard.object(forKey: pendingSinceKey(userId)) as? Date ?? .distantPast) > 86_400 {
                setPending(false, userId: userId)
            }
            if message.isEmpty {
                message = appleSyncFailed
                    ? String(appLocalized: "Apple sync could not complete, but FitFight checked your account purchases.")
                    : pendingPurchase
                        ? String(appLocalized: "Apple is still processing your Special purchase.")
                        : snapshot?.editions.contains(where: { $0.status == .yours }) == true
                            ? String(appLocalized: "Purchases checked. Your Specials are ready to use.")
                            : String(appLocalized: "Purchases checked. No completed purchase was found for this account.")
            }
        } catch is CancellationError { return }
        catch { message = error.localizedDescription }
    }

    private func reconcile(session: SessionStore) async throws {
        for await result in Transaction.unfinished {
            try Task.checkCancellation()
            guard case .verified(let transaction) = result,
                  transaction.productID.hasPrefix(Self.productID) else { continue }
            _ = try await deliver(result, session: session)
        }
        try await refresh(session: session)
        await session.loadProfile()
    }

    private func deliver(_ result: VerificationResult<Transaction>, session: SessionStore) async throws -> SpecialClaimResult? {
        guard case .verified(let transaction) = result else {
            throw NSError(domain: "SpecialPurchase", code: 1, userInfo: [NSLocalizedDescriptionKey: String(appLocalized: "Apple could not verify this purchase.")])
        }
        // Builds before 12 Oct 2026 sold one product per Special; their refunds and late charges still record.
        let legacy = transaction.productID.hasPrefix(Self.productID + ".")
        guard legacy || transaction.productID == Self.productID else { return nil }
        guard let userId = ownerId, session.profile?.userId == userId else { throw CancellationError() }
        if snapshot == nil { try await refresh(session: session) }
        guard let snapshot, ownerId == userId else { throw CancellationError() }
        guard transaction.appAccountToken == snapshot.appAccountToken else {
            message = String(appLocalized: "This purchase belongs to another FitFight account. Sign in to that account or contact support.")
            return nil
        }
        let companionId = legacy
            ? "limited-" + transaction.productID.dropFirst(Self.productID.count + 1).replacingOccurrences(of: "_", with: "-")
            : UserDefaults.standard.string(forKey: draftKey(userId))
        guard let companionId else {
            // Left unfinished: Apple keeps offering it until a chosen Special claims it.
            hasUnclaimedCharge = true
            message = String(appLocalized: "You paid for a Special that is not unlocked yet. Pick one and tap Unlock.")
            return nil
        }
        guard processing.insert(transaction.id).inserted else { return nil }
        defer { processing.remove(transaction.id) }
        let claim = legacy
            ? try await api.claimSpecial(companionId: companionId, signedTransaction: result.jwsRepresentation,
                                         accessToken: session.freshAccessToken())
            : try await api.claimSpecialPurchase(companionId: companionId, signedTransaction: result.jwsRepresentation,
                                                 accessToken: session.freshAccessToken())
        try Task.checkCancellation()
        guard ownerId == userId, session.profile?.userId == userId else { throw CancellationError() }
        if claim.outcome == .conflict {
            message = String(appLocalized: "This purchase could not be assigned. Request a refund from Apple below.")
            return claim
        }
        await transaction.finish()
        if !legacy {
            if UserDefaults.standard.string(forKey: draftKey(userId)) == claim.companionId {
                UserDefaults.standard.removeObject(forKey: draftKey(userId))
            }
            hasUnclaimedCharge = false
            setPending(false, userId: userId)
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

import Combine
import Foundation
import StoreKit

struct CustomCharacterStoreSnapshot: Decodable {
    let appAccountToken: UUID
    let environment: String
    let purchasesEnabled: Bool
    let productId: String
    let characters: [CustomCharacterProgress]

    enum CodingKeys: String, CodingKey {
        case environment, characters
        case appAccountToken = "app_account_token"
        case purchasesEnabled = "purchases_enabled"
        case productId = "product_id"
    }
}

struct CustomCharacterProgress: Decodable, Identifiable {
    enum Status: String, Decodable { case ready, generating, retryable, needsSupport = "needs_support", complete, refunded }
    enum Stage: String, Decodable { case portrait, fitness }

    let id: UUID
    let description: String?
    let stage: Stage?
    let status: Status
    let requestID: UUID?
    let pollAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case id, description, stage, status
        case requestID = "request_id"
        case pollAfterSeconds = "poll_after_seconds"
    }
}

struct CustomCharacterClaim: Decodable {
    let purchaseID: UUID
    let refunded: Bool

    enum CodingKeys: String, CodingKey {
        case purchaseID = "purchase_id", refunded
    }
}

struct CustomCharacterAdvanceBody: Encodable {
    let description: String?
    let retry: Bool?
}

@MainActor
final class CustomCharacterPurchases: ObservableObject {
    @Published private(set) var snapshot: CustomCharacterStoreSnapshot?
    @Published private(set) var product: Product?
    @Published private(set) var isBusy = false
    @Published private(set) var pendingPurchase = false
    @Published var message = ""

    private let api = FitFightAPI()
    private var ownerID: UUID?
    private var processing: Set<UInt64> = []

    private func draftKey(_ userID: UUID) -> String { "ff.character.draft.\(userID.uuidString)" }
    private func pendingKey(_ userID: UUID) -> String { "ff.character.pending.\(userID.uuidString)" }

    func observe(session: SessionStore) async {
        ownerID = session.profile?.userId
        snapshot = nil
        product = nil
        message = ""
        pendingPurchase = false
        guard let userID = ownerID else { return }
        pendingPurchase = UserDefaults.standard.bool(forKey: pendingKey(userID))
        let updates = Task {
            for await result in Transaction.updates {
                guard !Task.isCancelled else { return }
                do { _ = try await deliver(result, session: session) }
                catch is CancellationError {
                    if Task.isCancelled || ownerID != userID { return }
                } catch { message = error.localizedDescription }
            }
        }
        defer { updates.cancel() }
        do {
            try await refresh(session: session)
            try await reconcile(session: session)
        } catch is CancellationError {
            if Task.isCancelled || ownerID != userID { return }
        } catch { message = error.localizedDescription }
        await withTaskCancellationHandler {
            await updates.value
        } onCancel: {
            updates.cancel()
        }
    }

    func refresh(session: SessionStore) async throws {
        let userID = session.profile?.userId
        let loaded = try await api.customCharacters(accessToken: try await session.freshAccessToken())
        try Task.checkCancellation()
        guard userID == ownerID, session.profile?.userId == userID else { throw CancellationError() }
        snapshot = loaded
        if loaded.purchasesEnabled && product == nil {
            do {
                let products = try await Product.products(for: [loaded.productId])
                try Task.checkCancellation()
                guard userID == ownerID, session.profile?.userId == userID else { throw CancellationError() }
                product = products.first(where: { $0.id == loaded.productId && $0.type == .consumable })
            } catch is CancellationError { throw CancellationError() }
            catch { message = error.localizedDescription }
        } else if !loaded.purchasesEnabled {
            product = nil
        }
    }

    func buy(description: String, session: SessionStore) async {
        let prompt = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isBusy, !pendingPurchase, processing.isEmpty, !prompt.isEmpty, prompt.count <= 1000,
              let userID = ownerID, userID == session.profile?.userId,
              let snapshot, snapshot.purchasesEnabled, let product else { return }
        isBusy = true
        message = ""
        defer { isBusy = false }
        UserDefaults.standard.set(prompt, forKey: draftKey(userID))
        UserDefaults.standard.set(true, forKey: pendingKey(userID))
        pendingPurchase = true
        do {
            let result = try await product.purchase(options: [.appAccountToken(snapshot.appAccountToken)])
            switch result {
            case .success(let verified):
                _ = try await deliver(verified, session: session)
            case .userCancelled:
                UserDefaults.standard.removeObject(forKey: draftKey(userID))
                UserDefaults.standard.removeObject(forKey: pendingKey(userID))
                pendingPurchase = false
            case .pending:
                message = String(appLocalized: "Apple is processing your character purchase. We will resume when it completes.")
            @unknown default:
                message = String(appLocalized: "Purchase status is unknown. Check purchases before buying again.")
            }
        } catch StoreKitError.userCancelled {
            UserDefaults.standard.removeObject(forKey: draftKey(userID))
            UserDefaults.standard.removeObject(forKey: pendingKey(userID))
            pendingPurchase = false
        } catch is Product.PurchaseError {
            UserDefaults.standard.removeObject(forKey: draftKey(userID))
            UserDefaults.standard.removeObject(forKey: pendingKey(userID))
            pendingPurchase = false
        } catch is CancellationError {
            return
        } catch { message = error.localizedDescription }
    }

    func advance(_ id: UUID, description: String? = nil, retry: Bool = false, session: SessionStore) async throws -> CustomCharacterProgress {
        guard let userID = ownerID, userID == session.profile?.userId else { throw CancellationError() }
        let result = try await api.advanceCustomCharacter(
            id: id, description: description, retry: retry,
            accessToken: try await session.freshAccessToken()
        )
        try Task.checkCancellation()
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        if result.status != .ready {
            UserDefaults.standard.removeObject(forKey: draftKey(userID))
        }
        try await refresh(session: session)
        return result
    }

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
            try await refresh(session: session)
            if message.isEmpty {
                message = appleSyncFailed
                    ? String(appLocalized: "Apple sync could not complete, but FitFight checked your account purchases.")
                    : pendingPurchase
                        ? String(appLocalized: "Apple is still processing your character purchase.")
                        : snapshot?.characters.isEmpty == false
                            ? String(appLocalized: "Your character purchases are linked to this FitFight account.")
                            : String(appLocalized: "No character purchases were found for this FitFight account.")
            }
        } catch is CancellationError { return }
        catch { message = error.localizedDescription }
    }

    private func reconcile(session: SessionStore) async throws {
        for await result in Transaction.unfinished {
            try Task.checkCancellation()
            guard case .verified(let transaction) = result,
                  transaction.productID == "com.fitfight.mvp.custom_character" else { continue }
            _ = try await deliver(result, session: session)
        }
        try await refresh(session: session)
    }

    private func deliver(_ result: VerificationResult<Transaction>, session: SessionStore) async throws -> CustomCharacterClaim? {
        guard case .verified(let transaction) = result else {
            throw NSError(domain: "CustomCharacterPurchase", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: String(appLocalized: "Apple could not verify this purchase.")])
        }
        guard transaction.productID == "com.fitfight.mvp.custom_character" else { return nil }
        guard let userID = ownerID, session.profile?.userId == userID else { throw CancellationError() }
        if snapshot == nil { try await refresh(session: session) }
        guard let snapshot, ownerID == userID else { throw CancellationError() }
        guard transaction.appAccountToken == snapshot.appAccountToken else {
            message = String(appLocalized: "This purchase belongs to another FitFight account. Sign in to that account or contact support.")
            return nil
        }
        guard processing.insert(transaction.id).inserted else { return nil }
        defer { processing.remove(transaction.id) }
        let claim = try await api.claimCustomCharacter(
            signedTransaction: result.jwsRepresentation,
            accessToken: try await session.freshAccessToken()
        )
        try Task.checkCancellation()
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        await transaction.finish()
        UserDefaults.standard.removeObject(forKey: pendingKey(userID))
        pendingPurchase = false
        try await refresh(session: session)
        if !claim.refunded, let prompt = UserDefaults.standard.string(forKey: draftKey(userID)) {
            do { _ = try await advance(claim.purchaseID, description: prompt, session: session) }
            catch { message = error.localizedDescription }
        }
        return claim
    }
}

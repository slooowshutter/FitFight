import Combine
import Foundation
import PostHog
import StoreKit

struct CustomCharacterStoreSnapshot: Decodable {
    let appAccountToken: UUID
    let environment: String
    let purchasesEnabled: Bool
    let productId: String
    /// Characters this person can still create without paying. A server without the field means none.
    let freeCharacters: Int
    /// Referred, and the referral character waits for this account's first Apple Health steps. Missing means no.
    let referralPending: Bool
    let characters: [CustomCharacterProgress]

    enum CodingKeys: String, CodingKey {
        case environment, characters
        case appAccountToken = "app_account_token"
        case purchasesEnabled = "purchases_enabled"
        case productId = "product_id"
        case freeCharacters = "free_characters"
        case referralPending = "referral_pending"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appAccountToken = try container.decode(UUID.self, forKey: .appAccountToken)
        environment = try container.decode(String.self, forKey: .environment)
        purchasesEnabled = try container.decode(Bool.self, forKey: .purchasesEnabled)
        productId = try container.decode(String.self, forKey: .productId)
        freeCharacters = try container.decodeIfPresent(Int.self, forKey: .freeCharacters) ?? 0
        referralPending = try container.decodeIfPresent(Bool.self, forKey: .referralPending) ?? false
        characters = try container.decode([CustomCharacterProgress].self, forKey: .characters)
    }
}

struct CustomCharacterProgress: Decodable, Identifiable {
    enum Status: String, Decodable { case ready, generating, retryable, needsSupport = "needs_support", complete, refunded }
    enum Stage: String, Decodable { case portrait, fitness }
    /// The detailed step. `status` keeps the values older builds decode.
    enum Phase: String, Decodable {
        case ready, portraits, choosing, poses, complete, retryable, refunded
        case needsSupport = "needs_support"
    }

    struct Candidate: Decodable, Identifiable {
        enum Status: String, Decodable { case pending, completed, failed, needsSupport = "needs_support" }
        let id: UUID
        let slot: Int
        let status: Status
        let imageURL: URL?
        let selected: Bool

        enum CodingKeys: String, CodingKey {
            case id, slot, status, selected
            case imageURL = "image_url"
        }
    }

    /// A name and a line written for this character.
    struct Suggestion: Decodable, Equatable {
        let name: String
        let line: String
    }

    let id: UUID
    let description: String?
    let stage: Stage?
    let status: Status
    let requestID: UUID?
    let pollAfterSeconds: Int?
    let phase: Phase
    /// The chosen portrait, or nil until one is chosen.
    let portraitURL: URL?
    /// The three portrait choices. Characters bought before the choice existed have none.
    let candidates: [Candidate]
    /// Every finished batch of four, first batch first. Nil from a server that cannot name companions.
    let suggestions: [Suggestion]?
    /// A batch is being written.
    let suggestionsPending: Bool
    /// "Four more" batches this character can still ask for.
    let moreSuggestionsLeft: Int
    /// The saved name and line, nil until the owner saves them.
    let name: String?
    let line: String?

    /// Finished portraits the owner can pick from.
    var candidateURLs: [URL] { candidates.compactMap { $0.status == .completed ? $0.imageURL : nil } }

    enum CodingKeys: String, CodingKey {
        case id, description, stage, status, phase, candidates, suggestions, name, line
        case requestID = "request_id"
        case pollAfterSeconds = "poll_after_seconds"
        case portraitURL = "portrait_url"
        case suggestionsPending = "suggestions_pending"
        case moreSuggestionsLeft = "more_suggestions_left"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        stage = try container.decodeIfPresent(Stage.self, forKey: .stage)
        status = try container.decode(Status.self, forKey: .status)
        requestID = try container.decodeIfPresent(UUID.self, forKey: .requestID)
        pollAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .pollAfterSeconds)
        portraitURL = try container.decodeIfPresent(URL.self, forKey: .portraitURL)
        candidates = try container.decodeIfPresent([Candidate].self, forKey: .candidates) ?? []
        suggestions = try container.decodeIfPresent([Suggestion].self, forKey: .suggestions)
        suggestionsPending = try container.decodeIfPresent(Bool.self, forKey: .suggestionsPending) ?? false
        moreSuggestionsLeft = try container.decodeIfPresent(Int.self, forKey: .moreSuggestionsLeft) ?? 0
        name = try container.decodeIfPresent(String.self, forKey: .name)
        line = try container.decodeIfPresent(String.self, forKey: .line)
        // A server without the phase field still describes every legacy step through status and stage.
        if let phase = try? container.decodeIfPresent(Phase.self, forKey: .phase) {
            self.phase = phase
        } else {
            switch status {
            case .ready: phase = .ready
            case .generating: phase = stage == .fitness ? .poses : .portraits
            case .retryable: phase = .retryable
            case .needsSupport: phase = .needsSupport
            case .complete: phase = .complete
            case .refunded: phase = .refunded
            }
        }
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
    let choosePortrait: Bool?

    enum CodingKeys: String, CodingKey {
        case description, retry
        case choosePortrait = "choose_portrait"
    }
}

/// The AI's review of a description: an optional question or warning, and three rewrites to pick from.
struct CharacterPromptCheck: Decodable {
    let note: String?
    let variations: [String]
}

/// A Blend prompt check on `ai/runs`. It takes about a minute: poll while `pending` or `running`.
struct CharacterPromptCheckRun: Decodable {
    let requestID: UUID
    let status: String
    let pollAfterSeconds: Int?
    let check: CharacterPromptCheck?

    enum CodingKeys: String, CodingKey {
        case status
        case requestID = "request_id"
        case pollAfterSeconds = "poll_after_seconds"
        case check = "data"
    }
}

@MainActor
final class CustomCharacterPurchases: ObservableObject {
    @Published private(set) var snapshot: CustomCharacterStoreSnapshot?
    @Published private(set) var product: Product?
    @Published private(set) var isBusy = false
    @Published private(set) var pendingPurchase = false
    @Published var message = ""

    /// Completed characters this person has already opened; the rest show as Ready.
    @Published private var seenReady: Set<UUID> = []

    private let api = FitFightAPI()
    private var ownerID: UUID?
    private var processing: Set<UInt64> = []
    /// Kept until the server answers, so tapping again after a lost answer cannot use a second free character.
    private var freeClaimKey: UUID?

    /// Characters or Specials this person can still get without paying.
    var freeCharacters: Int { snapshot?.freeCharacters ?? 0 }
    /// Referred, and the referral character waits for this account's first Apple Health steps.
    var referralPending: Bool { snapshot?.referralPending ?? false }

    /// Characters the server is still drawing, waiting for a portrait choice, or stuck on a failure.
    var inProgress: [CustomCharacterProgress] {
        snapshot?.characters.filter { [.portraits, .choosing, .poses, .retryable, .needsSupport].contains($0.phase) } ?? []
    }

    /// Finished characters this person has not opened yet.
    var unseenReady: [CustomCharacterProgress] {
        snapshot?.characters.filter { $0.phase == .complete && !seenReady.contains($0.id) } ?? []
    }

    private func draftKey(_ userID: UUID) -> String { "ff.character.draft.\(userID.uuidString)" }
    private func seenKey(_ userID: UUID) -> String { "ff.character.seen.\(userID.uuidString)" }

    func markReadySeen() {
        guard let userID = ownerID else { return }
        seenReady.formUnion(snapshot?.characters.filter { $0.phase == .complete }.map(\.id) ?? [])
        UserDefaults.standard.set(seenReady.map(\.uuidString), forKey: seenKey(userID))
    }
    private func pendingKey(_ userID: UUID) -> String { "ff.character.pending.\(userID.uuidString)" }
    private func pendingSinceKey(_ userID: UUID) -> String { "ff.character.pending.since.\(userID.uuidString)" }

    #if DEBUG && targetEnvironment(simulator)
    /// Simulator preview only: shows one fixed state without a backend.
    func showPreview(_ snapshot: CustomCharacterStoreSnapshot) {
        self.snapshot = snapshot
    }
    #endif

    func observe(session: SessionStore) async {
        ownerID = session.profile?.userId
        snapshot = nil
        freeClaimKey = nil
        product = nil
        message = ""
        pendingPurchase = false
        seenReady = []
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
        if let userID {
            if let stored = UserDefaults.standard.stringArray(forKey: seenKey(userID)) {
                seenReady = Set(stored.compactMap(UUID.init(uuidString:)))
            } else {
                // Characters finished before this screen existed were already seen.
                markReadySeen()
            }
        }
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
        UserDefaults.standard.set(Date(), forKey: pendingSinceKey(userID))
        pendingPurchase = true
        do {
            let result = try await product.purchase(options: [.appAccountToken(snapshot.appAccountToken)])
            switch result {
            case .success(let verified):
                _ = try await deliver(verified, session: session)
                PostHogSDK.shared.capture("purchase_completed", properties: ["product": "custom_character"])
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

    /// Uses one free character. The portraits start in the background, so the caller can move on at once.
    func claimFree(description: String, session: SessionStore) async throws {
        let prompt = description.trimmingCharacters(in: .whitespacesAndNewlines)
        // Callers move on only after a claim, so every early exit throws.
        guard !isBusy, !prompt.isEmpty, prompt.count <= 1000,
              let userID = ownerID, userID == session.profile?.userId else { throw CancellationError() }
        isBusy = true
        defer { isBusy = false }
        let key = freeClaimKey ?? UUID()
        freeClaimKey = key
        let claim = try await api.claimFreeCustomCharacter(
            description: prompt, idempotencyKey: key, accessToken: try await session.freshAccessToken()
        )
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        freeClaimKey = nil
        PostHogSDK.shared.capture("free_character_claimed")
        // The character exists now; a failed reload must not make the caller think it does not.
        try? await refresh(session: session)
        // Starts the portraits now; if this fails, the server starts them within a few minutes.
        Task { _ = try? await advance(claim.purchaseID, session: session) }
    }

    func advance(_ id: UUID, description: String? = nil, retry: Bool = false, session: SessionStore) async throws -> CustomCharacterProgress {
        guard let userID = ownerID, userID == session.profile?.userId else { throw CancellationError() }
        let phase = snapshot?.characters.first { $0.id == id }?.phase
        let result = try await api.advanceCustomCharacter(
            id: id, description: description, retry: retry,
            accessToken: try await session.freshAccessToken()
        )
        try Task.checkCancellation()
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        // Polling a chosen portrait for poses or name ideas must not drop the description of a purchase still with Apple.
        if result.status != .ready, phase != .poses, phase != .complete {
            UserDefaults.standard.removeObject(forKey: draftKey(userID))
        }
        try await refresh(session: session)
        return result
    }

    func choose(_ id: UUID, candidate: UUID, session: SessionStore) async throws -> CustomCharacterProgress {
        guard let userID = ownerID, userID == session.profile?.userId else { throw CancellationError() }
        let result = try await api.chooseCustomCharacterPortrait(
            id: id, candidateID: candidate, accessToken: try await session.freshAccessToken()
        )
        try Task.checkCancellation()
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        try await refresh(session: session)
        return result
    }

    /// `source` is `suggestion`, `edited` or `own`. Analytics never gets the text: it is user content.
    func saveLabel(_ id: UUID, name: String, line: String, source: String, session: SessionStore) async throws {
        guard let userID = ownerID, userID == session.profile?.userId else { throw CancellationError() }
        let saved = try await api.labelCustomCharacter(
            id: id, name: name, line: line, accessToken: try await session.freshAccessToken()
        )
        try Task.checkCancellation()
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        // Every batch holds four.
        PostHogSDK.shared.capture("companion_label_saved",
                                  properties: ["source": source, "batches": (saved.suggestions?.count ?? 0) / 4])
        try await refresh(session: session)
        // The companion card on Fights and Profile reads the pair from the profile.
        await session.loadProfile()
    }

    /// Starts "Four more". The server answers a repeated attempt id with the batch it already started.
    func suggestLabels(_ id: UUID, attemptID: UUID, session: SessionStore) async throws {
        guard let userID = ownerID, userID == session.profile?.userId else { throw CancellationError() }
        _ = try await api.suggestCustomCharacterLabels(
            id: id, attemptID: attemptID, accessToken: try await session.freshAccessToken()
        )
        try Task.checkCancellation()
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        try await refresh(session: session)
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
            // A pending Ask to Buy has no transaction yet, so an empty reconcile proves nothing until
            // Apple's 24 hour approval window has passed. After that, Restore is the way out.
            if !appleSyncFailed, processing.isEmpty, let userID = ownerID,
               Date().timeIntervalSince(UserDefaults.standard.object(forKey: pendingSinceKey(userID)) as? Date ?? .distantPast) > 86_400 {
                UserDefaults.standard.removeObject(forKey: pendingKey(userID))
                pendingPurchase = false
            }
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
        // The server saves the description with the purchase, so drawing continues even if the app closes now.
        let prompt = UserDefaults.standard.string(forKey: draftKey(userID))
        let claim = try await api.claimCustomCharacter(
            signedTransaction: result.jwsRepresentation,
            description: prompt,
            accessToken: try await session.freshAccessToken()
        )
        try Task.checkCancellation()
        guard ownerID == userID, session.profile?.userId == userID else { throw CancellationError() }
        await transaction.finish()
        UserDefaults.standard.removeObject(forKey: pendingKey(userID))
        pendingPurchase = false
        if !claim.refunded, prompt != nil {
            UserDefaults.standard.removeObject(forKey: draftKey(userID))
        }
        try await refresh(session: session)
        if !claim.refunded, prompt != nil {
            // Starts the portraits now; if this fails, the server starts them within a few minutes.
            _ = try? await advance(claim.purchaseID, session: session)
        }
        return claim
    }
}

// StoreKit and HTTP are the replaced boundaries; the purchase controller is compiled unchanged.
enum VerificationResult<Value> {
    case verified(Value), unverified
    var jwsRepresentation: String { "verified-receipt" }
}

@MainActor
struct Product {
    enum PurchaseResult { case success(VerificationResult<Transaction>), userCancelled, pending }
    enum PurchaseOption: Hashable { case appAccountToken(UUID) }
    enum PurchaseError: Error { case purchaseNotAllowed }
    let id: String
    static var result = PurchaseResult.pending
    static var presented = 0
    static var failure: Error?
    static func products(for ids: [String]) async throws -> [Product] { ids.map { Product(id: $0) } }
    func purchase(options: Set<PurchaseOption>) async throws -> PurchaseResult {
        Self.presented += 1
        if let failure = Self.failure { throw failure }
        return Self.result
    }
}

@MainActor
final class Transaction {
    let id: UInt64 = 123
    let originalID: UInt64 = 123
    let productID = StockCompanion.pangolin.productId
    let appAccountToken: UUID?
    var finished = false
    static var continuation: AsyncStream<VerificationResult<Transaction>>.Continuation?
    static var history: [VerificationResult<Transaction>] = []
    static var updates: AsyncStream<VerificationResult<Transaction>> {
        AsyncStream { continuation = $0 }
    }
    static var all: AsyncStream<VerificationResult<Transaction>> {
        AsyncStream { stream in
            for item in history { stream.yield(item) }
            stream.finish()
        }
    }
    init(account: UUID) { appAccountToken = account }
    func finish() async { finished = true }
}

enum AppStore { static func sync() async throws {} }
enum StoreKitError: Error { case userCancelled }
enum StockCompanion: String, CaseIterable {
    case pangolin = "limited-pangolin", platypus = "limited-platypus"
    var isLimited: Bool { true }
    var productId: String { "com.fitfight.mvp.special.\(rawValue.dropFirst(8))" }
}

@MainActor
final class SessionStore {
    struct Profile { let userId: UUID }
    var profile: Profile? = Profile(userId: UUID())
    func freshAccessToken() async throws -> String { "test-token" }
    func loadProfile() async {}
}

@MainActor
struct FitFightAPI {
    static var account = UUID()
    static var status = SpecialStoreSnapshot.Edition.Status.available
    static var loseReserveResponse = false
    static var failCancel = false
    static var failRead = false
    static var attempts: [UUID] = []
    static var delivered = 0
    static var outcome = SpecialClaimResult.Outcome.owned
    func specials(accessToken: String) async throws -> SpecialStoreSnapshot {
        if Self.failRead {
            Self.failRead = false
            throw URLError(.notConnectedToInternet)
        }
        return SpecialStoreSnapshot(appAccountToken: Self.account, environment: "Sandbox", purchasesEnabled: true,
            editions: StockCompanion.allCases.map { .init(id: $0.rawValue, productId: $0.productId, status: $0 == .pangolin ? Self.status : .available) }, conflicts: [])
    }
    func specialCheckout(action: String, companionId: String, attemptId: UUID, accessToken: String) async throws {
        if action == "reserve" {
            Self.attempts.append(attemptId)
            Self.status = .reserved
            if Self.loseReserveResponse {
                Self.loseReserveResponse = false
                throw URLError(.networkConnectionLost)
            }
        } else {
            if Self.failCancel {
                Self.failCancel = false
                throw URLError(.notConnectedToInternet)
            }
            Self.status = .available
        }
    }
    func claimSpecial(companionId: String, signedTransaction: String, accessToken: String) async throws -> SpecialClaimResult {
        Self.delivered += 1
        if Self.outcome == .owned { Self.status = .yours }
        return .init(outcome: Self.outcome, transactionId: "123", companionId: companionId)
    }
}

@main
struct SpecialPurchaseTests {
    @MainActor static func main() async throws {
        let session = SessionStore()
        let userId = session.profile!.userId
        defer { UserDefaults.standard.removeObject(forKey: "ff.special.purchase.\(userId.uuidString)") }
        let purchases = SpecialPurchases()
        let observer = Task { await purchases.observe(session: session) }
        defer { observer.cancel() }
        for _ in 0..<100 where purchases.products.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        precondition(purchases.canBuy(.pangolin))

        FitFightAPI.loseReserveResponse = true
        let firstResult = await purchases.buy(.pangolin, session: session)
        precondition(firstResult == false)
        try await purchases.refresh(session: session)
        precondition(purchases.canBuy(.pangolin), "A lost reserve response must allow the same attempt to resume")
        precondition(!purchases.canBuy(.platypus))
        Product.result = .pending
        let resumedResult = await purchases.buy(.pangolin, session: session)
        precondition(resumedResult == false)
        precondition(FitFightAPI.attempts.count == 2 && FitFightAPI.attempts[0] == FitFightAPI.attempts[1])
        precondition(!purchases.canBuy(.pangolin), "Never present a second purchase sheet for a submitted attempt")
        precondition(Product.presented == 1)
        observer.cancel()
        await observer.value

        // Recreate the controller to verify that the unresolved attempt survives restart.
        let restarted = SpecialPurchases()
        let nextObserver = Task { await restarted.observe(session: session) }
        defer { nextObserver.cancel() }
        for _ in 0..<100 where restarted.products.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        precondition(!restarted.canBuy(.pangolin))
        let foreign = Transaction(account: UUID())
        Transaction.continuation?.yield(.verified(foreign))
        try await Task.sleep(for: .milliseconds(30))
        precondition(!foreign.finished && FitFightAPI.delivered == 0)
        let transaction = Transaction(account: FitFightAPI.account)
        Transaction.continuation?.yield(.verified(transaction))
        for _ in 0..<100 where !transaction.finished { try await Task.sleep(for: .milliseconds(10)) }
        precondition(transaction.finished && FitFightAPI.delivered == 1)
        precondition(UserDefaults.standard.data(forKey: "ff.special.purchase.\(userId.uuidString)") == nil)
        precondition(!restarted.canBuy(.platypus), "Permanent ownership enforces the account limit")
        nextObserver.cancel()
        await nextObserver.value

        // Initial network failure must not permanently stop transaction observation.
        let otherSession = SessionStore()
        let recovering = SpecialPurchases()
        FitFightAPI.failRead = true
        FitFightAPI.status = .available
        FitFightAPI.outcome = .conflict
        let recoveringObserver = Task { await recovering.observe(session: otherSession) }
        defer { recoveringObserver.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        let conflict = Transaction(account: FitFightAPI.account)
        Transaction.continuation?.yield(.verified(conflict))
        for _ in 0..<100 where FitFightAPI.delivered < 2 { try await Task.sleep(for: .milliseconds(10)) }
        precondition(FitFightAPI.delivered == 2 && !conflict.finished, "Unfulfilled charges must remain recoverable")
        try await recovering.refresh(session: otherSession)
        Product.result = .userCancelled
        let cancelled = await recovering.buy(.pangolin, session: otherSession)
        precondition(!cancelled && recovering.canBuy(.platypus), "Apple cancellation must release only this checkout")
        FitFightAPI.loseReserveResponse = true
        _ = await recovering.buy(.pangolin, session: otherSession)
        precondition(recovering.canCancelCheckout)
        await recovering.cancelCheckout(session: otherSession)
        precondition(!recovering.canCancelCheckout && recovering.canBuy(.platypus))
        recoveringObserver.cancel()
        await recoveringObserver.value

        // Apple refusing before a charge releases the hold at once.
        let thirdSession = SessionStore()
        let failing = SpecialPurchases()
        FitFightAPI.status = .available
        let failingObserver = Task { await failing.observe(session: thirdSession) }
        defer { failingObserver.cancel() }
        for _ in 0..<100 where failing.products.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        Product.failure = Product.PurchaseError.purchaseNotAllowed
        let refused = await failing.buy(.pangolin, session: thirdSession)
        precondition(!refused && FitFightAPI.status == .available && failing.canBuy(.pangolin) && failing.canBuy(.platypus),
                     "A refused purchase must release the hold")

        // Dismissing Apple's sign-in is a cancel, not an error.
        Product.failure = StoreKitError.userCancelled
        _ = await failing.buy(.pangolin, session: thirdSession)
        precondition(FitFightAPI.status == .available && failing.canBuy(.platypus) && failing.message.isEmpty,
                     "A dismissed sign-in must release the hold quietly")

        // An ambiguous error keeps the hold; the checkout frees itself once the server hold lapses.
        Product.failure = URLError(.networkConnectionLost)
        _ = await failing.buy(.pangolin, session: thirdSession)
        Product.failure = nil
        precondition(FitFightAPI.status == .reserved && !failing.canBuy(.pangolin) && !failing.canBuy(.platypus),
                     "A possibly charged purchase must keep its hold")
        FitFightAPI.status = .available
        try await failing.refresh(session: thirdSession)
        precondition(failing.canBuy(.pangolin), "A lapsed server hold must not strand the checkout")

        // A cancel that could not reach the server can be retried by hand.
        Product.result = .userCancelled
        FitFightAPI.failCancel = true
        _ = await failing.buy(.pangolin, session: thirdSession)
        precondition(failing.canCancelCheckout && !failing.canBuy(.pangolin))
        await failing.cancelCheckout(session: thirdSession)
        precondition(!failing.canCancelCheckout && failing.canBuy(.platypus))
        print("Special purchase recovery, account binding, pending holds, errors, lapses, cancellation and delivery checks passed")
    }
}

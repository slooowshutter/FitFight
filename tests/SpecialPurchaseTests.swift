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
    enum ProductType { case consumable, nonConsumable }
    let id: String
    let type = ProductType.consumable
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
    let id: UInt64
    let productID: String
    let appAccountToken: UUID?
    var finished = false
    static var continuation: AsyncStream<VerificationResult<Transaction>>.Continuation?
    static var pending: [Transaction] = []
    static var updates: AsyncStream<VerificationResult<Transaction>> {
        AsyncStream { continuation = $0 }
    }
    static var unfinished: AsyncStream<VerificationResult<Transaction>> {
        AsyncStream { stream in
            for item in pending where !item.finished { stream.yield(.verified(item)) }
            stream.finish()
        }
    }
    init(account: UUID, id: UInt64 = 123, productID: String = "com.fitfight.mvp.special") {
        appAccountToken = account
        self.id = id
        self.productID = productID
    }
    func finish() async { finished = true }
}

enum AppStore { static func sync() async throws {} }
enum StoreKitError: Error { case userCancelled }
enum StockCompanion: String, CaseIterable {
    case blackPanther = "limited-black-panther", loneWolf = "limited-lone-wolf", tiger = "limited-tiger"
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
    static var owned: Set<String> = []
    static var failRead = false
    static var failClaim = false
    static var claims: [String] = []
    static var legacyClaims: [String] = []
    /// The server keeps the Special a charge first unlocked.
    static var recorded: [String: String] = [:]
    func specials(accessToken: String) async throws -> SpecialStoreSnapshot {
        if Self.failRead {
            Self.failRead = false
            throw URLError(.notConnectedToInternet)
        }
        return SpecialStoreSnapshot(appAccountToken: Self.account, environment: "Sandbox", purchasesEnabled: true,
            productId: "com.fitfight.mvp.special",
            editions: StockCompanion.allCases.map { .init(id: $0.rawValue, status: Self.owned.contains($0.rawValue) ? .yours : .available) },
            conflicts: [])
    }
    func claimSpecialPurchase(companionId: String, signedTransaction: String, accessToken: String) async throws -> SpecialClaimResult {
        if Self.failClaim {
            Self.failClaim = false
            throw URLError(.networkConnectionLost)
        }
        Self.claims.append(companionId)
        let key = "\(Self.claims.count)"
        let companion = Self.recorded[key] ?? companionId
        Self.owned.insert(companion)
        return .init(outcome: .owned, transactionId: key, companionId: companion)
    }
    func claimSpecial(companionId: String, signedTransaction: String, accessToken: String) async throws -> SpecialClaimResult {
        Self.legacyClaims.append(companionId)
        Self.owned.insert(companionId)
        return .init(outcome: .owned, transactionId: "1", companionId: companionId)
    }
}

@main
struct SpecialPurchaseTests {
    @MainActor static func main() async throws {
        // Older servers sent five statuses and no shared product; current ones send the consumable.
        let decoder = JSONDecoder()
        let current = try decoder.decode(SpecialStoreSnapshot.self, from: Data("""
            {"app_account_token":"6283b4c1-0e8f-4caa-b04b-827b6f1e925b","environment":"Sandbox","purchases_enabled":true,
             "product_id":"com.fitfight.mvp.special","conflicts":[],
             "editions":[{"id":"limited-tiger","product_id":"com.fitfight.mvp.special.tiger","status":"yours"}]}
            """.utf8))
        precondition(current.productId == "com.fitfight.mvp.special" && current.editions[0].status == .yours)
        let older = try decoder.decode(SpecialStoreSnapshot.self, from: Data("""
            {"app_account_token":"6283b4c1-0e8f-4caa-b04b-827b6f1e925b","environment":"Sandbox","purchases_enabled":true,
             "conflicts":[],"editions":[{"id":"limited-tiger","product_id":"com.fitfight.mvp.special.tiger","status":"taken"}]}
            """.utf8))
        precondition(older.productId == nil && older.editions[0].status == .taken)

        let session = SessionStore()
        let userId = session.profile!.userId
        let draftKey = "ff.special.draft.\(userId.uuidString)"
        defer {
            UserDefaults.standard.removeObject(forKey: draftKey)
            UserDefaults.standard.removeObject(forKey: "ff.special.pending.since.\(userId.uuidString)")
        }
        let purchases = SpecialPurchases()
        let observer = Task { await purchases.observe(session: session) }
        defer { observer.cancel() }
        for _ in 0..<100 where purchases.product == nil { try await Task.sleep(for: .milliseconds(10)) }
        precondition(purchases.canBuy(.blackPanther) && purchases.canBuy(.loneWolf))

        // A completed charge unlocks the chosen Special; the account can keep buying others.
        let first = Transaction(account: FitFightAPI.account, id: 1)
        Product.result = .success(.verified(first))
        let bought = await purchases.buy(.blackPanther, session: session)
        precondition(bought)
        precondition(first.finished && FitFightAPI.claims == ["limited-black-panther"])
        precondition(UserDefaults.standard.string(forKey: draftKey) == nil)
        precondition(!purchases.canBuy(.blackPanther), "An owned Special is not sold again")
        precondition(purchases.canBuy(.loneWolf), "One account can own many Specials")

        // Cancelling or Apple refusing charges nothing and leaves buying open.
        Product.result = .userCancelled
        let cancelled = await purchases.buy(.loneWolf, session: session)
        precondition(!cancelled)
        precondition(purchases.canBuy(.loneWolf) && purchases.message.isEmpty && UserDefaults.standard.string(forKey: draftKey) == nil)
        Product.failure = Product.PurchaseError.purchaseNotAllowed
        let refused = await purchases.buy(.loneWolf, session: session)
        precondition(!refused)
        precondition(purchases.canBuy(.loneWolf) && !purchases.message.isEmpty)
        Product.failure = StoreKitError.userCancelled
        _ = await purchases.buy(.loneWolf, session: session)
        precondition(purchases.canBuy(.loneWolf) && purchases.message.isEmpty, "A dismissed sign-in is quiet")
        Product.failure = nil

        // Ask to Buy: the chosen Special waits with the charge and unlocks when Apple approves.
        Product.result = .pending
        let waiting = await purchases.buy(.loneWolf, session: session)
        precondition(!waiting)
        precondition(purchases.pendingPurchase && !purchases.canBuy(.tiger), "Never start a second charge while one is pending")
        let approved = Transaction(account: FitFightAPI.account, id: 2)
        Transaction.continuation?.yield(.verified(approved))
        for _ in 0..<100 where !approved.finished { try await Task.sleep(for: .milliseconds(10)) }
        precondition(approved.finished && FitFightAPI.claims.last == "limited-lone-wolf" && !purchases.pendingPurchase)
        precondition(FitFightAPI.owned.contains("limited-lone-wolf"))

        // A charge from another FitFight account is never claimed here.
        let foreign = Transaction(account: UUID(), id: 3)
        Transaction.continuation?.yield(.verified(foreign))
        try await Task.sleep(for: .milliseconds(30))
        precondition(!foreign.finished && FitFightAPI.claims.count == 2)
        observer.cancel()
        await observer.value

        // A crash after Apple charged: the saved choice claims the unfinished charge on the next launch.
        UserDefaults.standard.set("limited-tiger", forKey: draftKey)
        let interrupted = Transaction(account: FitFightAPI.account, id: 4)
        Transaction.pending = [interrupted]
        let restarted = SpecialPurchases()
        let restartedObserver = Task { await restarted.observe(session: session) }
        for _ in 0..<100 where !interrupted.finished { try await Task.sleep(for: .milliseconds(10)) }
        precondition(interrupted.finished && FitFightAPI.claims.last == "limited-tiger")
        restartedObserver.cancel()
        await restartedObserver.value

        // A charge whose choice was lost stays unfinished, then unlocks the next Special picked without paying.
        FitFightAPI.owned = []
        let orphan = Transaction(account: FitFightAPI.account, id: 5)
        Transaction.pending = [orphan]
        let recovering = SpecialPurchases()
        let recoveringObserver = Task { await recovering.observe(session: session) }
        defer { recoveringObserver.cancel() }
        for _ in 0..<100 where !recovering.hasUnclaimedCharge { try await Task.sleep(for: .milliseconds(10)) }
        precondition(recovering.hasUnclaimedCharge && !orphan.finished && FitFightAPI.claims.count == 3)
        let presented = Product.presented
        let unlocked = await recovering.buy(.loneWolf, session: session)
        precondition(unlocked)
        precondition(orphan.finished && Product.presented == presented && FitFightAPI.claims.last == "limited-lone-wolf")
        precondition(!recovering.hasUnclaimedCharge)

        // A failed claim keeps the charge and its choice for Restore purchases.
        let retried = Transaction(account: FitFightAPI.account, id: 6)
        Product.result = .success(.verified(retried))
        FitFightAPI.failClaim = true
        let unclaimed = await recovering.buy(.tiger, session: session)
        precondition(!unclaimed)
        precondition(!retried.finished && UserDefaults.standard.string(forKey: draftKey) == "limited-tiger")
        Transaction.pending = [retried]
        await recovering.restore(session: session)
        precondition(retried.finished && FitFightAPI.claims.last == "limited-tiger" && !recovering.pendingPurchase)
        precondition(recovering.message == String(appLocalized: "Purchases checked. Your Specials are ready to use."))

        // A legacy one-of-a-kind charge still records under its own Special.
        let legacy = Transaction(account: FitFightAPI.account, id: 7, productID: "com.fitfight.mvp.special.black_panther")
        Transaction.pending = [legacy]
        await recovering.restore(session: session)
        precondition(legacy.finished && FitFightAPI.legacyClaims == ["limited-black-panther"])
        print("Special purchase decoding, many-per-account ownership, pending, interrupted, orphaned, failed-claim, account binding and legacy checks passed")
    }
}

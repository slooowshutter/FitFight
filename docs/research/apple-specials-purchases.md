# Paid Specials with Apple In-App Purchase

Researched on 20 September 2026 against Apple documentation and Apple's App Store Server Library source. This note informs the requested implementation. It is not evidence that products, credentials, agreements, or a release have been configured or approved.

## Recommendation

Use StoreKit 2 non-consumable In-App Purchases for permanently owned Specials, one product identifier for each of the 40 artworks, with Family Sharing disabled. Persist ownership independently from the equipped profile companion. Switching to a free companion must not release a paid Special. Apple defines a non-consumable as purchased once without expiry or depletion; consumables are used up and repurchased. [Product types][types]

There is a material limitation: ordinary StoreKit does not expose a documented stock reservation or server veto before charging for a non-consumable. A database constraint can guarantee one owner, but cannot guarantee that Apple never charges a second purchaser. An expiring reservation is particularly unsafe when purchases remain pending. Do not describe exclusivity enforcement as a guarantee against duplicate charges. The reservation and unresolved-payment policy needs to be settled before selling these items.

On 21 September, Marc specified EUR 0.99 per Special. The implementation is using his earlier "users can only have one" instruction as one permanently owned Special per account. Permanent ownership must not follow the existing free picker's release-on-switch behavior.

## What Apple supports

### Payment method and product catalog

Apple's ordinary digital-goods flow is In-App Purchase: guideline 3.1.1 covers unlocking functionality and premium content inside an app. Apple Pay is named in guideline 3.1.3(e) for physical goods and services consumed outside the app. StoreKit displays Apple's purchase confirmation sheet and uses the customer's Apple Account payment methods. No Apple Pay merchant ID or Apple Pay processing certificate is needed for this StoreKit integration. [Review guidelines][guidelines], [In-App Purchase overview][iap]

External purchasing rules vary by storefront and agreement. Current guideline 3.1.1(a) permits certain external links, including a United States storefront exception. That does not establish a universal Stripe exemption or a guaranteed fee saving. Implementing a future external-payment path requires a separate check of the relevant storefront terms. [Review guidelines][guidelines]

Create a distinct `NON_CONSUMABLE` product for each artwork with a stable identifier, such as `com.fitfight.mvp.special.pangolin`. Apple's limit is 10,000 In-App Purchase products per app, so 40 products do not require a large-catalog API. Product IDs cannot be edited or reused after creation, even after deleting the original product. [Configuration overview][configuration], [Product information][product-information]

Live API evidence on 20 September: despite the help page listing hyphens as permitted, product creation rejected them with `409 ENTITY_ERROR.ATTRIBUTE.INVALID`: "A product ID can only contain alphanumeric characters, underscores, and periods." FitFight's preparation script therefore removes the internal `limited-` prefix and replaces remaining hyphens with underscores, for example `limited-spotted-quoll` becomes `com.fitfight.mvp.special.spotted_quoll`. [Cloud response](https://github.com/slooowshutter/FitFight/actions/runs/35538395443)

Keep Family Sharing off. It grants access to up to five additional family members, and enabling it on an In-App Purchase cannot be undone. This conflicts with one-owner items. Also reject `FAMILY_SHARED` transactions from the exclusive-ownership path if one is received. [Family Sharing][family]

Fetch current localized prices from `Product` and display `displayPrice` in the purchase UI. Set the commercial price in App Store Connect, not in app code. Apple can derive other storefront prices from a chosen base territory, taking exchange rates and taxes into account. [Product][product], [Pricing][pricing]

### Reservations, pending purchases, and scarce stock

**Documented facts:**

- `Product.purchase(options:)` presents the system confirmation sheet and returns a purchase result. A customer can confirm or cancel. A pending purchase can later succeed through `Transaction.updates`. [Purchase][purchase], [Pending result][pending]
- `PurchaseIntent` is a handoff for promoted purchases and certain subscription offers initiated outside the app. It is not a server authorization token for a payment. [PurchaseIntent][purchase-intent]
- Standard `PurchaseOption` values add account information, quantity, offers, storefront behavior, and testing behavior. They do not document a stock quantity, application-server callback, or deadline for a non-consumable purchase. [PurchaseOption][purchase-option]
- Apple's signed StoreKit request mechanisms cover Advanced Commerce, promotional offers, and introductory-offer eligibility. The signed payload must not contain `exp`; Apple derives an expiry from `iat`. A custom purchase option is documented for Advanced Commerce, not arbitrary server authorization of normal products. [Signed requests][signed-requests], [Advanced Commerce request][advanced-request]
- Advanced Commerce requires approval per app and is intended for eligible core business models such as exceptionally large catalogs. Its one-time-charge API uses server-signed requests, but the reviewed documentation does not promise that a merchant-specified inventory reservation expires or that an already pending payment can be canceled. It should not be assumed available or appropriate for 40 avatar products. [Advanced Commerce eligibility][advanced-eligibility], [Advanced Commerce request][advanced-request]
- `Transaction.finish()` acknowledges delivery of content. It is not authorization to capture funds or a way to cancel a successful charge. [Finish][finish]

**Implications for FitFight:**

1. Reserve the specific artwork atomically on the server before showing the purchase sheet. Require authentication and make repeated requests by the same purchaser idempotent. This prevents two supported clients from starting normal checkout simultaneously.
2. Never release a reservation merely because the sheet closed, the app disconnected, the user signed out, or a short timer elapsed. A payment can still be pending or already completed but not delivered to the server.
3. A permanent reservation until a known outcome avoids the expiry race for supported clients but can strand the entire 40-item supply through abandoned checkouts. A client report of cancellation is also not cryptographic evidence that every previous purchase attempt is canceled.
4. A modified client can request an otherwise available StoreKit product without using FitFight's preflight endpoint. StoreKit's product is available to Apple Accounts generally; a normal product ID is not an exclusive checkout capability.
5. Preserve a durable record of every verified charge, including one that cannot be fulfilled. Never silently discard it or report success while refusing the purchased content. Standard StoreKit has a customer refund-request UI; the request is not a promise that Apple grants an immediate automatic refund. [Refund support][refund-support]

Changing to generic credits, substituting another artwork, allowing duplicate owners, or leaving checkout reservations permanent changes the requested commercial promise. Those are product decisions, not technical details that should be silently substituted.

## Server verification and entitlement storage

Use Apple's maintained `@apple/app-store-server-library` rather than implementing Apple certificate-chain validation. Its `SignedDataVerifier` takes DER-encoded Apple root certificates, an online-check flag, the expected environment, bundle ID, and production app Apple ID. Verification checks the certificate chain, signature, bundle, and environment; notification verification also checks the production app Apple ID. The production ID is required when constructing that verifier. Verification alone needs public root certificates, not an In-App Purchase private key. [Official Node library][library], [Verifier implementation][verifier], [Apple PKI][pki]

Use the In-App Purchase private key only on the server when calling `AppStoreServerAPIClient`, for example `getTransactionInfo`. The library generates the authorization JWT. API requests are environment-specific, and Get Transaction Info supports finished transactions and every product type. [Official Node library][library], [Get Transaction Info][transaction-info]

Recommended trust boundary and invariants:

- Verify every incoming transaction JWS from both the app and Apple notifications before applying it. Verify the outer notification JWS and its embedded `signedTransactionInfo`.
- Accept only a known product from the 40-product mapping, the expected `Non-Consumable` type, a purchased ownership type, and a valid original transaction ID/transaction ID. Reject revoked purchases from the grant path.
- Use one server-created UUID per FitFight account as `appAccountToken`, and pass it into every purchase. Apple recommends reusing the same account token for a given customer. Require the verified token to match the authenticated account on client-originated claims. Tokens are associations, not authentication credentials. [Account tokens][account-token], [WWDC25 server APIs][wwdc25]
- Persist transactions with environment plus transaction ID as a uniqueness boundary. Persist the environment plus original transaction ID binding to its FitFight owner. Repeated app deliveries, restores, and notifications must resolve idempotently to the same entitlement.
- Persist notification UUIDs for deduplication and update entitlement state transactionally. Do not allow a delayed older purchase payload to overwrite a later refund/revocation. An Apple-signed historical JWS remains authentic after its entitlement changes; query current transaction information when reconciling stale or conflicting evidence. [Transaction payload][transaction-payload], [Get Transaction Info][transaction-info]
- Have the profile-save path independently enforce paid ownership for every Special. Client UI checks alone would leave the existing profile update endpoint as a free bypass.
- Keep purchase state and the currently equipped `profiles.companion_id` separate. The database must enforce a single owner per artwork within its payment environment, regardless of concurrent requests or profile changes.
- Finish the StoreKit transaction only after the server durably delivers the entitlement. Keep a transaction-update listener active from app startup so pending, interrupted, or externally delivered transactions are processed. [Finish][finish], [Pending result][pending]

These are FitFight design recommendations derived from Apple's trust boundaries, not a claim that Apple provides the inventory database or account authorization.

## Sandbox, TestFlight, and App Review

Sandbox purchases simulate payments without charging. TestFlight apps always use Sandbox for purchases. Apple also reviews purchases in Sandbox, including a production-signed app, so accepting only Production transactions at the production server can cause purchase review failures. [Sandbox testing][sandbox], [Apple IAP FAQ, App Review cases][faq]

The old FAQ's `verifyReceipt` URL and 21007 fallback are historical receipt-API instructions. For this StoreKit 2 implementation, use correctly configured JWS verifiers and App Store Server API clients; do not introduce deprecated receipt verification to reproduce that older example.

**Recommended review arrangement:** allow the production service to verify Sandbox evidence for a dedicated, server-configured review/test account, while maintaining separate Sandbox inventory and entitlements. Configure that account's preflight availability and equip behavior to the Sandbox namespace before a purchase begins. Explain the test account and test inventory in App Review notes. An untrusted client parameter, app version header, or merely decoding an unverified JWS must never switch a real account into a paid Production entitlement.

Sandbox ownership must never consume, release, or acquire Production inventory. A review account's test companion should not become a real public owner or displace a paying customer. Exactly how the existing profile API isolates the review account is implementation work; Apple does not provide a FitFight-specific sandbox database design. Exercise the full reviewer account flow using a production-configured build before submission.

For notifications, configure both production and Sandbox URLs in App Store Connect and handle the signed environment explicitly. A signed Sandbox transaction remains a test payment even if it arrives at a production-hosted URL. [Configuration overview][configuration], [Sandbox testing][sandbox]

## Restores, deletion, and refunds

Use `Transaction.currentEntitlements` for normal startup and account reconciliation. Non-consumables appear there; revoked or refunded products do not. Provide an explicit Restore Purchases action using `AppStore.sync()`, which can prompt for Apple Account authentication and should only be called after a user action. [Current entitlements][entitlements], [Sync][sync]

For an existing FitFight account, restoration should recover the same permanent ownership without charging again. A transaction already bound to another live FitFight account must not transfer just because someone submits its JWS or signs into a different FitFight account on the same device.

Deleting a Supabase account does not cancel Apple's permanent purchase. Do not sell the artwork to someone else merely because its owner deleted their profile: that creates a later restore conflict. Apple requires account deletion and removal of associated personal data except data legally required to be retained. The deletion flow needs clear purchase consequences and an agreed retention/recovery policy, rather than keeping all old account data forever. [Deletion requirements][deletion], [Product types][types], [Restore requirements][iap]

Apple's Set App Account Token endpoint can update the binding for existing non-consumables. That makes deliberate account recovery technically possible, but Apple does not authenticate a replacement Supabase account for FitFight. A recovery flow must prove entitlement and ownership, ensure the previous account is deleted or legitimately recovered, prevent transfers from a live owner, atomically update FitFight's binding, and then update Apple's token. Keeping a minimal purchase record is not by itself a legal basis for retaining personal data. [Set App Account Token][set-account-token]

Handle Notifications V2 for `ONE_TIME_CHARGE`, `REFUND`, `REFUND_REVERSED`, and any applicable revocation. `ONE_TIME_CHARGE` has been available in Production since 27 May 2025; older documentation and forum answers calling it Sandbox-only are outdated. [Notification types][notification-types], [Notification changelog][notification-changelog]

Record refund/revocation state before changing equip state. A full refund should remove access; a reversed refund can reinstate the purchase. Consequently, automatically relisting a refunded one-of-one artwork can create another collision if the refund is reversed. Retiring such artwork until the entitlement is conclusively resolved is safer than immediately reselling it. This stock policy remains a FitFight product choice. Apple's current transaction payload also contains revocation type and percentage fields; partial-refund behavior for an indivisible artwork should be defined explicitly rather than inventing fractional ownership. [Notification types][notification-types], [Transaction payload][transaction-payload], [WWDC25 server APIs][wwdc25]

Respond with success only after a notification has been durably handled. Apple retries unsuccessful Production V2 notifications five times, at 1, 12, 24, 48, and 72 hours after the previous attempt. Sandbox sends once. Use notification history and transaction queries to reconcile missed events, and request a test notification to verify the endpoint. [Notification responses][notification-responses]

## App Store Connect setup

1. Verify the Account Holder has signed the Paid Apps Agreement. Apple's Sandbox checklist requires an active Developer Program membership and a signed agreement. Banking and required tax forms must be completed to receive proceeds; an agent should not invent legal or banking details. A signed agreement does not by itself prove product lookup or Sandbox checkout works. [Agreements][agreements], [Banking][banking], [Sandbox testing][sandbox]
2. Keep the existing App Store Connect API key for catalog/distribution automation. Create a separate In-App Purchase key under Users and Access > Integrations > Keys > In-App Purchase. Apple explicitly distinguishes this from the App Store Connect API key. Admin access is required according to Apple's library README. [Key creation][keys], [Signed requests][signed-requests], [Official Node library][library]
3. Download that private `.p8` once and store it in the server's secret manager. Apple does not keep a downloadable copy. Record the key ID and issuer ID without placing the private key in source, app bundles, logs, or chat. No extra signing key is needed simply to verify an incoming JWS. [Key creation][keys], [Official Node library][library]
4. Create the 40 product records with `POST /v2/inAppPurchases`, type `NON_CONSUMABLE`, and explicit immutable product IDs. Keep Family Sharing disabled. [Create IAP][create-product], [Family Sharing][family]
5. Current metadata uses a version container: create `POST /v1/inAppPurchaseVersions`, then attach English and French names/descriptions via `POST /v2/inAppPurchaseLocalizations` with a `version` relationship. The older direct v1 localization flow is deprecated from App Store Connect API 4.4.1 but remains for existing integrations. [Metadata migration][metadata-migration]
6. Fetch valid price points for the chosen base territory, then set the price schedule and intended storefront availability. The pricing endpoint remains `POST /v1/inAppPurchasePriceSchedules`; the metadata version migration does not change it. Do not guess an opaque price-point ID. [Pricing][pricing], [Metadata migration][metadata-migration]
7. Supply review metadata/screenshots and configure Notifications V2 production and Sandbox endpoints. Product metadata can take up to one hour to appear in Sandbox. [Configuration overview][configuration], [Create IAP][create-product]
8. Test before submission. The first In-App Purchase must be submitted with a new app version. Configuring a catalog does not authorize publishing it, submitting for review, merging a branch, or uploading a build. [Configuration overview][configuration]

The current documented create-product payload has this shape; use the real app Apple ID and an agreed permanent product ID. This does not set pricing, availability, or submit anything for review. [Managing IAP][manage-products]

```json
{
    "data": {
        "type": "inAppPurchases",
        "attributes": {
            "name": "Special Pangolin",
            "productId": "com.fitfight.mvp.special.pangolin",
            "inAppPurchaseType": "NON_CONSUMABLE",
            "reviewNote": "Exclusive digital companion. Permanent ownership. Family Sharing disabled."
        },
        "relationships": {
            "app": {
                "data": {
                    "type": "apps",
                    "id": "<appAppleId>"
                }
            }
        }
    }
}
```

Apple's current limits are 64 characters for the internal reference name, 100 for the product ID, 2 to 30 for the localized display name, and at most 45 for the localized description. The description can describe the purchase while the longer funny caption stays in the app. The documentation's create response has `familySharable: false`; verify it after creation. Endpoint documentation was checked, but availability of the version-based metadata endpoints against this team's live account has not been tested by this research. [Product information][product-information], [Managing IAP][manage-products]

## Required verification before paid rollout

- Cloud migration tests: concurrency, replay, ownership-preserving swaps, unauthorized profile-save attempts, rejected cross-account claims, and strict Sandbox/Production isolation.
- Apple Sandbox tests: successful purchase, cancellation, pending approval, interrupted delivery, duplicate notification, reinstall/restore, account switching, refund and refund reversal.
- Delayed success after checkout abandonment and after any proposed reservation timeout. A passing ordinary checkout does not resolve the scarce-stock problem.
- Production-configured reviewer account purchasing against separate Sandbox inventory.
- Actual StoreKit product lookup, localized price display, private-key server API authorization, test-notification delivery, and documented agreement/catalog status.
- Deleted-account restore policy and refund-stock policy agreed before enabling live sale. Record code checks, cloud checks, configuration, review, and live deployment separately.

[types]: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-types/
[guidelines]: https://developer.apple.com/app-store/review/guidelines/#payments
[iap]: https://developer.apple.com/in-app-purchase/
[configuration]: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/overview-for-configuring-in-app-purchases/
[product-information]: https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/
[family]: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/turn-on-family-sharing-for-in-app-purchases/
[product]: https://developer.apple.com/documentation/storekit/product
[pricing]: https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/
[purchase]: https://developer.apple.com/documentation/storekit/product/purchase(options:)
[pending]: https://developer.apple.com/documentation/storekit/product/purchaseresult/pending
[purchase-intent]: https://developer.apple.com/documentation/storekit/purchaseintent
[purchase-option]: https://developer.apple.com/documentation/storekit/product/purchaseoption
[signed-requests]: https://developer.apple.com/documentation/storekit/generating-jws-to-sign-app-store-requests
[advanced-request]: https://developer.apple.com/documentation/storekit/sending-advanced-commerce-api-requests-from-your-app
[advanced-eligibility]: https://developer.apple.com/in-app-purchase/advanced-commerce-api/
[finish]: https://developer.apple.com/documentation/storekit/transaction/finish()
[refund-support]: https://developer.apple.com/videos/play/tech-talks/10887/
[library]: https://github.com/apple/app-store-server-library-node
[verifier]: https://github.com/apple/app-store-server-library-node/blob/main/jws_verification.ts
[pki]: https://www.apple.com/certificateauthority/
[transaction-info]: https://developer.apple.com/documentation/appstoreserverapi/get-transaction-info
[account-token]: https://developer.apple.com/documentation/appstoreserverapi/appaccounttoken
[transaction-payload]: https://developer.apple.com/documentation/appstoreserverapi/jwstransactiondecodedpayload
[wwdc25]: https://developer.apple.com/videos/play/wwdc2025/249/
[sandbox]: https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox
[faq]: https://developer.apple.com/library/archive/technotes/tn2413/_index.html
[entitlements]: https://developer.apple.com/documentation/storekit/transaction/currententitlements
[sync]: https://developer.apple.com/documentation/storekit/appstore/sync()
[deletion]: https://developer.apple.com/support/offering-account-deletion-in-your-app/
[set-account-token]: https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token
[notification-types]: https://developer.apple.com/documentation/appstoreservernotifications/notificationtype
[notification-changelog]: https://developer.apple.com/documentation/appstoreservernotifications/app-store-server-notifications-changelog
[notification-responses]: https://developer.apple.com/documentation/appstoreservernotifications/responding-to-app-store-server-notifications
[agreements]: https://developer.apple.com/help/app-store-connect/manage-agreements/sign-and-update-agreements/
[banking]: https://developer.apple.com/help/app-store-connect/manage-banking-information/enter-banking-information/
[keys]: https://developer.apple.com/documentation/appstoreserverapi/creating-api-keys-to-authorize-api-requests
[create-product]: https://developer.apple.com/documentation/appstoreconnectapi/post-v2-inapppurchases
[metadata-migration]: https://developer.apple.com/documentation/appstoreconnectapi/migrating-in-app-purchase-metadata-to-v2
[manage-products]: https://developer.apple.com/documentation/appstoreconnectapi/managing-in-app-purchases

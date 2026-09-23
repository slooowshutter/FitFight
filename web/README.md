# FitFight API (Next.js)

iOS command API only. No marketing pages. Node.js runtime, never Edge.

## Marc — Vercel

1. Create a Vercel project on this GitHub repo.
2. Set **Root Directory** to `web/`.
3. Env vars (Vercel dashboard only — never paste secrets in git or chat):

| Vercel env                           | Preview + `develop`                                                           | Production (`main`)                     |
| ------------------------------------ | ----------------------------------------------------------------------------- | --------------------------------------- |
| `NEXT_PUBLIC_SUPABASE_URL`           | Supabase **develop** project URL                                              | Main / production project URL           |
| `SUPABASE_SECRET_KEY`                | develop secret key                                                            | production secret key                   |
| `DATABASE_URL`                       | develop transaction-pooler URL                                                | production transaction-pooler URL       |
| `FITFIGHT_APP_URL`                   | staging site origin (optional)                                                | production site origin (optional)       |
| `APPLE_SIGN_IN_TEAM_ID`              | Apple developer Team ID                                                       | same Team ID                            |
| `APPLE_SIGN_IN_KEY_ID`               | Sign in with Apple key ID                                                     | same key ID                             |
| `APPLE_SIGN_IN_PRIVATE_KEY`          | Sign in with Apple `.p8` contents                                             | same key, or its production replacement |
| `APPLE_SIGN_IN_CLIENT_ID`            | `com.fitfight.mvp`                                                            | `com.fitfight.mvp`                      |
| `APPLE_SIGN_IN_TOKEN_ENCRYPTION_KEY` | separate base64 32-byte key                                                   | separate base64 32-byte key             |
| `NOTION_TOKEN`                       | Notion internal integration token with access to Product Backlog              | same token                              |
| `CURSOR_API_KEY`                     | Cursor Cloud Agents API key (Dashboard → API Keys) for admin “Send to Cursor” | same key                                |

Preview deployments must use the **develop** Supabase project. Never point Preview at production.
The Sign in with Apple key must be enabled for the FitFight App ID. It is not the
App Store Connect API key. Keep the staging and production token-encryption keys stable,
because changing one makes already stored revocation tokens unreadable.

Use Supavisor transaction mode (port `6543`) for `DATABASE_URL`, with prepared statements disabled by the backend. The password stays in Vercel. The `private` schema does not need to be exposed through the Data API.

After a `web/` push, Vercel deploys. iOS uses the User JWT as `Authorization: Bearer <jwt>`.

## Specials purchase setup

The dedicated In-App Purchase credentials are stored as sensitive Vercel
Preview/Production variables and GitHub secrets: `APPLE_IAP_KEY_ID`,
`APPLE_IAP_ISSUER_ID`, and `APPLE_IAP_PRIVATE_KEY`. The purchase key is separate
from the Sign in with Apple and App Store Connect distribution keys.

The 40 non-consumable product records have English/French metadata and Family
Sharing disabled. All are priced at EUR 0.99 with France as the base territory
and Apple's automatic equivalent prices elsewhere. The Account Holder has
signed the Paid Apps Agreement. Apple still requests payout banking and tax
information from the Account Holder.

Deployment variables (configured separately from the private keys):

| Variable | Preview | Production |
| --- | --- | --- |
| `APPLE_IAP_ENVIRONMENT` | `Sandbox` | `Production` |
| `APPLE_SPECIALS_ENABLED` | `true` | `false` |
| `APPLE_IAP_REVIEW_USER_IDS` | empty | App Review account IDs |

The paid migration must land before the backend, then the native app. StoreKit
reserves an edition through `/api/v1/me/specials/checkout` before presenting the
Apple sheet. A stable server-created account token binds the purchase. Unpaid
holds lapse after 30 minutes. A later verified charge is owned if the Special is
still free and the account has no other Special, otherwise it is a refundable
conflict. The app releases a hold when the user cancels or Apple refuses the
purchase before charging.

`lib/apple/special-purchase.ts` verifies both the submitted receipt and Apple's
current transaction. `/api/v1/me/specials/transactions` persists the result in a
private purchase ledger. Ownership survives companion changes and account
deletion. Refunds retire the artwork and remove it from the profile; a later
refund reversal restores ownership. A conflicting verified charge is retained
and the app offers Apple's refund-request sheet. Apple determines refunds.

The preview release job requires the deployed staging endpoint, then configures
App Store Server Notifications V2. Apple's test-delivery check only warns:
`https://staging.fitfight.app/api/apple/specials/notifications/sandbox`.
The production path is `/api/apple/specials/notifications/production` on the
production domain, only with its separately authorized rollout. Request and
verify an Apple test notification before device testing. Notifications and
restores share signature verification and the same transactional ledger.

Production sale remains disabled, and the app hides Specials while it is. Enable
it on production while a build is in review. App Review buys in Sandbox, so give
it a dedicated sign-in and list that FitFight user ID in production
`APPLE_IAP_REVIEW_USER_IDS`; only listed accounts use the separate Sandbox shelf.
See [current evidence](../docs/status.md)
and [Apple purchase research](../docs/research/apple-specials-purchases.md).

`lib/apple/apple-root-certificates.json` contains public DER root certificates
downloaded from [Apple PKI](https://www.apple.com/certificateauthority/), with
source URLs and SHA-256 fingerprints. JSON bundling keeps these trust roots in
the server build; no private key belongs in that file. Certificate-chain and
online revocation checking use Apple's `SignedDataVerifier`.

## Local

```bash
cp .env.example .env.local
# fill URL, secret, and pooled database URL from the develop project
npm install
npm run dev
```

- `GET /api/health` → `{ "ok": true }`
- Commands live under `/api/v1/...` (see `contracts/openapi.yaml`)

```bash
npm run typecheck
npm test
```

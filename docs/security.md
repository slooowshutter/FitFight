# Security, privacy, auth

Contract for the backend and for anything that leaves the phone. The app is
still fixtures (`FIGHT-742`, Maya, no HealthKit, no server). Do not invent
screens listed in [`design/source/INVENTORY.md`](design/source/INVENTORY.md).
Do follow these picks when those features are built.

Marc is in western Europe. Friends will be too. Treat GDPR as in force, not as
a later nice-to-have. Health numbers are special-category data.

Map: [`system/README.md`](system/README.md). Compile path: [`sync.md`](sync.md)
and [`system/ingest.md`](system/ingest.md). Types: [`system/layers.md`](system/layers.md).
**This file wins** on identity, authz, secrets, abuse, retention, and **what may
leave the phone**. Sync wins on queue mechanics. Canonical samples are **not**
uploaded — only daily totals. `FIGHT-742` in fixtures is not a generator.

## Picks

| Topic | Pick |
| --- | --- |
| Sign-in | **Sign in with Apple only.** Identity is Apple `sub`, never email. |
| Session | **Our** access + refresh tokens. Apple’s identity token is not a session. Keychain: `AfterFirstUnlockThisDeviceOnly`, not iCloud-syncable. Not sqlite, not UserDefaults. |
| Device / APNs | One row per device. Token upsert on launch, delete on logout and on APNs rejection. |
| Health off-phone | **Daily totals for the fight’s metric, for dates inside that fight’s window.** Nothing else. |
| HealthKit deny | Indistinguishable from zeros. Do not guess. **No successful upload in the window → unscored, buy-in refunded.** |
| Strava | **Not in v1.** When it lands: tokens in Keychain, phone fetches, same aggregate upload as HealthKit. Server never stores Strava tokens. Prefer HealthKit if Strava already writes into it (avoids the double-count bug in the mock). |
| Join codes | UUID internally. Display `FF-XXXX-XXXX` (8 Crockford chars, ~40 bits). **Never sequential `FIGHT-742`.** |
| Authz | **App-layer on an API we own.** Not RLS-only. Postgres not on the internet. |
| Audit | Append-only on the server. Auth, fight membership, accepted scores, export/delete. |
| TestFlight | **Today:** every app push (see `shipping.md`). **Recommendation:** `main` + daily cron only once a public API exists, so a PR Fastfile cannot mint a hostile binary. Marc’s call; do not change the workflow in a docs PR. |
| Transport | ATS on, HTTPS only. **No certificate pinning** in v1. |
| Money | **IOU among friends.** No cards, no in-app cash movement, until legal says otherwise. |
| Mail | **None in v1.** Pushes only. Then Hide My Email is a stored string we may never use. |

## Threat model

**What we protect**

Apple `sub`, session refresh tokens, APNs tokens, HealthKit-derived daily
scores, (later) Strava OAuth tokens, fight membership, IOU outcomes, relay
emails, the App Store Connect `.p8`.

**Who might care**

| Actor | What they can do |
| --- | --- |
| Friend using the app | See fights they belong to. Tempted to fake steps. |
| Random internet | Clone the public repo. Hit the API if we leave it open. Guess join codes if they are short. |
| Cloud agent | Push code. Cannot read GitHub secrets. **Can edit `fastlane/` so the next Actions run leaks them.** |
| GitHub Actions `macos-26` | Holds the ASC `.p8` during a TestFlight job. |
| Stolen phone | Keychain + unlocked Health. |
| Malicious Health app on the same phone | Write fake samples into HealthKit. We will not fully stop this. |

**Trust boundaries**

1. Phone (HealthKit, Keychain, UserDefaults). UserDefaults is not a vault.
2. FitFight API — the only process allowed to see health aggregates.
3. Postgres — not reachable except through that API.
4. Apple (SIWA, APNs, App Store Connect).
5. GitHub (public git + Actions secrets).
6. Strava — later, and only from the phone.

**Invariants**

- The client is a dumb reporter. It does not decide scores, rank, pot, or who is in a fight.
- Raw HealthKit samples, GPS, heart rate, sleep, weight never leave the device.
- Secrets never enter git or chat. Team ID `C92DPD8ME2` is not a secret; `.p8` files are.
- Email is not an identity.

**What we accept we cannot stop**

Friends can write junk into HealthKit. Social fights plus “unscored if you
never synced” is the control. Real-money pots would make cheating worth it;
that is one reason v1 is IOU.

---

## Sign in with Apple

The App ID is currently **explicit, no capabilities**. SIWA, HealthKit, and
Push all need Marc in Apple Developer — agents cannot do this.

**Verify the identity token on the server.** JWT from Apple, checked against
Apple’s JWKS:

- `iss` = `https://appleid.apple.com`
- `aud` = `com.fitfight.mvp`
- `exp` in the future
- `nonce` matches the one this attempt created

Then mint **our** session. Apple’s token lasts minutes. Do not send it on
every API call. Do not treat it as a user id in the database — store `sub`.

**Email and name arrive once**, on first consent. Persist immediately or they
are gone. Hide My Email is the common case; the relay address is not a
person, not stable forever, and not usable as a login. Never require a “real”
email. Display name in the app is a handle the user types, not Apple’s
`fullName`.

**Account deletion — App Store 5.1.1(v).** If we create accounts, we offer
deletion **in the app**, not “email Marc”. That screen is not designed; do
not invent it, but the API must exist before store review:

1. Authenticated `DELETE /me`.
2. Revoke the Apple token (`/auth/revoke`) so the user can SIWA-clean on a new install.
3. Wipe PII (handle, email, tokens, APNs, devices).
4. In live and finished fights they sat in: keep the **number**, label the
   person `Deleted user`. Other people still need a fair board.
5. Do not make deletion a soft flag that still serves their health history
   to anyone.

No second login provider in v1. Email/password is another dump, another
reset flow, another thing to delete.

---

## Sessions, devices, APNs

| Token | Where | Lifetime |
| --- | --- | --- |
| Apple identity token | RAM, then discarded | ~10 min |
| Access token | Memory / short Keychain | ~15 min |
| Refresh token | Keychain, this-device | weeks, **rotated** on use |
| APNs device token | Server device row | replaced whenever iOS hands a new one |
| Strava access/refresh | Keychain only, when Strava exists | per Strava |

Keychain: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
`kSecAttrSynchronizable = false`. Background wakes can happen before the next
unlock; tokens must still be readable. They must not roam via iCloud Keychain.
Not sqlite, not UserDefaults, not logs, not crash reports.

**Device table:** `device_id`, `user_id`, refresh-token **hash**, APNs
token, last seen. Logout this device deletes that row. “Log out all” is a
Settings sub-screen — not designed, do not invent; the API can still revoke
every refresh token for the user.

**APNs hygiene**

- Register on launch after SIWA.
- Unregister on logout.
- `BadDeviceToken` / `Unregistered` → delete the row. Do not keep spraying.
- Never log the token in full (public Actions logs, especially).
- Lock-screen text: no health numbers, no money (already on the poke
  backlog). Copy is “open FitFight”, not “Leo hit 12k”.

---

## Health data minimization

The phone’s job is: while open (or briefly woken), read HealthKit, **reduce**,
upload, show UI. The server’s job is: window, membership, settlement, push.

**What may leave the phone**

For each fight the user has joined, and only while it is live:

```
{ fight_id, metric, day, value, source: "healthkit" }
```

- `day` is a calendar date in the timezone **frozen on the fight at create** (one zone for every member).
- `value` is a daily total: step count, active minutes, or workout count.
- One row per (user, fight, day). Re-upload may replace that day until
  the fight settles; after settle, refuse.
- Optional: `sourceCite` as `healthKit` / `strava` — not bundle IDs, not
  workout times. Enough for You → Data sources after a reinstall.

The server **settles from these daily rows**, not from a workout list. Dedup
is finished before this payload exists.

**What must not leave**

Heart rate, sleep, routes / GPS, per-workout payloads, other metrics,
multi-year history, samples from fights the user is not in, weight (until
a dual-challenge actually ships and has its own review), HealthKit
`sourceRevision` bundle IDs (they name other apps on the phone), start/end
instants of individual workouts.

The You tab’s “8,240 steps today” can stay **on device** until that person
is in a steps fight. Do not “sync everything to the cloud so the profile
is snappy.”

HealthKit **write** access: do not request it. Usage strings and Privacy
Nutrition Labels are required the moment the entitlement lands. Health data
is not for ads, ranking strangers, or training models.

### Authorization denial is indistinguishable

Apple does not let us learn whether the user denied read access. A query
returns empty. That is the same shape as “rest day” and as “never opened
the app.”

Do **not**:

- Branch UI on `authorizationStatus(for:)` for reads (that API is about
  **write**).
- Treat 0 as cheating.
- Show “please enable Health” because a query was empty.

Do:

- After `requestAuthorization`, query. If we have never received a
  non-empty result **and** the user is in onboarding, show the designed
  permission copy (when that screen exists).
- **Upload rule** (same as sync): only enqueue a day if HealthKit returned a
  statistic, including a genuine 0. If the query **fails** or auth looks
  empty because we cannot tell, **skip that day**. Never overwrite a good
  server value with a compiled 0 that might mean “denied.”
- End-of-window nudge: “open so we can sync,” already on the backlog.
- **Settlement rule:** no successful upload in the window → **unscored**,
  buy-in refunded. Do not invent a forfeit-as-loss that looks like they
  scored 0. That punishes Don’t Allow and a dead phone the same way.

Background delivery is allowed later so a killed app can still upload
aggregates. Same payload rules. One compiling device in v1 (the iPhone
that granted HealthKit). A second device is replica-only.

---

## Strava (later)

Tokens: Keychain, PKCE, never git, never UserDefaults, never the server.
The phone pulls activities, maps them onto the same daily aggregate, uploads
that. Then a killed app cannot refresh Strava — same limitation as HealthKit,
which we already accepted.

If a ride is already in Apple Health via Strava’s HK write, **do not also
connect Strava** for that metric. That is the “counted twice” bug on the
Requests tab. Dedup happens **on the phone** (HealthKit is the merge plane)
**before** the daily total is uploaded. The server cannot un-double a single
number. Production uploads have SoD `healthKit` or (later) `strava`.
**`.manual` is fixture/preview only** — the API refuses it.

---

## Abuse

**Fake HealthKit data.** Other apps can write steps. We cannot make this
honest against a determined friend. Mitigations worth doing: prefer Apple
Watch samples when present; flag insane jumps for Marc to look at in the
audit log; no public matchmaking; no real-money pots. Do not build a
“anti-cheat ML” in v1.

**Invite spam.** Rate-limit pending invites per sender per day. Recipient
can ignore. Block is required before pokes (“discourage”) ship — Apple 1.2
will pull the app if we ship spicy messages without mute/block/report.

**Poke spam.** Cap length (~80 chars). Cooldown per pair (one per 30 min).
Server sends the push; the words are the friend’s. Filter garbage. Report
goes to Marc’s email, not a fake inbox.

**Scrape `public_code`.** With `FIGHT-742` (three digits) a script joins
every live fight in a second. With `FF-XXXX-XXXX` and a join-by-code
rate limit (per account and per IP), guessing is theatre. No list-codes
endpoint. Unused codes die when the fight starts; live codes die when it
ends. Constant-time compare is optional at 40 bits; rate limit is not.

---

## Fight join codes

The mock shows `FIGHT-742` in the nav of fight detail. That is fixture.
Production:

- **id:** UUID, never shown.
- **code:** 8 characters from Crockford base32 (`0-9`, `A-H`, `J-K`, `M-N`,
  `P-T`, `V-Z` — no `I/L/O/U`). Display grouped `FF-7K2Q-9M4R`.
- Generate on the server **when the create-fight command applies**, not on
  the phone. A local-only draft has no code (sync: other people cannot see
  it until apply). Reject client-supplied codes.
- Entropy is the access control for “I have the code, I can join.” Treat
  it like a password: log failed joins, lock after N.
- Domain type can stay a string (`FightCode`). Fixtures keep `FIGHT-742`.
  Production generator must not.

---

## RLS vs app-layer — pick app-layer

A friends app with health numbers and money-shaped IOUs cannot put a
Supabase URL + anon key in the iOS binary and hope RLS is perfect. One
missed `auth.uid()` on a new table dumps everyone’s steps. Cloud agents
will add tables. Settlement, cron, and APNs need a privileged worker
anyway.

```
iOS  --session-->  FitFight API  --service role-->  Postgres (private)
```

Every route authenticates, then checks membership (are you in this fight?).
If the host is Supabase, **do not** grant the client table access. RLS as
belt-and-suspenders on a restricted role is fine; RLS as the only lock is
not.

---

## Audit log

Append-only, server-side, not a user-facing screen in v1.

**Write:** login, logout, revoke, delete-me; fight create / join / leave /
settle; each **accepted** score upload (`user, fight, day, value, source`);
export; invites and pokes sent (for abuse, not to replay the spicy text
forever).

**Do not write:** raw HealthKit, access tokens, APNs, Strava tokens, email
bodies, poke copy after it has been handled.

Retention: accepted scores follow the fight (below). Audit rows 24 months,
then drop or hash. Marc can read it; a user sees their slice via export.

---

## Secrets, public repo, Actions

Already true and good: `.p8` / `.p12` / profiles in `.gitignore`; secret
**names** in [`shipping.md`](shipping.md); Fastlane writes the key to
`~/private_keys` and deletes it; TestFlight logs must not print tester
emails (the Fastfile already counts testers only).

**The sharp edge:** TestFlight runs on **every app push, including PR
branches**, with production secrets. A cloud agent (or anyone with push)
can change `fastlane/Fastfile` on a branch and exfiltrate
`APP_STORE_CONNECT_API_KEY`, or upload a hostile binary to Marc’s phone.
The key is **Admin**. The lane also **revokes every signing certificate**
on the team before archiving. A leaked Admin key is not “they shipped a
weird build”; it is “they can break signing for the whole team.”

**Pick:** Simulator + screenshots on PRs (no secrets). TestFlight on
`main` and the 18:00 UTC cron. Marc’s loop becomes: merge (or tell the
agent to merge) → wait for TestFlight → Update. That is slower than
today’s “every branch uploads.” It is the right trade for a **public**
repo and a signing key.

If that pick is refused, minimum:

- Replace the Admin ASC key with the least role that can upload and assign
  TestFlight groups.
- Stop revoking **all** certificates from the upload lane.
- GitHub Environments on the TestFlight job, secrets not available to
  `pull_request` from forks (already the default; we must not switch the
  TestFlight workflow to a form that grants forks secrets).
- CODEOWNERS / branch protection on `fastlane/**` and `.github/workflows/**`.
- Never `echo` secret values. Never bake them into the app bundle.

Keep the repo **public** (free macOS minutes). Do not put the API’s
service role in the iOS target. SIWA needs a **second** `.p8` (Apple
private key for the client secret) on the **server**, not in the app, not
in git. Marc adds it; agents do not see it.

Pin GitHub Actions by commit SHA when we next touch the workflows.

---

## What the server refuses from the client

Refuse even from a valid session:

- Final score, rank, pot, `projectedNet`, settlement outcome
- Anyone else’s uploads
- Health rows outside the fight window, or for a metric the fight is not using
- Future days; rewriting a day after the fight has settled
- A timezone change after create (frozen on the fight, or people shop DST)
- Join without a valid unused code or a real invite
- Client-chosen fight id / join code / Apple `sub`
- APNs token registration for a user that is not the session
- Strava tokens, raw HK samples, GPS
- Delete or export of another account
- Display handle that is already taken (409, do not confirm “exists” on
  login — SIWA does not need that)

Accept:

- Daily aggregates for **this** user, **their** live fights, unsynced days
- Handle / avatar (rate-limited)
- Join by code (rate-limited)
- This device’s APNs token
- Poke text after filters
- `POST /auth/apple` (identity token + nonce)
- `POST /auth/refresh`
- `DELETE /me`, `GET /me/export`

Auth routes sync.md does not list: `POST /auth/apple`, `DELETE /me`,
`GET /me/export`, `POST /auth/logout` (this device). Keep them off the
command-batch catch-all so a bug in `/commands` cannot delete an account.

---

## GDPR-ish: export, delete, retention

Controller: Marc Lamy. Legal basis: contract (run the fight) + consent
(HealthKit prompt). Privacy policy URL is required for the store the
moment HealthKit or accounts exist. Host Postgres in the **EU**.

**Export.** Authenticated JSON: profile, fights, *your* daily scores,
your audit slice. Share sheet or a file; not “we emailed you” (we have
no mail).

**Delete.** Same as 5.1.1(v) above. Other participants keep the numbers
and a tombstone name. That is how a finished board stays true.

**After a fight ends**

| Data | Keep |
| --- | --- |
| Daily series (the numbers that were shown) | 24 months, then drop |
| History row (name, dates, rank, net IOU) | Until the user deletes, or 24 months after last login if we ever prune ghosts |
| Raw upload payloads / retries | 90 days |
| Audit | 24 months |
| APNs / refresh tokens | Until logout or replace |
| Apple `sub` | Until `DELETE /me` |

Do not keep a shadow copy of HealthKit “in case they come back.”

---

## App Transport Security, pinning

ATS stays on. No `NSAllowsArbitraryLoads`. No cleartext exceptions.

**No certificate pinning in v1.** Pins break when the host rotates a
Let’s Encrypt leaf, cloud agents cannot coordinate a pin bump with DNS,
and a wrong pin bricks TestFlight. ATS + HTTPS is enough for a friends
IOU app. If we pin later: backup keys, never the leaf alone.

---

## What Marc has to do (agents cannot)

- App ID capabilities: Sign in with Apple, HealthKit, Push.
- Privacy policy hosted somewhere public.
- GitHub secrets: SIWA `.p8` (server), APNs key when push exists (server,
  never the iOS target), later whatever hosts the API. Names only in
  [`shipping.md`](shipping.md).
- Rotate the ASC key off **Admin** when convenient.
- Legal: IOU vs real money; company-sponsored credits on the backlog are
  a different review.
- TestFlight testers.

Talk to him only for those. Do not send him into Apple’s documentation
while he is on a phone loop — name the toggle, not the doc.

---

## What agents must not do

- Invent sign-in, HealthKit permission, delete-account, or devices UI.
- Put secrets in the repo, in `Info.plist`, or in chat.
- Trust the client for scores or membership.
- Send raw HealthKit off the device.
- Generate `FIGHT-` plus three digits.
- Add email/password “just for testing.”
- Add certificate pinning “for security.”
- Point the iOS app at Postgres / Supabase tables.
- Restore TestFlight-on-every-branch without an explicit Marc override of
  the pick above.

# Decisions we will still like in 6–9 months

Each pick is a default with a reason, not metaphysics. The regret pass is in [`reviews.md`](reviews.md). Open questions stay open at the bottom — do not fake precision.

## Do this

### 1. Server clock, phone sensor

The phone compiles HealthKit and submits intents. It never flips `live → settled` because `Date() > window_end`. Settlement is a job after grace.

### 2. One IANA timezone per fight, frozen at create

Shared “Day 3” and goal-mode days are a lie if everyone uses `Calendar.current`. Default = creator’s zone. Show it on create: “Days are Europe/Paris days.” Members do not get a private calendar at join.

### 3. Daily totals in that timezone, not a sample warehouse

Upload grain: `(fight_id, local_date, integer value, compiled_at, source fingerprint)`.
`HKStatisticsCollectionQuery` (or workout identity set) with a **calendar whose `timeZone` is the fight’s**. Never `Calendar.current`. Never sum `HKSampleQuery` rows.

Hourly UTC buckets are a later escape hatch if DST/travel bites. Do not start there.

### 4. Version the metric, freeze it on the fight

`metric_kind` + `rules_version` + `merge_policy_version` on `fights`. “Active minutes” means one documented definition for the life of that fight. Improving the definition later starts **new** fights, it does not rewrite old ones.

v1 mappings:

| Kind | Compile |
| --- | --- |
| `steps` | HK merged `stepCount` statistics |
| `active_minutes` | Logged-workout moving time, identity-deduped (**not** `appleExerciseTime` unioned with Strava) |
| `workouts` | Identity-resolved sessions with a minimum duration (10 minutes) |

See [`ingest.md`](ingest.md). Strava OAuth is **not** v1. If Strava already wrote the ride into Health, HealthKit is the merge plane — do not also add Strava.

### 5. Integer money, integer metrics, separate types

- Money: `Int64` cents + `currency`. Never `Double`. Never a unified “milli-everything”.
- Steps: `Int64` counts. Minutes: store **seconds**, display minutes. Workouts: counts.
- Remainder cents: largest remainder (Hamilton). Σ nets = 0.

### 6. IOU ledger, no rails

FitFight computes who owes whom. People pay each other. The moment we receive, hold, or send the pot we are in App Store 5.3.4 and money-transmitter land.

Copy: stake / IOU / “you settle yourselves”. Not bet, odds, jackpot, cash out. Invite-only. 18+. No rake.

Rename the undesigned You → **Payouts** row to **IOUs** when that screen is designed. Do not invent the screen now.

### 7. Pot is a query

`pot = sum(accepted memberships.buy_in)`. Invited people are not in the pot. That is the mock bug “pot still shows the old amount.”

### 8. Settlement is a pure function + one persisted result

```
preview  = settle(rules, pace(scores, now))   // live UI; never POST this
final    = settle(rules, frozen_scores)       // once, after grace
```

Client cannot submit `projectedNet`, rank, or SAFE. After freeze, late HealthKit is rejected (`409 window_frozen`), not applied.

**Goal mode (v1):** window total vs `daily_goal × length_days`. Live SAFE = on pace for that. Not seven independent daily hits (late Watch data would reverse “SAFE” screenshots).

### 9. Grace, then freeze, with an honest “never synced”

States: `scheduled → live → grace → settled` (or `cancelled`).

Grace: **until next noon in the fight timezone after `window_end`**, hard cap 48h. Visible push: “open so we can sync.” Not a fake score.

**No successful score upload in the window → unscored, buy-in refunded.** Do not treat “never opened / denied Health / query failed” as 0. Query **failure** must not upload zeros. A real authorized 0 is uploadable.

### 10. Typed IDs inside, public codes outside

UUID (or ulid) primary keys. Display `FF-XXXX-XXXX` (8 Crockford chars). Fixtures may keep `FIGHT-742`. Server generates codes. Never sequential.

Apple `sub` ≠ `user.id` ≠ handle ≠ fight code.

### 11. SIWA is the only credential, not the only way to point at a person

Handles + invite links. Hide My Email is normal. Account deletion API exists before store review even if the screen is undesigned.

### 12. GRDB replica + two outboxes, not a Postgres clone

Phone sqlite: `cache_*` (GET replica), `outbox_command`, `outbox_score_batch`, `local_*` watermarks. File excluded from iCloud backup. Tokens in Keychain, not sqlite.

JSON files cannot atomically write “optimistic fight + outbox row.” SwiftData invites CloudKit. Do not clone the server ERD onto the device.

### 13. REST + ETag + APNs invalidation

No websocket in v1. Push payload is a **scope**, never a score or a dollar amount.

### 14. App-layer authz, Postgres private

No Supabase URL + anon key in the binary. RLS as belt is fine; RLS as the lock is not.

### 15. Fixtures implement the same protocols

`FixtureFightStore` and `APIFightStore` both satisfy `FightRepository`. Screenshot CI (`FF_SHOOT=1`) never opens sqlite.

### 16. Leave hooks, don’t build Later

Nullable `series_id`, `shape` (`race` \| `dual` \| `sponsored_race`), `orgs` schema, `Block` table, poke tables unused. Dual is **not** `Fight.kind` plus a JSON blob of backers. Stickers mint a `JoinToken`, they do not hang `qr_url` on `fights`.

### 17. Minimize what leaves the phone

`{ fight_id, metric, day, value, source, compiled_at, fingerprint }`. No HR, GPS, routes, sleep, lifetime dump, other metrics. You-tab “steps today” can stay on-device until that person is in a steps fight.

### 18. One compiling device per user in v1

The iPhone that granted HealthKit. A second device is replica-only. Do not `max()` two compilers.

## Refuse (fashionable, will rot)

- Polymorphic `Fight.kind` + JSON for dual / sponsors / pokes / stickers
- On-device settlement, local midnight timers, Live Activity as score authority
- Storing kicker copy or mid-window `projectedNet` as columns
- IAP chips, crypto pots, mixing sponsor credits into the peer pot
- Summing Strava API duration with HK exercise minutes
- Email/password “for testing”
- Certificate pinning in v1
- TCA / SwiftData-as-architecture
- A Facebook-style friend graph
- Treating the Requests tab as fight mail
- Unified milli-units for money *and* steps *and* kg
- TestFlight-from-every-unreviewed-branch **and** an Admin `.p8` — see privacy doc; do not silently change Marc’s current loop in this PR

## Explicitly undecided (do not pick a fake default)

- Cheat policy for manual HealthKit entries (friends vs sticker-strangers)
- Pause-when-ill / leave / forfeit
- Dual miss: refund backers vs challenger pays (schema has the enum; product is Ask first)
- Whether action forfeits share the money ledger at all
- Handle rename / SIWA revoke recovery UX
- Retention after 24 months in practice
- Android / web join for stickers
- Exact `active_minutes` copy if we later offer an exercise-ring mode (would be a new `metric_kind`, not a silent swap)

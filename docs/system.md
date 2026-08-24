# FitFight system

Design, not built. Stack: native iOS + **Supabase** (Postgres, Auth, Storage, Realtime) + **Vercel** (ingest, crons, public web, APNs). No Edge Functions as the app server. No Stripe. DDL: [`system/schema.sql`](system/schema.sql).

The phone is a sensor and a screen. Postgres is the truth. Vercel is the only process that turns HealthKit/Strava into scores, IOUs, or pushes.

```
HealthKit / Strava ──► Vercel /api/v1/ingest/* ──► Postgres
                         │
                         ├─ samples (private, never Realtime)
                         ├─ fight_member_days (accepted members)
                         ├─ cron: settle, nudge
                         └─ APNs: "open so we can sync" (no numbers)
iPhone reads PostgREST + Realtime (anon key). Service role never leaves Vercel.
```

---

## Layers and SoD

SoD = **Source of Data** (and **Zod** on Vercel — same word on a phone). Every number from L1 up carries one: `healthkit | strava | scale | manual | derived | user | system`.

| Layer | What | Who writes | Stored? |
| --- | --- | --- | --- |
| L0 | Vendor payload on the ingest wire | iOS → Vercel | No JSONB blob |
| L1 | Canonical sample (one ride, not two) | Vercel | `metric_samples` |
| L2 | Daily total in a timezone | Vercel | Computed, not a table |
| L3 | That day clipped to a fight | Vercel | `fight_member_days` |
| L4 | Rank, today, net | iOS from L3 | Not a table |
| L5 | `"12 min behind Leo"` | iOS `FightCopy` | Never |

Units are integers: steps, **seconds** (show minutes), workout counts, **cents**. `user` = intent (name, buy-in). `manual` = typed sample. `derived` = any computed number.

Never in Postgres or as English on the wire: kickers, `payoutLine`, `"2h ago"`. Invited rank is `null`, never `0`.

Vercel `/api/v1` JSON is camelCase. PostgREST is snake_case. Zod is source of truth; Swift is hand-mirrored; same JSON fixtures in git.

---

## What lives where

| Thing | Home |
| --- | --- |
| Rows, RLS, Apple Sign In, avatars | Supabase |
| Live board while the app is open | Supabase Realtime on fight days / members / fights |
| Ingest, dedup, settle, Strava, APNs, crons | Vercel |
| Invite page `/i/{token}`, privacy, AASA | Vercel |
| UI, HealthKit read, SwiftData L4 cache | iOS |

Reads: PostgREST + RLS. Writes that matter (create, accept, ingest): Vercel. `user_id` is the JWT `sub`.

| Path | Job |
| --- | --- |
| `POST /api/v1/ingest/healthkit` | Evidence → samples → fight days |
| `POST /api/v1/ingest/strava/pull` + webhook | Server fetches Strava; phone never sends activities |
| `POST /api/v1/fights` + `…/accept` + `…/decline` | Trusted create/join |
| `POST /api/v1/invites/:token/claim` | Join via link (needs a session) |
| `POST /api/v1/devices` | APNs token |
| `GET /api/cron/settle` `nudge-sync` `outbox` | `CRON_SECRET`. First nudge at `ends_at`, second +2h if they have not synced. Settle at `ends_at + 6h` or when everyone synced. |

Vercel Pro. No `pg_cron` as well — that double-pays. Preview deploys have **no** prod service role. Two Supabase projects (staging, prod) before any real fight data. PR TestFlight → staging.

---

## Schema

Rules: UUID PKs. Fight `code` is a label, not a secret. No `pot` column. No copy columns. Clients cannot insert samples or days. RLS from `CREATE TABLE`.

**People.** `profiles` = `auth.users.id`. Handle 3–20, `^[a-z][a-z0-9._]{2,19}$`. Profile tz is only for You-tab “today.” Fight tz is frozen at create. `connection_secrets` is service-role only.

**Evidence.** `ingest_batches` (retry = no-op) → `metric_samples` (unique `user, source, external_id`). No GPS, HR, titles, vendor JSON. Canonical = `duplicate_of` and `excluded_reason` null.

**Game.** `fights` (frozen IANA tz, `starts_at` inclusive, `ends_at` exclusive, `settle_at = ends_at + 6h`, `recipe_version`). `fight_members` (`invited` is membership, not `fights.lifecycle`). `fight_member_days` is the scoreboard. `series_id` nullable now; no series table until recurring exists.

**Money.** Freeze writes `fight_settlements` + `fight_settlement_lines` (`net_cents` sums to 0) + pairwise `obligations`. Live pot = `buy_in_cents × accepted_count`.

**UGC / ops.** `requests` + votes. `boss_messages`. `user_blocks` / `user_reports` from day one. `invite_tokens`. `device_tokens` + `push_outbox`. `feature_flags`. `sync_runs`.

**RLS, short.** Invited people see names and fight metadata, **not** scores. Accepted members see daily totals for the fight metric, not raw samples or HK-vs-Strava mix. Handle search is an RPC, not `SELECT * FROM profiles`. Settlements: accepted only. Samples: no client SELECT.

---

## Sync

Two buttons: **refresh from server** (L4 GET) vs **refresh from source** (HealthKit/Strava → ingest). Pull-to-refresh is server first, then source. Never show a client-summed HK total as the fight score.

- Steps = HealthKit only. Workouts/minutes = one canonical session (Strava-in-Health is shadow; do not sum).
- Do not score `appleExerciseTime` in v1 (Watch-less zeros + doubles).
- Hourly step stats, per-workout objects. Cap 500 rows / 256 KB. `Idempotency-Key`. Advance the HK anchor only after 2xx.
- Fight days: `(ended_at AT TIME ZONE fight.timezone)::date`. Phone does not bucket with `Calendar.current`.
- SwiftData caches L4 only, CloudKit off. Background HK is speed, not correctness.
- After `ends_at`: settling. Ingest only for samples still inside the window. Freeze at `settle_at`. Late rows get `excluded_reason = 'late'` and do not move nets.
- Never-synced accepted member: score 0, can lose. Void only if **nobody** in the pot synced.

---

## Money

IOU ledger. FitFight does not collect, hold, or send money. Copy already on New: *“Scores sync automatically. You settle up at the end.”*

- Bragging: no obligations. Money: $5–$100. Action: winner/goal only, not proportional.
- One `settle()` for live (`net.phase = projected`) and freeze (`final`). Linear pace while live.
- Invited ∉ pot. Hamilton split. Action: unique last owes unique first; ties void the favour, not clone dinners.
- Goal: hit iff `score >= daily_goal × length_days`. Missers fund hitters. All hit or all miss → nets 0.
- Paid = payee confirm, later. Sponsor credits are a different book. Store listing: challenge/stake, not bet/casino.

The mock’s pot and +$7 goal maths are wrong. Implement this spec.

---

## Identity

Apple only. Capture name the first time Apple sends it. Handle via RPC. `@marc` is staff.

No friends table. Roster = people you have fought + handle search + share link. `FIGHT-XXXXXX` is a label. The link is `/i/{token}` (unguessable, preview only, no scores). Join needs a session.

Tombstone the profile (`deleted_at`). Hard-delete samples. FK is `ON DELETE RESTRICT` so Auth delete does not wipe other people’s history.

---

## Privacy

Anon key is in the IPA. RLS is the wall.

Accepted opponents see window total, today, and day-by-day **totals** (the designed card). Never raw workouts, GPS, HR, titles, or source mix. Invited-not-accepted see no scores.

HealthKit: prompt when joining a live fight, types for **that** metric only. No CloudKit. No health or money on the lock screen.

App Store 17+. Staked fights: 18+ when that screen exists. Report/block before pokes or request compose.

---

## iOS

Keep `FitFight/` at the repo root. Folders, not SPM: `Domain` (L4 + `FightCopy`), `Data/{Remote,Local,Fixtures}`, `Features`, `Health`. Protocols: `FightRepository`, `IngestClient`, `SessionStore`. Fixtures implement them so screenshots stay. Kill `AppModel` last. New stores `@Observable`. Ingest is user-level evidence, not `fightID` on the sample. Explicit `pbxproj` file list.

---

## Repo when we build it

```
FitFight/   apps/web/   packages/contracts/   supabase/migrations/
```

Do not move Xcode. pnpm is JS only. SQL migrations, expand/contract. Flags in Postgres (`ff.fights.live_backend`), fail closed for writes.

Build order: schema + RLS → ingest that no-ops settle → Apple Sign In + fixture protocols → live GET behind the flag → HealthKit → crons → invite page.

---

## Locked (change in a PR, not in passing)

Clients never write scores. SoD on every quantity. L5 never in the DB. Fight tz frozen. No stored pot. 6h grace. IOU only. No friends table. No Edge Functions as the backend. Preview has no prod service role. Zod + fixtures, not Swift codegen yet.

**Rejected:** client-side money, English in Postgres, Realtime on samples, averaging HK+Strava, void-if-they-never-open, friends/DMs/Venmo in v1, `AppModel` as the Health owner, `apps/ios` rename.

**Not v1 screens:** friends, chat, Stripe, pokes, social feed, dual challenge, sticker art, payouts. Schema may leave nullable hooks (`series_id`, `subject_user_id`, `sponsor_key`).

# FitFight system design

**Status:** design, not built. Ten independent reviews (schema, types, sync, money, identity, platform, iOS, privacy, repo, adversarial) were merged here. Conflicts are resolved in [decisions.md](decisions.md).

**Locked stack:** native iOS + **Supabase** (Postgres, Auth, Storage, Realtime) + **Vercel** (Next.js, ingest, crons, public web, APNs). No Firebase, no Rails, no home server, no Supabase Edge Functions as the app server.

Marc: read this file. The rest is for the agent that builds it.

---

## One sentence

The phone is a sensor and a screen. Postgres is the truth. Vercel is the only process allowed to turn HealthKit/Strava into scores, money, or pushes.

---

## Why this shape in 6–9 months

Today the app is a pixel-accurate mock (`AppModel` fixtures). The backlog already says real fights need a server: a killed iPhone will not settle a month, notice a missing upload, or send the “open so we can sync” nudge.

If we do these now, we will not have to unwind them later:

1. **Clients never write scores.** Stolen JWT + anon key is a REST client. RLS cannot be “the SwiftUI app is honest.”
2. **Every number has a Source of Data (SoD)** and a **layer**. Raw HealthKit is not a standing. A kicker string is not a column.
3. **Fight timezone is frozen at create.** “Today” is that zone, computed on the server.
4. **Money is cents, IOU-only, zero-sum, frozen with an algorithm version.** No Stripe, no IAP for pots, no stored `pot`.
5. **Supabase holds state. Vercel thinks.** Preview deploys never get the prod service role.
6. **The fight is the social graph.** No friends table, no DMs, no payments product.

---

## Picture

```
HealthKit / Strava / (later: scale)
        │  phone open, or briefly woken
        ▼
   Vercel  /api/v1/ingest/*     JWT in, service_role out
        │
        ▼
   Postgres
     L0/L1 metric_samples       private, never Realtime
                                (canonical rows; no vendor JSON blob)
     L2                         derived in Vercel, not a table
     L3 fight_member_days       accepted members may read totals
     L4                         iOS derives from L3 + Realtime
     L5 copy                    iOS only — never stored
        │
        ├─ RLS + Realtime ── iPhone (open app)
        ├─ Vercel cron ── settle, nudge, series roll
        └─ Vercel APNs ── "open so we can sync" (no numbers)
```

---

## Data layers (SoD)

SoD = **Source of Data**. Phone-transcribed “types with sod” — every quantity carries where it came from. On Vercel, **Zod** is the validator (likely the same word).

| Layer | Name | Who writes | SoD | Example |
| --- | --- | --- | --- | --- |
| L0 | Raw | Vercel ingest | `healthkit` / `strava` / `scale` / `manual` | HK workout UUID payload |
| L1 | Canonical | Vercel | winning origin, never `derived` | one ride, not two |
| L2 | Daily rollup | Vercel | `derived` | 8,240 steps on 2026-09-03 in fight TZ |
| L3 | Fight window | Vercel | `derived` | those days clipped to the fight |
| L4 | Standing | Vercel (view or RPC) | `derived` | rank, today, projected net cents |
| L5 | View model | iOS | n/a | `"12 min behind Leo"` |

**Never in Postgres:** `kickerEmphasis`, `listSubtitle`, `payoutLine`, `endedLabel`, `"2h ago"`.

**Never on the wire as English:** send `{ kind: "behind", amount: 12, unit: "minute", personId }` if the API helps the client; the sentence is iOS.

Details: [types.md](types.md).

---

## What lives where

| Thing | Home |
| --- | --- |
| Users, fights, samples, IOUs, votes | **Supabase Postgres** |
| Sign in with Apple | **Supabase Auth** (iOS `signInWithIdToken`) |
| Avatars | **Supabase Storage** |
| Live leaderboard while the app is open | **Supabase Realtime** on standings only |
| Ingest, settlement, dedup, Strava webhook, APNs, crons | **Vercel** |
| Invite / sticker landing, privacy policy, AASA | **Vercel** |
| UI, HealthKit read, local L4 cache | **iOS** |

iOS holds the **anon key** (public by design). The **service role** never leaves Vercel.

---

## Schema, short

Full DDL: [schema.sql](schema.sql). Narrative: [schema.md](schema.md).

**People:** `profiles` (handle, display name, IANA tz). Secrets for Strava live on `connection_secrets` (service role only).

**Evidence:** `ingest_batches` (idempotency) → `metric_samples` (append-only, no GPS/HR) → canonical + day tables.

**Game:** `fights` (frozen tz, metric, stake, window) + `fight_members` (invited/accepted) + `fight_member_days` (the scoreboard).

**Money:** do not store `pot`. At freeze: `fight_settlements` + `fight_settlement_lines` (`net_cents` sums to 0) + pairwise `obligations`.

**UGC:** `requests` + `request_votes`. `boss_messages` (one thread per user with Marc). `user_blocks` / `user_reports` from day one.

**Push:** `device_tokens` + `push_outbox`. Lock screen copy never contains health or money.

---

## Refresh and cache

Two different buttons:

| User action | Meaning |
| --- | --- |
| Pull-to-refresh on Fights | **Server first** (L4 cache → GET). Then HealthKit upload in the background. |
| You → Apple Health row | **Source:** read HK, POST ingest. |
| App become active | Both, debounced. Show cache immediately (stale-while-revalidate). |
| Fight ends | Server push: “Open so we can sync.” Grace (default **6 hours**), then freeze. |

Phone cache = SwiftData of **L4 fights/standings**, local-only, not iCloud. Never a Health dump.

Details: [sync.md](sync.md).

---

## Money, in one screen

Friend pots are **IOUs**. FitFight does not collect, hold, or send money. Apple Cash / Venmo happen outside. Copy already on New: *“Scores sync automatically. You settle up at the end.”*

- Invited people are **not** in the pot.
- `pot = buy_in_cents × accepted_count` (computed).
- Live `net.phase = projected` is the **same function** as freeze (`phase = final`), on current (or paced) scores. Do not store a live pot; freeze snapshots `pot_cents`.
- Freeze is a server transaction with `algorithm_version`. History never moves when we fix rounding.

Details: [settlement.md](settlement.md).

---

## 6–9 months from now

If this is followed, the repo looks like:

- `FitFight/` still at the root, still fixture-capable. `AppModel` is gone. Views talk to `FightRepository`. Design tab may be dead; `FightCopy` still formats L4.
- `supabase/migrations/` has real RLS. Nobody’s HealthKit dump is in Realtime.
- `apps/web` hosts `/privacy`, `/i/{token}`, AASA. Vercel crons settle and nudge.
- `packages/contracts` Zod + JSON fixtures. Swift Codable still hand-written, still passing the same fixtures.
- First real fights among Marc and friends: IOUs, not Stripe. Invite links, not a friends graph.
- Staging vs prod Supabase. PR TestFlight hits staging.
- Flags can kill uploads without an App Store wait.

What we will be glad we did: server-side scores, SoD layers, frozen fight TZ, cents + `algorithm_version`, no pot column, no Edge Functions split, no iCloud Health, report/block before pokes.

What would hurt: client-side money, English in Postgres, Realtime on samples, preview service role, averaging HK+Strava, a friends table “just in case.”

---

## What we are not building (yet)

Do not invent screens the inventory marks **Ask first**. Schema may leave **columns** (nullable `series_id`, `subject_user_id`, `sponsor_key`) so Later items are not a second product.

Not v1: friends graph, chat, Stripe, poke UI, social feed, dual-challenge UI, sticker art, company credits UI, in-app payouts.

---

## Files

| File | Topic |
| --- | --- |
| [decisions.md](decisions.md) | Locked calls + rejected alternatives |
| [architecture.md](architecture.md) | Service map, crons, secrets, envs |
| [schema.md](schema.md) / [schema.sql](schema.sql) | Postgres |
| [types.md](types.md) | Layers, SoD, Zod, Swift |
| [sync.md](sync.md) | Ingest, dedup, cache, grace |
| [settlement.md](settlement.md) | Stake maths, ledger |
| [identity.md](identity.md) | Apple, handles, invites |
| [privacy.md](privacy.md) | RLS, HealthKit, App Review |
| [ios.md](ios.md) | Client modules, kill `AppModel` |
| [repo.md](repo.md) | Monorepo around `FitFight/` |

Build order when an agent implements this: schema + RLS → Vercel ingest (no-op settle) → iOS Sign in with Apple + fixture protocols → live reads → HealthKit upload → crons → invite web. Flag `ff.fights.live_backend` so TestFlight can stay on fixtures until it is true.

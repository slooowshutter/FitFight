# Sync, ingest, cache

Phone = sensor. Server = scorekeeper. UI binds to L4.

## Two refreshes

| Phrase | Reads | Writes |
| --- | --- | --- |
| Refresh from **server** | L4 fights/standings | nothing |
| Refresh from **source** | HealthKit / Strava | evidence POST to Vercel |

Pull-to-refresh on Fights: **server first** (paint cache), then source in the background. You-tab source row: **that source only**. App become `.active`: both, debounce 60s.

Never show a client-summed HK total as the fight score.

## Ingest path

```
HK / Strava → POST /api/v1/ingest/* → L0 persist
  → canonicalize + dedup → L1
  → recompute civil days in fight TZ → L3
  → Realtime on standings
```

Auth: user JWT. `user_id` is `sub`. Service role only after verify.

### HealthKit POST `/api/v1/ingest/healthkit`

- `Idempotency-Key` = client run UUID
- Hourly **statistics** for steps, not every sample
- Workouts as objects (`uuid`, start, end, duration, source bundle)
- Deletes array
- Device hash, profile tz, `clockUnixMs` (skew > 5 min → flag, still accept)
- Cap 500 rows / 256 KB

Do not enable `appleExerciseTime` for v1 scoring (see [decisions.md](decisions.md)).

Success `200` with accepted/duplicate counts + `affectedFightIds`. `202` if recompute still running. `409` if key reused with different hash.

Advance the HK query anchor **only after 2xx**.

### Strava

Tokens live on Vercel/DB secrets. Phone never sends activities.

Webhook: verify signature, 200 immediately, enqueue fetch. Pull on app-open if last event is stale.

OAuth start/finish/delete on `/api/v1/sources/strava/*`.

## Dedup (the mock bug)

1. Unique `(user_id, source, external_id)`
2. If Strava connected, HK rows with `com.strava.*` bundle are **shadow** — do not session them
3. Fuzzy: same sport family, start ±3 min, duration within 10% → one canonical session, keep richer source, **do not sum**
4. **Steps = HealthKit only.** Never add Strava to steps
5. Active minutes v1 = sum of **canonical session** duration overlapping the window — not ring exercise time, not HK+Strava

Each fight stores `recipe_version` (column on `fights`). Old fights do not move when the recipe changes. Freeze also writes `algorithm_version` on the settlement row.

## Cursors

| Cursor | Where |
| --- | --- |
| `HKQueryAnchor` | On device, not iCloud |
| Hourly watermark `max(end)` | Device + server |
| Strava `after` | Server only |

Reinstall: backfill from `min(open fight start) - 24h`, not all-time Health. Server uniques drop replays.

Promise: **at-least-once HTTP, exactly-once rows**.

## Background HK

Entitlement `com.apple.developer.healthkit.background-delivery` when we add it. Observer in app launch. Always call the completion handler.

Background is **latency**, not correctness. App-open + 6h grace + nudge is the product even if Apple is slow on the entitlement.

Primary **iPhone** uploads. iPad does not.

## Time

Fight `timezone` frozen at create. Day buckets: `(ended_at AT TIME ZONE fight.timezone)::date`. Phone must not bucket with `Calendar.current`.

You-tab “steps today” uses **profile** tz. Fight tile “today” uses **fight** tz. Do not merge those into one table.

Travel does not move fight days.

## Grace

```
live → (ends_at) settling → (settle_at = ends_at+6h) settled
```

While settling: ingest allowed only for samples with `ended_at < ends_at`. UI: “Ended — waiting on last sync”, not final money.

Nudge at `ends_at`: **“Open FitFight so we can sync.”** No scores, no $. Second nudge +2h if that member has not synced. Early freeze if every accepted member synced after `ends_at`.

Phone must not lock scores at `ends_at`. Server freezes.

## Client cache

SwiftData (or SwiftData-shaped) **L4 only**: fights, standings, day grid, source status, `fetched_at`.

Not stored: raw HK, Strava JSON, tokens.

SWR: show cache → GET `?since=` → patch. Realtime invalidates that fight. Hard-expire live fights after 36h without GET (still show + stale chip).

Outbox: ingest batches on disk, Data Protection, excluded from backup, TTL 7 days. `URLSession` background upload.

No CloudKit. Offline UI is L4.

## Failure

| Case | Behaviour |
| --- | --- |
| Permission denied for a type | Do not zero the standing; mark source error |
| Split HK auth | That metric missing, others upload |
| Strava 401 | Reconnect on You; do not start counting Strava-written HK or doubles return |
| Clock skew | Reject samples `start > now+10m` |
| Never opened the app | Score 0, still in the pot if they accepted |

`sync_runs` stores counts and error codes, not titles or GPS.

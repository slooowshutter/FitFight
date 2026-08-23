# Review notes (overnight)

Eight specialist passes. This page is the **disagreements and the call**. The resolved law lives in the other files.

| Lens | Call we kept |
| --- | --- |
| HealthKit ingest | Phone compiles **daily** totals; fight IANA calendar, not `Calendar.current`. Statistics queries for steps. Workout **identity** merge. No `appleExerciseTime` ∪ Strava. Grace because Watch syncs late. Limited auth days are void, not 0. |
| Postgres | UUID ≠ `sub` ≠ handle ≠ public code. Integer cents. Pot is a view. Immutable settlement + `input_hash`. `series_id` / `shape` / roles from day one. Do not 3NF the phone. |
| Money / App Store | IOU among invite-only friends, no rails, no rake, 18+. Copy is stake/IOU not bet/odds. Goal mode = window total vs `daily × days`. Client cannot POST `projectedNet`. |
| Sync / cache | GRDB replica + two outboxes. SWR. Upload-then-refetch. Server clock. One compiler device. Query failure ≠ upload 0. |
| 6–9 month product | Bounded contexts stay split. Presentation fields never become columns. Dual / stickers / sponsors **attach beside** `Fight`. Requests ≠ invites. |
| Privacy / auth | SIWA only. Our sessions. App-layer authz. Daily totals only. Unguessable join codes. No pinning in v1. Account delete API before review. |
| Swift layers | SoD on samples/aggregates. Domain has no kickers. Presenter formats. Not TCA. Not SwiftData-as-architecture. Fixtures implement the same protocols. |
| Regret | Most “clean” picks stay, with an escape hatch. Fake precision we refused: 36.00h grace, milli-USD, CRDT scores, GraphQL, hexagon folders for Requests. |

## Fights we actually had to pick

**Daily buckets vs hourly UTC.** HealthKit review wanted hourly UTC so the server could rebucket. Sync law wanted daily civil totals (tiny payloads, matches the UI). **Call:** daily totals, compiled with the **fight** calendar. Hourly is the escape hatch if DST/travel bites. Revisit then, not now.

**Grace 6h vs next noon.** 6h is tight for a Watch left on the charger. **Call:** next noon in fight TZ, cap 48h.

**Timezone frozen at join vs at create.** Security draft said join (people shop DST). Shared Day 1 columns need one zone. **Call:** frozen **on the fight at create**. Show it in the create summary.

**GRDB vs JSON files.** JSON cannot atomically write optimistic fight + outbox. SwiftData invites CloudKit. **Call:** GRDB. Do not clone Postgres.

**Where settlement maths live.** Views today leak rank/pace/SAFE. **Call:** `SettlementEngine` in Domain; presenter owns copy; server freeze is the only ledger write.

**Strava.** Mock already contains the double-count bug. **Call:** not v1. When it lands, one source per metric; HK is the merge plane if Strava already wrote the workout.

**TestFlight every PR branch.** Security wants `main` + cron once secrets can ship a hostile binary. Current `shipping.md` uploads every app push (Marc’s loop). **Call:** document the risk, do **not** change the workflow in this docs PR.

**Active minutes definition.** Three different HK meanings. **Call:** v1 = identity-resolved **logged workouts’ duration** (min 10 min), versioned on the fight. Not exercise-ring ∪ Strava. If we later want ring minutes, that is a new `metric_kind`.

**Goal mode daily hits vs window total.** Independent daily hits explode with late HK. **Call:** window total vs `daily_goal × length`. Live SAFE = on pace for that.

**Never synced = 0.** Punishes Don’t Allow and looks like a rest day. **Call:** unscored + buy-in refunded.

## Minimum architecture that will not embarrass us

One API process, one Postgres, SIWA, APNs as invalidation. Server owns windows and freeze. Phone compiles daily integers with a fight-TZ statistics query, outbox, GRDB cache. Money is cents IOUs. Presentation is not a table. Later features point at `fight_id`; they do not fatten `Fight`.

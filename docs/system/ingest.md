# Ingest — HealthKit (and later Strava)

The phone is a **compiler of daily totals**. The server is a **judge** of those totals against a frozen window. Neither stores raw HealthKit samples.

## What we query

Register observer queries at launch, `enableBackgroundDelivery`, always call the observer completion handler. Test on a **device**. Simulator does not do background delivery. Steps are often capped at **hourly** wakes.

Dirty range: `HKAnchoredObjectQuery` to learn what changed; persist `HKQueryAnchor` **per type** in `local_hk_cursor` (excluded from backup). Rebuild quantities with **statistics** over the dirty civil days — do not increment from individual samples.

| Fight metric | HK | How |
| --- | --- | --- |
| steps | `stepCount` | `HKStatisticsCollectionQuery` `.cumulativeSum`, **not** `.separateBySource` for the scored number. Calendar = fight IANA tz. Interval = 1 civil day. |
| active_minutes v1 | `HKWorkout` | Identity-resolve sessions, sum duration, min 10 minutes. **Not** `appleExerciseTime` + workouts. **Not** Strava API + HK. |
| workouts | `HKWorkout` | Count of identity-resolved sessions, same min duration. |

Audit (optional): `.separateBySource` as a fingerprint. Never sum those slices.

**Do not send:** HR, GPS, routes, sleep, per-workout samples, lifetime history, standings, money.

## Fight calendar, not `Calendar.current`

```swift
var cal = Calendar(identifier: .gregorian)
cal.timeZone = TimeZone(identifier: fight.ianaTimeZone)!
```

## Authorization (iOS 18+)

Read denial is indistinguishable from “no samples.” Do not treat 0 as cheat.

- Limited window: days before `earliestAuthorizedSampleDate` are **void**, not 0.
- Query **failure**: skip the day; send **no** zeros.
- Authorized genuine 0: uploadable.

You-tab “steps today” can read HK on the fly. Do not persist it unless they are in a live/grace steps fight.

## Watch

v1: iPhone Health store only. Watch syncs into that store, often after midnight. That is why grace exists.

## Payload

```json
{
  "fight_id": "…",
  "compiled_at": "2026-08-23T21:10:00Z",
  "time_zone": "Europe/Paris",
  "source": "healthkit",
  "fingerprint": "hkstat:v1:stepCount",
  "days": [{ "day": "2026-08-22", "value": 11002 }]
}
```

Integer native units. Idempotency: `scores:{user}:{fight}:{from}:{to}:{sha256}`. Newer `compiled_at` overwrites until freeze. One HTTP per fight, atomic.

## Strava (not v1)

PKCE, Keychain, phone fetches, same daily upload. Server never stores Strava tokens. If the activity is already in Health, **do not also connect Strava for that metric.** One source per metric per fight. HealthKit is the default merge plane.

## Workout identity

HK does **not** statistics-dedupe workouts. Link: start ±90s, duration within 10% or 2 min, sport family. One interval. Never sum Watch + Strava-via-HK.

## Server apply

Member of fight, `live` or `grace`, metric matches, days inside window, no future fight-tz day. Upsert `health.day_quantities` if `compiled_at` newer. Copy into `fights.score_days`. After freeze: `409`. Never accept `projectedNet` or rank.

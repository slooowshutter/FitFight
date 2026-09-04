# Data sources FitFight can collect

Catalog date: **4 September 2026**. This is the inventory of sources, not an implementation plan and not a Fight-scoring change. Vendor terms and HealthKit exports change; re-check first-party docs before shipping an adapter. Field-level HealthKit behavior for each vendor lives in [`sports-health-integrations.md`](sports-health-integrations.md).

## What this is answering

Before mapping Metrics onto sports and letting those Fights run, FitFight needs a real activity store. Today the app only asks Apple Health for merged **Steps** over exact Fight windows. That is enough for the current product. It is not enough to later say “this was a run,” “this was a WHOOP workout,” or “this came from a Fitbit.”

The catalog below is every source that is worth naming. Most of them do **not** need their own OAuth app. They already land in Apple Health if the person turns the export on.

## The model — three layers, not 40 apps

```text
Device or recording app          Hub on the phone              FitFight
Apple Watch, Garmin, WHOOP,     Apple Health / HealthKit  -->  one adapter
Oura, Fitbit, Strava, NRC, …         (iOS)
                                 Health Connect later          (Android)
```

1. **Hub.** One permission sheet. FitFight reads typed HealthKit objects. This is the iPhone path.
2. **Direct cloud API.** Only when the hub cannot hold the number (WHOOP Recovery, Oura Readiness, Garmin Body Battery) or when the phone never sees the data.
3. **Aggregator (Terra, Junction/Vital, ROOK).** One vendor sitting between FitFight and 100+ APIs. Do not adopt for v1. Extra processor, cost, Apple privacy label, and the aggregator still cannot waive Strava/WHOOP display terms.

Apple Watch is **not** a separate integration. It writes into Apple Health. Same for the iPhone pedometer. FitFight already reads that hub; it just only asks for Steps.

## What FitFight already collects

| Source | What is stored | Used for |
| --- | --- | --- |
| Apple Health merged Steps | Exact Fight-window cumulative total + relevant daily chart buckets | Standings and the Fight chart |

Not collected today: workouts, sport type, distance, energy, heart rate, sleep, per-source totals, device names, GPS routes, or any vendor OAuth payload.

## First collection slice — before sport mapping

Do this next, still **private to the signed-in User**, still **not** a Fight score:

| HealthKit type | Why collect it now |
| --- | --- |
| `HKWorkout` | Apple already labeled the sport (`HKWorkoutActivityType`: running, cycling, swimming, strength, yoga, hiking, rowing, tennis, pickleball, … ~80 types). That is the sport map. Do not invent a parallel taxonomy. |
| Workout duration + statistics | Minutes, distance, active energy attached to that workout. Needed later for Active Minutes / Workout Count. |
| `distanceWalkingRunning`, `distanceCycling`, `distanceSwimming` | Daily movement that is not always a named workout. |
| `activeEnergyBurned`, `appleExerciseTime` | Useful later Measures; cheap to keep with the same consent sheet. |

Still do **not** score Fights from this. Steps remains the only production Metric until the backlog says otherwise.

Gates before that slice ships: one Collection consent that names workouts (not “all health data”), updated HealthKit usage strings, App Privacy labels, retention and account-deletion coverage, no GPS routes unless a shipped feature needs them.

## Hubs

| Hub | Platform | What it is | FitFight |
| --- | --- | --- | --- |
| **Apple Health / HealthKit** | iOS | On-device typed store. No public Apple Health REST API. | **Use now.** Expand types per the slice above. |
| **Google Health API** | Cloud | Replaces the Fitbit Web API (shutdown **September 2026**). Fitbit + Pixel Watch (and other Google Health connections). | Direct API only if Fitbit users must sync without opening FitFight, or if HealthKit export is off. |
| **Health Connect** | Android | On-device broker, same role as HealthKit. | Adapter seam only. Build with Android. |
| **Samsung Health** | Android | Own SDK, partner registration. | No iOS path. |

## Wearables and rings — HealthKit first

These are hardware. On iPhone they almost always arrive through the companion app → Apple Health. “Connect WHOOP in FitFight” is a later product surface, not a requirement to start collecting.

| Source | Typical hardware | Through Apple Health (if the person enables export) | Direct API worth it only for |
| --- | --- | --- | --- |
| **Apple Watch / iPhone** | Watch, phone | Native. Steps, workouts, rings, HR, sleep, routes. | Never a separate cloud API. |
| **WHOOP** | Band | Workouts, energy, HR, sleep, optional steps. **Not** Recovery, Strain, or WHOOP HRV (RMSSD). | Recovery / Strain / RMSSD, after written social-display approval. |
| **Oura** | Ring | Steps, HR, sleep, workouts/routes, energy, respiration. **Not** Readiness. | Readiness / Oura scores / deeper ring data. |
| **Ultrahuman** | Ring | HRV, HR, energy; glucose if they use M1. | Only if a named Ultrahuman score is a product Metric. |
| **Garmin** | Watch | Steps, energy, floors, selected HR, sleep, workouts. No GPS routes. Garmin Connect often needs to be opened to push. | Body Battery, stress, FIT/GPX detail. Enterprise program. |
| **Fitbit / Pixel Watch** | Band, Pixel Watch | **Yes as of Google Health iOS 5.05 (3 Aug 2026):** two-way Apple Health, including exercise, steps, sleep, vitals. [Google Help](https://support.google.com/googlehealth/answer/17037331?hl=en), [9to5Mac](https://9to5mac.com/2026/08/03/google-health-adds-two-way-apple-health-syncing-on-iphone/) | Google Health API if the phone path is not enough. Do not build the dying Fitbit Web API. |
| **Polar** | Watch | Workout energy/HR, sleep timing, steps, weight, workout type/distance. Not continuous HR. | Exercise streams, cardio load. |
| **COROS** | Watch | Distance, HR, sleep, steps. Confirm `HKWorkout` on-device. | Partner API if HealthKit is thin. |
| **Suunto** | Watch | Verify export on-device; first-party field list is thin. | Partner Cloud API, gated. |
| **Amazfit / Zepp** | Watch, Helio strap | Zepp writes steps, sleep, HR, workouts, SpO2. HRV only on some devices. | Not a first-wave direct API. |
| **Xiaomi / Zepp Life** | Band | Older Mi Fit path: steps, sleep, weight. Lighter than Zepp. | Skip unless a named user needs it. |
| **Withings** | Scale, watch, sleep mat | Weight/composition, BP, sleep, steps, HR. | Richer composition / clinical history. |
| **Eight Sleep** | Mattress | Sleep stages, HR, HRV, respiratory rate. No daytime steps. | Not needed if HealthKit sleep is enough. |
| **Wahoo** | Bike computer | Workouts via the Wahoo iOS app. | Cloud API is partner-gated; prefer HealthKit workouts. |
| **Huawei Health** | Watch | No useful official iPhone HealthKit path. | Skip on iOS. Special process even for aggregators. |

Samsung Galaxy Watch is Health Connect / Samsung Health, not Apple Health.

## Recording and training apps — HealthKit copy of the activity

These are not wearables. They create `HKWorkout` (and sometimes routes) when the person records in that app. Collecting Apple Health workouts already picks them up. Do not add a second copy via the vendor API unless HealthKit is empty for that app.

| App | Apple Health | Direct API |
| --- | --- | --- |
| **Strava** | Writes Strava-recorded type, time, distance, calories, route. Does **not** re-export activities it imported from Garmin/Zwift. | **Blocked** for shared Fights under 2026 Strava API Policy unless Strava gives written approval. Seven-day cache. Display only to the authenticated athlete. |
| **Nike Run Club** | Completed runs: workout, distance, energy, HR. | No public consumer API worth building. |
| **Peloton** | Documented HealthKit connectivity; verify fields on-device. | No public consumer workout API. Do not scrape. |
| **TrainingPeaks** | Reads/writes Apple Health workouts. | Partner; not needed to collect the HealthKit copy. |
| **Concept2 ErgData** | Usually via Logbook → Strava/Garmin/TrainingPeaks, then maybe HealthKit. | No FitFight-direct path. |
| **Zwift** | Official third-party list does not include Apple Health. Strava will not reliably re-export imported Zwift rides. | No dependable path without file import. |
| **MyFitnessPal** | Meals/nutrients/weight; limited exercise import. | API closed to new apps. |
| **Komoot, Relive, AllTrails, Runkeeper, Adidas Running** | Often write a workout/route if the user enables Health. | Treat as HealthKit workouts. Do not build each API. |
| **Apple Fitness+ / Workout app** | Native HealthKit workouts. | None. |

## Direct APIs that are actually different from HealthKit

Build one of these only when a shipped Metric cannot be read from Apple Health:

| Provider | Missing from HealthKit | Extra cost |
| --- | --- | --- |
| WHOOP | Recovery, Strain, RMSSD | OAuth, webhooks, social-display terms, deletion |
| Oura | Readiness and Oura scores | Production user-cap approval; membership required for Gen3+ API |
| Garmin | Body Battery, stress, full FIT | Business program approval |
| Google Health | Server-side Fitbit/Pixel without the iPhone open | Google OAuth verification; Fitbit Web API dies Sep 2026 |
| Polar | Streams, cardio load | AccessLink / API v4 |
| Strava | Full activity streams | **Do not use for leaderboards** without written approval |

## Sports Apple already named

Sport mapping should start from `HKWorkout.workoutActivityType`, not a handmade list of vendor sports. Apple’s current types include:

- **Cardio / endurance:** walking, running, cycling, swimming, hiking, rowing, elliptical, jump rope, stairs, HIIT, mixed cardio, wheelchair walk/run, hand cycling, swim-bike-run
- **Strength / studio:** functional and traditional strength, core, cross training, yoga, pilates, barre, cardio dance, flexibility, cooldown
- **Racket:** tennis, pickleball, badminton, squash, table tennis, racquetball
- **Team / field:** soccer, basketball, rugby, hockey, volleyball, and the other team constants
- **Outdoor / water / snow:** climbing, golf, paddle sports, surfing, skiing, snowboarding, skating
- **Combat:** boxing, kickboxing, martial arts, wrestling, tai chi
- **Other:** `other`, plus deprecated dance aliases

A later FitFight sport picker should be a **reviewed subset** of this enum (and a rule for `other`), not a new ontology. Vendor-only labels (WHOOP “activity”, Strava sport string) map into this enum at the adapter, never in scoring.

## What not to collect yet

| Data | Why wait |
| --- | --- |
| GPS / `HKWorkoutRoute` | Location is a different privacy class and App Privacy type. |
| Clinical: ECG, glucose, blood pressure as a Fight metric | Medical-adjacent; Dual-challenge weight is the only backlog hook, and even that is Later. |
| Nutrition, cycle tracking, mindfulness | Not a Fight Measure. |
| Raw overlapping step samples from every contributing app | Apple’s merged statistic is the Steps source of truth. Summing sources double-counts. |
| Everything HealthKit offers “just in case” | Apple and FitFight policy: collect for a named shipped behavior, after consent. |

## Aggregators (Terra, Junction, ROOK, Validic)

They advertise 150–500 sources. They still:

- Need the iOS SDK for Apple Health / Health Connect (no cloud shortcut around HealthKit).
- Put a third party in the health-data path (App Privacy, DPA, deletion).
- Cannot make Strava’s API Policy allow a shared leaderboard.
- Charge per connection.

FitFight already has the iPhone hub. Prefer HealthKit, then first-party APIs for named gaps. Revisit an aggregator only if Android + many cloud providers ship together and Marc accepts the processor.

## Honest limits that collection will not fix

- A source is visible only if the vendor wrote that HealthKit type **and** the person allowed FitFight to read it. Empty looks the same as denied.
- Garmin and similar may not write until their companion app is opened.
- Two sources for the same run (Watch + Strava) are two HealthKit objects. Scoring must pick **one** Data source per member per Metric per Fight. Never add them.
- Freshness is product data. HealthKit is not a server API; the phone must run.

## Recommended order

1. Keep shipping Steps from Apple Health aggregates.
2. Collect private `HKWorkout` + the activity quantities in the first-slice table. Store sport type from Apple. Do not put it on a Fight yet.
3. After real workouts exist for the people who will test sports Fights, define Measure × Score for workouts / active minutes from that store.
4. Add a direct WHOOP or Oura adapter only for a named proprietary Metric, with written sharing terms.
5. Health Connect / Samsung only with Android.
6. Strava direct API only after written approval; until then Strava is “whatever it already wrote into Apple Health.”

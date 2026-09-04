# Data sources

Last updated **2 Sep 2026**. This is the living catalog of every fitness source FitFight might use, plus the Apple Health bulk-ingest design.

Vendor field lists and terms change. Re-check first-party docs before building an adapter. Deeper vendor notes: [`sports-health-integrations.md`](sports-health-integrations.md). Architecture: [`system-design.md`](../system-design.md) §8. What to build next: [`backlog.md`](../backlog.md).

**Do not implement this file.** It is the map. Agents build one numbered backlog item at a time.

## What shipping 1.0 does today

The App Store / production Fight is **Steps × highest total**. The phone sends Apple's **merged** cumulative Steps for each exact Fight window, plus merged daily buckets for chart days. No raw samples, no TUS archive, no WHOOP/Fitbit/Garmin OAuth.

That cut was deliberate: a full historical dump of overlapping raw step samples was often **>100MB** uncompressed, and summing those samples is the wrong way to score Steps.

## Collect vs score

Marc wants more data so he and friends can invent metrics. That is **collection**, not a new scored Fight.

| Layer | Rule |
| --- | --- |
| **Scoring (production 1.0)** | Still exact-window Apple Health Steps. Do not change live Fight totals because a new type arrived. |
| **Collection (staging first)** | Pull the richest **useful** representation we can store, consent, delete, and afford. Marc + friends try it on TestFlight. |
| **A new Metric** | Needs a unit, window, merge rule, freeze version, and a Changelog. Freeze historical results before that ships. |

Never add Apple Health steps to Garmin steps, or a WHOOP workout to its Strava copy. One scoring source per member, per Metric, per Fight.

## Why raw Apple Health was huge

HealthKit can store one `HKQuantitySample` every few minutes for years, from **several overlapping writers** (Watch, iPhone, Garmin Connect, WHOOP, Google Health). Uncompressed NDJSON with UUID + source + device + metadata per sample is what blew past 100MB.

**Maximum useful data is not a second copy of the Health database.**

- For cumulative numbers (steps, distance, energy, exercise time): Apple's **statistics** already merge overlapping sources. Daily (and later hourly) buckets for years are kilobytes to low megabytes, not 100MB.
- For workouts and sleep: the workout/session objects are small. Do not also store every associated heart-rate sample unless a metric needs the stream.
- Heart-rate samples, GPS routes, and raw steps are the size bombs. Collect them only when a named metric cannot be built from statistics/workouts.

### Ingest design (Apple Health v2)

Use this when the backlog item **Apple Health ingest v2 (staging)** is the current work. Do not restore the old one-blob raw pipeline blindly.

1. **Ask only the HealthKit types this slice stores.** Each new type needs an Info.plist usage string, privacy nutrition-label update, consent copy, and deletion coverage.
2. **Prefer `HKStatisticsCollectionQuery` / `HKStatisticsQuery` and `HKWorkout.allStatistics`.** Exact Fight-window Steps stay the same query they are today.
3. **If samples are required:** gzip NDJSON, **chunk by calendar day and type**, resume with TUS, SHA-256 the object, commit, then delete Storage. Never one 100MB JSON.
4. **First backfill is incremental after that.** `HKAnchoredObjectQuery` + a saved anchor; do not re-send history every open.
5. **Hard cap.** If a chunk is still too large, fail that type and keep statistics. Do not OOM the phone or Vercel.
6. **Compress on device** (gzip). No pretty-printed JSON.
7. **Score from the statistic meant for that metric**, never by summing overlapping raw samples or `separateBySource` totals.
8. **Deletions.** If samples are stored, persist deletion UUIDs from the anchored query and reconcile. Statistics-only types can be recomputed from Apple on the next sync.
9. **Staging first.** Do not put a new HealthKit type into the already-submitted App Store 1.0 binary unless Marc asks to resubmit.

### What to collect first on staging (Apple, no extra OAuth)

These are enough to invent most “did they move / sleep / work out” metrics. All of them can come from HealthKit **without** WHOOP or Garmin developer apps, if the user enabled that app’s Apple Health export.

| Type | How | Size | Why |
| --- | --- | --- | --- |
| Steps | Merged exact-window + daily (already shipping) | Tiny | Current Fight |
| Distance, flights, active/basal energy, exercise time, stand hours | Daily (then hourly if needed) statistics | Small | Active-minutes-style metrics |
| Workouts | `HKWorkout` + `allStatistics` (type, duration, energy, distance, avg HR if Apple has it) | Small | Workout count, duration, sport |
| Sleep | `HKCategorySample` sleep analysis intervals | Small–medium | Sleep fights; do not duplicate every HR sample in the night |
| Resting HR, walking HR average | Daily statistics | Small | Recovery-ish without WHOOP |
| Body mass | Sparse samples | Tiny | Dual-challenge / scale later |
| Mindful minutes | Daily statistic if present | Tiny | Optional |

**Do not collect in the first expansion** unless a metric is named: raw step samples, continuous heart rate, HRV sample streams, workout GPS routes, ECG, audio exposure, clinical records, audio/voice.

Heart rate variability: Apple's HealthKit type is **SDNN**. WHOOP's number is **RMSSD**. They are not interchangeable. If Marc wants WHOOP Recovery / Strain / RMSSD, that is a **direct WHOOP API**, not more HealthKit.

## How to read the catalog

| Path | Meaning |
| --- | --- |
| **HealthKit** | User turns on that app’s Apple Health export, then grants FitFight read. FitFight never talks to the vendor. |
| **Direct API** | FitFight OAuth + backend adapter. Needs Marc to create a developer app, secrets, terms review, deletion, and usually permission to show a derived score to Fight members. |
| **Blocked / none** | Do not build. Terms, no public API, or no iOS path. |

HealthKit is empty both when the user denied read access and when there is no data. Apple does not tell us which. [Authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)

Garmin (and some others) only push to Apple Health after the companion app is opened. Show freshness; do not claim “automatic.”

---

## Catalog — hubs

| Source | HealthKit | Direct API | FitFight |
| --- | --- | --- | --- |
| **Apple Health / Watch / Fitness+** | Native. Workouts from the Workout app and Fitness+ land as `HKWorkout`. | No public Apple Health REST API. | **Use now.** Expand types on staging per ingest design above. |
| **Google Health Connect** | Android only | On-device broker on Android | **No iOS path.** Revisit only if Android ships. |

## Catalog — wearables and watches

| Source | Typical HealthKit (if user exports) | Direct API | Vendor-only (needs API) | FitFight |
| --- | --- | --- | --- | --- |
| **WHOOP** | Workouts, active energy, HR, sleep, RHR, respiratory rate, SpO2, optional steps. **Not** Recovery, Strain, or WHOOP HRV (RMSSD). | Public OAuth 2: recovery, cycles/strain, sleep, workouts, webhooks. [API](https://developer.whoop.com/api/) | Recovery, Strain, RMSSD | HealthKit first for movement/sleep. **Direct API is the first vendor adapter** when Marc creates a WHOOP app. |
| **Garmin** | Steps, energy, sleep, selected HR, weight/body, floors, distance, workouts. **No routes.** Companion often must be foregrounded. | Enterprise Connect program, approval. Health + Activity (FIT) APIs. [Program](https://developer.garmin.com/gc-developer-program/) | Body Battery, stress, FIT streams, routes | HealthKit first. Direct API only after approval, for Body Battery / rich activities. |
| **Oura** | Steps, HR, sleep/stages, workouts/routes, energy, weight, respiration, mindful minutes | Public OAuth 2; production approval after a user cap. Membership may be required. [v2](https://cloud.ouraring.com/v2/docs) | Readiness, Oura scores, temperature/stress context | HealthKit first. Direct API for Readiness. |
| **Google Health / Fitbit / Pixel Watch** | **As of Google Health iOS 5.05 (~2 Aug 2026)** the app can **write** exercise, sleep, vitals, steps (and more) to Apple Health. HRV still does not cross. Google’s Help Center can lag the App Store notes — verify on device. | Google Health API replaces Fitbit Web API (Fitbit Web API shutdown scheduled Sep 2026). OAuth verification. [About](https://developers.google.com/health/about) | Some Fitbit/Google scores and HRV | **Prefer HealthKit** now that write exists. Direct Google Health API only if a metric is missing after on-device check. |
| **Polar** | One-way Polar → Health: workout energy/HR, sleep timing, steps, weight, workout summary. Not continuous HR. | AccessLink + newer API v4 | Streams, cardio load, continuous HR | HealthKit first. |
| **COROS** | Distance, HR, sleep, steps, swim; confirm `HKWorkout` on device (docs conflict). | Partner API, apply. Schema is thin. | Training detail | HealthKit first; verify workouts on a real phone. |
| **Suunto** | Unclear field list — verify on device. | Cloud API, partner approval, FIT workouts; webhooks mention sleep/24h activity. | Gated schemas | Verify Health export before any API. |
| **Amazfit / Zepp** | Often steps/sleep/workouts if the user enables Health | Partner programs vary | Proprietary scores | HealthKit only unless a named gap appears. |
| **Ultrahuman** | Ring metrics the app writes to Health | Check current partner API | Glucose/recovery scores if not in Health | HealthKit first. |
| **Eight Sleep** | Sleep the app writes to Health | Partner/API if offered | Pod-only scores | HealthKit sleep if present. |
| **Samsung Galaxy Watch** | **No official Apple Health bridge** | Samsung Health Data SDK (Android) | Energy Score etc. | **Android later.** Not an iOS connector. |
| **Huawei / Xiaomi / other Android bands** | Spotty or none on iPhone | Vendor Android APIs | — | Ignore until Android or a proven HealthKit write. |

## Catalog — cycling, indoor, gym

| Source | HealthKit | Direct API | FitFight |
| --- | --- | --- | --- |
| **Wahoo** | iOS app can share activity; fields vary by product | Cloud API, approval: workouts, zones, routes | HealthKit workouts first |
| **Peloton** | Documented Health read/write; no field-level schema | **No public consumer workout API.** Do not scrape private endpoints. | HealthKit workouts only |
| **Zwift** | **Not** on Zwift’s official third-party list. Strava will not reliably re-export imported Zwift rides to Health. | No public user API; FIT export is a file feature | **No dependable connector.** File import would be a separate Later item. |
| **Concept2 ErgData** | Typically writes indoor-row/ski workouts to Health | Concept2 logbook APIs exist for some partners | HealthKit workouts first |
| **TrainerRoad / Hydrow / similar** | If the app writes `HKWorkout`, it shows up for free | Often no public API | HealthKit only |
| **Apple Workout / Fitness+** | Native `HKWorkout` | None | Already in the Apple hub |

## Catalog — training, nutrition, booking

| Source | HealthKit | Direct API | FitFight |
| --- | --- | --- | --- |
| **Strava** | Recorded-in-Strava activity type, time, distance, calories. Activities **imported into** Strava (Garmin/Zwift) are **not** re-exported. Strava imports only Apple Workout app workouts, not every third-party Health workout. | OAuth activity API. **2026 policy:** display only to the authenticated user, 7-day cache, tight storage rules. [API policy](https://www.strava.com/legal/api_policy) | HealthKit copy may feed Apple’s merged totals. **Do not use the Strava API for shared Fight standings** without written Strava approval. |
| **TrainingPeaks** | If the companion writes Health | Partner API, approval | Only if a coach-plan metric is a product; not for 1.0 |
| **Nike Run Club / Nike Training** | Often workouts to Health | No useful public athlete API for fights | HealthKit workouts |
| **MyFitnessPal** | Meal summaries / nutrients / weight write; same-day exercise/sleep import; little history | **Not accepting** API access requests | Nutrition/weight via Health only |
| **ClassPass** | None found | Merchant booking/attendance, not heart rate or steps | **Not a health source.** Attendance ≠ measured exercise. |
| **Komoot / Ride with GPS** | Sometimes workouts | Partner APIs | HealthKit if present; not a hub |

## Catalog — medical / clinical (parked)

Dexcom and other CGM, ECG strips, medications, clinical records: extra App Store and privacy cost. **Do not collect** until Marc explicitly asks. Fitness metrics do not need them.

---

## Adapter order (when we leave HealthKit-only)

Do not wire every OAuth at once. Each adapter is its own PR: secrets, scopes, webhooks, deletion, Fight-member display terms, tests.

1. **Apple Health ingest v2 (staging)** — this catalog’s ingest design. Marc + friends. No new Fight metric yet.
2. **Freeze historical results** — already Urgent; required before any new scored Metric.
3. **First extra Metric from Apple data only** (example: workout count or sleep). Changelog + scoring spec.
4. **WHOOP direct** — Recovery / Strain / RMSSD. Marc creates the WHOOP developer app. Confirm WHOOP allows a derived Fight score to named participants.
5. **Oura Readiness** or **Garmin Body Battery** — whichever Marc actually wears and can get approved.
6. **Google Health API** — only after a phone check that HealthKit is missing a metric we need.
7. **Polar / COROS / Withings** — only for remaining vendor-only gaps.
8. **Android Health Connect** — only if an Android app is in scope.
9. **Strava direct** — blocked until written approval.

Withings is HealthKit-first for weight; direct API is for clinical/composition history, not a near-term Fight.

## What only Marc can do

Agents cannot create vendor developer apps. When an adapter reaches Now:

- WHOOP / Oura / Google / Polar: create the app, OAuth redirect, GitHub/Vercel secrets (never commit them).
- Garmin / Suunto / Wahoo / COROS: apply to the enterprise/partner program and wait.
- Strava: written permission for shared standings, or do not build.
- Legal: privacy policy must list every new HealthKit type and every vendor.
- Apple: resubmit only if a new Health type ships in the App Store binary.

## Related files

- [`sports-health-integrations.md`](sports-health-integrations.md) — 29 Aug vendor research (Fitbit/Google corrected 2 Sep).
- [`system-design.md`](../system-design.md) §8 — adapter contract, one source per score, Strava block.
- [`backlog.md`](../backlog.md) — ordered work. This catalog is not permission to implement adapters.

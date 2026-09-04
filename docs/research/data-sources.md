# Data sources FitFight can collect

Catalog date: **4 September 2026**. Product decision: **pull from vendor APIs directly**, because most people never turn on Apple Health export. Apple Health remains the only path for Apple Watch and iPhone. This is still collection-only: private to the signed-in User, not Fight scoring. Field-level vendor notes: [`sports-health-integrations.md`](sports-health-integrations.md).

## Why not “just Apple Health”

Those watches and apps *can* write into Apple Health. Most people do not flip that switch. FitFight will not see their WHOOP, Oura, Polar, COROS, Garmin, or Strava data unless they connect that account in FitFight.

Apple Watch and the iPhone have **no cloud API**. HealthKit is the only legal way to read them.

## Wanted sources

| Source | How FitFight pulls it | What we get | Gate before coding |
| --- | --- | --- | --- |
| **Apple Watch / iPhone** | HealthKit on the phone. No REST API exists. | Steps (already), workouts, duration, distance, energy, sport type | Expand HealthKit types + consent copy |
| **WHOOP** | Public OAuth 2 API + webhooks | Workouts, sleep, Recovery, Strain, RMSSD, HR | WHOOP app approval; written OK to show derived scores to Fight members |
| **Oura** | Public OAuth 2 API | Workouts, sleep, Readiness, HR, activity | Production user-cap approval; active Oura membership for Gen3+ |
| **Polar** | AccessLink / API v4 OAuth | Exercises, daily activity, HR, sleep, cardio load | Register an AccessLink app |
| **COROS** | Partner OAuth API | Workouts, HR, sleep, distance | Marc: apply at [COROS API](https://support.coros.com/hc/en-us/articles/17085887816340-Submit-an-API-Application) / `api@coros.com` |
| **Garmin** | Garmin Connect Health + Activity APIs | Steps, workouts, Body Battery, stress, FIT detail | Marc: apply to the [Garmin Connect Developer Program](https://developer.garmin.com/gc-developer-program/) |
| **Strava** | Public OAuth 2 API + webhooks | Activities the athlete recorded in Strava | Collect for that person. **Do not put Strava numbers on someone else’s Fight** until Strava gives written approval. 2026 policy: display only to the authenticated athlete; 7-day cache |
| **Amazfit / Zepp** | **No public developer API.** Zepp OS OAuth is for watch apps, not pulling a user’s cloud history. | — | Apple Health export if they enable it. Do not reverse-engineer Huami. Ask Zepp for a partner API or drop this source |
| **Nike Run Club** | **No public consumer API.** Internal Nike endpoints are not a FitFight integration. | — | Apple Health workout if they enable NRC → Health. Do not scrape |
| **Peloton** | **No public API.** Community scrapers exist; we will not use them. | — | Apple Health workout if they enable Peloton → Health |

Parked this wave: **Fitbit / Pixel / Google Health** (Pixel is Android; Fitbit cloud would be the Google Health API, not this iPhone list), Samsung, Health Connect, Suunto, Wahoo, Zwift.

## First collection slice

Still **private**. Still **not** a Fight score. One Data source per member later; never add WHOOP + Strava + Watch for the same run.

1. Keep shipping Steps from Apple Health.
2. Add Connect on You for **WHOOP** and **Oura** first (public APIs, workouts plus Recovery/Readiness on the same connection).
3. Expand Apple Health to private `HKWorkout` + duration / distance / energy so Watch/iPhone sports exist in the same store.
4. Polar next (public AccessLink). Then Garmin and COROS once Marc has credentials.
5. Strava OAuth for the signed-in athlete’s own history. Fight standings stay blocked until written approval.
6. Amazfit, Nike Run Club, Peloton: HealthKit fallback only unless a partner API appears.

Normalize into one activity/observation shape at ingest. Vendor sport strings map into Apple’s `HKWorkoutActivityType` (running, cycling, swimming, strength, yoga, hiking, … ~80 types) plus `other`. Do not invent a second sport list.

## What Marc has to do (cannot be done from the cloud)

- WHOOP: create the developer app, wait for approval, confirm Fight-member display.
- Oura: create the app, apply to raise the user cap.
- Polar: AccessLink client.
- Garmin: Connect Developer Program.
- COROS: API application.
- Strava: API app now; written social-display approval before any shared Fight uses Strava data.
- Amazfit / Nike / Peloton: there is nothing to apply to today.

Secrets stay in Vercel/GitHub, never in git or iOS.

## Honest limits

- Connecting WHOOP in FitFight does not also give us Apple Watch. Two sources, two connections, one selected source per Fight.
- HealthKit still looks empty when the person denied read or never wrote that type.
- Garmin Connect often needs the companion app opened before *HealthKit* updates. The Garmin **API** does not have that problem.
- Empty Nike/Peloton/Amazfit in FitFight is expected until they enable Apple Health or a partner API exists.

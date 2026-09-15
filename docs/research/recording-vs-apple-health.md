# Recording a run vs pulling Apple Health

Research date: **14 Sep 2026**. Product research, not a build. Public Apple / Runna / Strava docs only. Do **not** decompile Runna or Strava.

FitFight currently scores **Steps** from Apple Health. The phone already stores private workout summaries from Health. Those extras are not fight options yet. Related: [`sports-health-integrations.md`](sports-health-integrations.md), [`apple-health-next-metrics.md`](apple-health-next-metrics.md). Backlog row: [Do not build a FitFight run recorder](https://app.notion.com/p/3db8907c7ecf8157956cf58aecadae75).

## Short answer

**For scoring a Fight, there is no point in FitFight recording the run.** Apple (or the user’s Watch / Apple Workout / Strava / Runna / Garmin writing into Health) already turns sensors into distance, pace, heart rate, and calories. We already pull that object.

Record only if the product becomes the **live session**: coaching on the wrist, a live map, “start together now,” or GPS proof while the person is moving. That is Runna’s and Strava’s job, not FitFight’s current job.

You do **not** convert raw accelerometer samples into a 5K. Apple does that when a workout session is running.

## What “record” actually means

Three different jobs get mixed up:

| Job | Who does it today | FitFight need |
| --- | --- | --- |
| Turn motion/GPS into steps, distance, HR, calories | Apple Watch + HealthKit during a workout session | **No.** Read the result. |
| Start / pause / save a session, show live pace, keep the Watch awake | Apple Workout, Strava, Runna | **Only if** we want “Record” in FitFight. |
| Score a week-long fight from those sessions | Health store → our ingest | **This is us.** Already the plan. |

If friends race “most running distance this week,” the recorder can be Apple Workout. FitFight only needs the `HKWorkout` that lands in Health.

## Apple already does the sports conversion

The stack, from raw to “a run”:

1. **Sensors.** Accelerometer, gyro, GPS, optical HR. Apps do not talk to the GPS chip. They ask Core Location / HealthKit. Apple fuses the radios.
2. **Core Motion.** `CMPedometer` already returns steps, distance, cadence, floors. That is Apple’s conversion, not a FitFight algorithm.
3. **Workout session (Watch).** `HKWorkoutConfiguration` (running + outdoor/indoor) → `HKWorkoutSession` + `HKLiveWorkoutDataSource`. Apple **tunes the sensors** for that sport and **automatically saves** samples such as heart rate, active energy, resting energy, and walking/running distance. Your app updates the UI from `builder.statistics(for:)`. [Running workout sessions](https://developer.apple.com/documentation/healthkit/running-workout-sessions)
4. **Saved object.** `finishWorkout` writes an `HKWorkout` into Health. That is the sports object. Optional `HKWorkoutRoute` is the GPS path, separate permission.
5. **WorkoutKit.** This is the **plan** (intervals, targets) synced into Apple’s Workout app. It is not the sensor pipeline. Completed health stats still come from HealthKit. [WorkoutKit](https://developer.apple.com/documentation/workoutkit)

Indoor / treadmill is the exception: GPS is useless, so Apple (and everyone else) falls back to motion + stride calibration. That is why Apple has a Watch calibration walk, and why Runna tells treadmill users to start from the **phone** and merge Watch heart rate.

Raw `CMAccelerometerData` is not how you build a running app in 2026. You would only go there for a custom indoor gadget Apple does not already measure.

## What it would take if we did record

A serious iPhone+Watch recorder is a **second app**, not a HealthKit query:

- Watch app + Workout Processing background mode
- Health **write** for workouts (we currently **read**)
- Location while using / always, plus Motion & Fitness
- Live session UI, pause, crash recovery (`recoverActiveWorkoutSession`)
- Outdoor GPS route vs indoor treadmill merge
- Duplicate sessions if the user also has Strava or Runna running
- App Review for always-on location and a Watch companion
- CI already cannot compile Watch targets on this Linux box; GitHub `macos-26` would

Phone-only GPS recording (Strava’s Record tab) is smaller than a Watch app, still needs background location, a map, and a Health write at the end. iPhone has no built-in HR; you need a Watch or a Bluetooth strap.

## When recording would have a point

| Want | Record ourselves? |
| --- | --- |
| Steps / Move / “did you train this week” | **No.** Health already has it. |
| Running distance or workout-count fights | **No.** Read `HKWorkout` / `distanceWalkingRunning`. |
| Live coaching, intervals, “speed up” | **Yes, but that is Runna.** Out of product scope. |
| Live race: both people running *now*, live map | **Yes.** Needs a session. |
| GPS proof / anti-cheat on a single run | Maybe, later. Still does not replace Health for week totals. |

If we record **and** the user records in Strava/Runna/Apple Workout, Health gets two copies. Runna already warns people not to pair the Watch with Strava at the same time. FitFight would inherit that mess.

## How Runna does it (public)

Runna is a **coaching** app. They record because they need a live session: pace targets, audio cues, laps, mirroring.

Two recording paths, both Apple-backed:

1. **Runna Watch app** — their session, live cues. Completed workout **saves to Apple Health / Fitness**, then syncs back into the plan.
2. **Apple Workout / Fitness via WorkoutKit** — they push the scheduled session into Apple’s Workout app. Apple records. Runna **reads Health** afterwards. Their own audio cues **do not** play there; Apple’s APIs do not give them that.

Treadmill: phone owns distance/pace; Watch streams HR/cadence/calories; they merge. Outdoor Watch accelerometer distance is treated as less trustworthy than GPS.

They write Workouts and Workout Routes to Health. They also **import** completed Apple Workout sessions. That is the same ingest idea as FitFight, plus a recorder they need for coaching.

[Runna + Apple Watch](https://support.runna.com/en/articles/6306200-how-to-use-your-apple-watch-with-runna)

## How Strava does it

Strava is a **recording social network**. The activity (map, segments, feed) *is* the product. So they record.

- **Phone Record** — GPS while you run. Motion permission for live elevation on iOS; after upload they **correct elevation on their servers** against a map database. Auto-pause uses GPS or the accelerometer. [Recording an activity](https://support.strava.com/en-us/articles/15402137-recording-an-activity)
- **Strava Watch app** — own session, uploads to Strava. They tell people not to run another GPS workout app at the same time.
- **Apple Health bridge** — they **write** Strava-recorded type/distance/time/calories/route into Health. They **import only native Apple Workout** sessions from the last 30 days. Garmin/Zwift/Runna workouts sitting in Health **do not** come into Strava that way. [Apple Health and Strava](https://support.strava.com/en-us/articles/15402024-apple-health-and-strava)

So Strava is not “Apple records, we just pull.” They record for the live map and their graph. They still use Apple as a **sidecar** for people who prefer the Workout app.

Direct Strava API is still **blocked** for a shared FitFight leaderboard under the 2026 API Policy. HealthKit copies of a Strava-written workout are a different path; we already decided not to claim Strava provenance we did not collect.

## What FitFight already has

The phone already asks Health for movement types and may send private rows:

- Daily totals: energy, walking/running distance, exercise/stand, flights, sport distances, …
- Workout summaries: type, start/end, duration, optional distance, energy, effort

Those live in `private.healthkit_activity_days` and `private.healthkit_workouts`. They do not score fights yet.

That is enough to **look** at whether a running-distance or workout-count fight is fair. It is not a recorder.

## Recommendation

1. **Do not build a FitFight recorder or Watch app** unless Marc wants a live-session product.
2. **Keep HealthKit-first.** If someone records in Apple Workout, Strava, Runna, or Garmin → Health, we see the workout when they grant Workouts.
3. **Look at the stored private workouts** before publishing a run fight. Same collect-first rule as Active Energy.
4. **Do not decompile Runna.** Their public docs already show the split: Apple measures; they coach and optionally schedule via WorkoutKit.

Marc can treat this as answered: Apple measures; we pull; record only for a live race.
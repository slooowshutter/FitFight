# Runna-style training algorithm — research, not a build

Recorded **14 Sep 2026** after Marc asked to reverse-engineer **Runna** (the running-coach app), pull what the science actually means by easy / intermediate / long, and sketch a weekly plus “I want to run today” recommender. Running, cycling, and swimming share a 3-zone engine; they do **not** share the same speed math or injury caps.

This is product research. Production scoring stays **Steps**. Do **not** ship a coach, a workout fight, or a recommendation UI until the backlog says so. Inbox row: [Runna-style run recommendations](https://app.notion.com/p/3db8907c7ecf81e28bffc4e48117b173). Daily picker detail: [`run-today-recommendation.md`](run-today-recommendation.md). Related: [`apple-health-next-metrics.md`](apple-health-next-metrics.md), [`sports-health-integrations.md`](sports-health-integrations.md).

---

## The short answer

Marc’s instinct is half-right.

- **Yes:** once current fitness is known, easy / tempo / interval targets all move together. Fitter people run every session faster. That is how Runna and Jack Daniels work.
- **No:** do **not** take “average run speed” and add 10–20% for an intermediate, or subtract 10% for a long run. Recreational average pace is usually already too fast (the gray zone). A long run is almost the **same speed as easy**, just **longer**.
- **Anchor on a recent 5K, not on easy and not on average.** Easy ≈ **78–85% of 5K speed**, tempo ≈ **90–94%**, intervals ≈ **5K pace**. “Tempo ≈ easy +20% speed” only works when easy is *truly* conversational (Daniels E). If easy days were already moderate, that +20% is interval work.
- **Same sport family, different adapters:** running, cycling, and swimming all use easy / threshold / VO2 sessions. Count **sessions**, not minutes, for the 80/20 mix. The **anchor** changes (run pace, bike power, swim CSS). Running is the only one where a too-long session is a major injury spike.

The smallest useful product is **not** a full Runna clone. It is:

1. Estimate current **easy** and **threshold** from a recent 5K/10K (or a conservative easy-run sample).
2. Build a week from “how many days will you run?”
3. When they open the app and say they want to run **today**, pick the session the week still needs, then cap distance so today’s run is not >10% longer than their longest in the last 30 days.

FitFight already stores private `HKWorkout` summaries. That is enough for a later v1. Heart-rate zones, VO2max, and sleep are not required.

---

## Verdict on “average ±10–20% speed”

Worked example from Jack Daniels VDOT 50 (about a 20:00 5K). Easy ~8:14/mi, threshold ~6:51/mi, interval ~6:16/mi.

| Session | Pace | Speed vs **easy** | Speed vs a typical mixed **average** (~7:30/mi) |
|---|---|---|---|
| Easy / most long runs | 8:14/mi | 1.00 | already slower than average |
| Tempo / threshold | 6:51/mi | **+20%** | +9% — too close to “just a bit faster” |
| Intervals (VO2) | 6:16/mi | **+31%** | +20% — this is where +20% from average accidentally lands |

The same +20% vs **true easy** holds at VDOT 40 and 60. Same runner vs **5K speed**: easy ~78%, tempo ~94%, intervals ~102%. Prefer the 5K column in code. Use ×1.20 vs easy only as a fallback when those easy runs pass a talk test.

It fails if the baseline is **average GPS pace**, because that average is a stew of easy, commute, and accidental tempo. Then “average + 20%” becomes interval work every time you wanted a moderate day. It also fails if “easy” was already grey-zone: then +20% vs that pace is VO2 work, not tempo.

Long run at “average − 10% speed” can accidentally look easy **if** the average was already moderate. That is luck, not a model. Science and Runna both say: long run = **easy effort, longer duration**. Some weeks add a faster finish; the body of the run stays conversational.

**Use this instead:**

1. Anchor on a recent all-out 5K/10K (current ability, not a goal time). Runna does exactly this. They do **not** publish VDOT; the shape is VDOT-*like* (one race time → all paces).
2. If there is no race, take the **slowest** 20–40 min steady runs from the last 4 weeks as easy. Do **not** average everything. Stay on talk-test easy for 3–6 weeks, then unlock tempo/intervals after a 5K or 20-min time trial.
3. Scale duration, not just speed. Easy and long share a pace band; they differ in minutes.

---

## What Runna actually does (public)

Runna is a **rules-based coaching system**, not a published neural net. Strava announced it would [acquire Runna on 17 Apr 2025](https://press.strava.com/articles/strava-to-acquire-runna-a-leading-running-training-app) and later [replaced Strava’s own web running plans](https://support.strava.com/en-us/articles/15401942-training-plans-for-runners) with Runna. Public support docs are enough to copy the product loop. Internal mileage curves stay black-box. They never claim sleep/HRV as plan inputs (Garmin Run Coach does).

Sources: [fitness / first session](https://support.runna.com/en/articles/15231838-how-does-runna-build-your-training-plan-around-your-current-fitness), [injury / load](https://support.runna.com/en/articles/15279082-how-does-runna-reduce-the-risk-of-injury-and-overtraining), [pace insights](https://support.runna.com/en/articles/14656203-what-are-pace-insights-and-how-do-they-work), [estimated race time](https://support.runna.com/en/articles/6205998-adjusting-your-estimated-race-time-and-pace-targets), [training preferences](https://support.runna.com/en/articles/10393191-how-to-use-training-preferences), [80:20](https://support.runna.com/en/articles/9551650-80-20-training-principle), [easy](https://support.runna.com/en/articles/13729841-what-is-an-easy-run), [tempo vs intervals](https://support.runna.com/en/articles/13848642-what-s-the-difference-between-a-tempo-and-interval-running-session), [long run](https://support.runna.com/en/articles/13752466-what-is-a-long-run), [long-run types](https://support.runna.com/en/articles/9357249-understanding-the-long-runs-in-your-runna-plan), [instant workouts](https://support.runna.com/en/articles/10116460-how-to-use-instant-workouts), [extra / club / parkrun](https://support.runna.com/en/articles/6206280-how-can-i-adjust-my-plan-to-add-extra-runs-parkrun-and-club-runs), [skip](https://support.runna.com/en/articles/15012850-how-and-when-to-skip-a-run-managing-missed-sessions-in-your-training-plan).

### Product loop

```text
Onboarding
  ability, days/week, current mileage, longest run,
  recent 5K/10K/HM time, goal (race vs run-faster vs run-further)
        ↓
Rules engine writes a week of typed sessions
  easy | long (4 flavours) | tempo | intervals | hills | rest
  pace targets from estimated current race time, not goal time
        ↓
You run. Speed sessions get a Pace Status.
        ↓
Pace Insights may suggest faster/slower targets.
  Nothing changes until the runner accepts.
        ↓
Volume and difficulty are separate knobs.
  Volume = how much. Difficulty = how many/how hard the quality days.
```

Beginner / return-to-running plans are **effort-based**. No pace targets. Walk-run first. Strength is optional, max **4×/week**, and **does not** change running adaptations.

Ability (their labels; “regularly run” = one-run distance, not weekly km): Beginner = 5 km without stopping under 60 min; Intermediate = regularly ≥5 km, unstructured; Advanced = regularly ≥10 km + some intervals; Elite = regularly half-marathon+ + structured; Elite Plus = 80–100 km/week. Runs/week caps: Beginner 2–4, Intermediate 2–5, Advanced 2–6, Elite 2–7. Most plans **6–26 weeks** (Maintain can be 3). Race/distance plans stop at **50 km**; Hyrox / tri plans are **run-only**.

### Constraints they disclose (copy these)

- Weekly mileage has a **ceiling on the week-to-week jump**. Higher-mileage and 6–7 day runners build **slower**, not faster.
- **Long run has its own build limit**, independent of weekly mileage. After 2+ weeks without a long run, the first one back is capped. **No two long runs back-to-back.**
- Foundation plans use a **double constraint**: min(fixed bump, multiple of current best).
- Deload typically **every 4–6 weeks** and is **not labelled in-app** (you infer a lighter week). Hard sessions shrink more than easy. HM+ **or** any plan ≥10 weeks → **3-week taper**; 10K and below on a shorter plan → **2 weeks**. You cannot skip a future week yourself (support can).
- Missed sessions: **Skip** (not doing it) vs **drag ±1 week** vs leave unticked. After **>3 misses or a week**, [Plan Realignment](https://support.runna.com/en/articles/10026375-how-to-use-the-plan-realignment-feature) (usually Monday). If short on time, drop the speed session first; keep long + easy.
- “Not feeling 100%” **pauses mileage and pace progression** (3–14 days). Holiday mode is 3–21 days and does **not** extend the plan.
- They will not let you race a distance your current long run cannot build toward.
- Pace is preferred over HR because wrist HR is noisy and needs a lab to set zones well. Easy is a **ceiling** (“no faster than”), not a target; **talk test wins** if pace/HR/RPE disagree. Hills are effort, never pace. Walking rests in intervals **count toward weekly mileage**. Optional heat overlay above ~20 °C / 68 °F slows paces if the user accepts; it does not change the race-time estimate. [Pace Insights](https://support.runna.com/en/articles/14656203-what-are-pace-insights-and-how-do-they-work) is the **only** published pace-adaptation path (chart = last five speed sessions). Volume/structure change only via explicit user levers.
- Instant Workout / parkrun **mileage accounting is inconsistently documented** (calendar says extras are not the plan; one FAQ says parkrun counts). Copy the UX: extras do not rewrite the week. Decide load accounting ourselves.

### 80/20, as Runna states it (this matches the science for amateurs)

| Days / week | Mix they recommend |
|---|---|
| 5–7 | ~80% easy sessions, 2–3 hard |
| 2–3 | Runna: ~60/40 (1 easy + 1–2 quality). **We should ship 1 quality at 3 days, 0–1 at 2 days.** Strict 80/20 at low frequency means almost never going hard; stacking two quality days on a 3-day week is the amateur failure mode. |

Warm-up, cool-down, and jog recoveries inside a quality session **do not count as hard**. Marathon-pace blocks are “steady,” not automatically hard, if they match current fitness.

### “I want to run today” in Runna

Runna does **not** auto-pick today’s extra session the way Garmin Daily Suggested Workouts do.

- **Plan day:** do the scheduled workout, or skip / drag it.
- **Extra day:** [Instant Workout](https://support.runna.com/en/articles/10116460-how-to-use-instant-workouts) (user **chooses** easy / long / tempo / intervals / parkrun) or a free run. Extra runs **do not replace** the plan. Premium.
- Club / parkrun: swap for an easy if social, or for the week’s speed session if you will race it.

Garmin is the closer model for Marc’s “today I wanna run → tell me what”: one suggestion from recent load, fitness, and recovery, with rest as a valid answer. ([Garmin daily suggestions](https://www.garmin.com/en-US/blog/fitness/daily-workout-suggestions-for-runners/))

Nike Run Club is a **fixed** plan plus audio-guided easy / long / speed. It does not reverse-engineer your Health history into paces.

### What they do not publish

Exact weekly % build, exact long-run km caps, VDOT vs proprietary race-time tables, how many speed sessions enter a Pace Insight, and the full Instant Workout library. Treat those as **our** rules below, labelled as such.

---

## What the research actually says

Elite observational data and recreational injury data answer different questions. Do not copy 160–220 km/week marathon logs onto a 3-day FitFight user.

### Intensity is three zones, not “short / medium / long”

| Zone | Physiology | Feels like | Typical running work |
|---|---|---|---|
| **Z1 Easy** | Below first lactate/ventilatory threshold (LT1/VT1) | Full sentences. RPE ~2–4/10. ~60–75% VO2max | Easy days, most of the long run |
| **Z2 Tempo** | Between LT1 and LT2 | Comfortably hard. RPE ~6–7. ~83–88% VO2max | Tempo, cruise intervals, marathon-pace blocks |
| **Z3 Hard** | Above LT2, toward VO2max | Few words. RPE ~8–9. ~95–100% VO2max | Intervals 1–5 min, short hills, 5K pace reps |

Seiler’s review: nationally competitive endurance athletes cluster around **~80% of sessions easy, ~20% dominated by high intensity** — that is a **session-count** rule. Time-in-zone looks even easier (~90%+ Z1) because interval minutes are short. Polarized means most of that 20% is Z3 with little Z2. Pyramidal means the 20% is more Z2 than Z3. Both beat “everything at threshold.” Short RCTs often favor polarized for VO2peak; elite runner *logs* look pyramidal by time. A 2024 meta-analysis found no clear time-trial winner. ([Seiler 2010](https://www.edzo.info.hu/images/Seiler2010.pdf); [Stöggl & Sperlich 2014 RCT](https://doi.org/10.3389/fphys.2014.00033); [Stöggl & Sperlich 2015](https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2015.00295/full); [Casado et al. 2022](https://journals.humankinetics.com/view/journals/ijspp/17/6/article-p820.xml); [Haugen et al. 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC8975965/); [Oliveira et al. 2024](https://doi.org/10.1007/s40279-024-02034-z))

World-class distance runners still do **≥80% of volume easy**, 11–14 sessions/week. That is not a recreational template. The transferable rule is: **most time easy, a little work that is actually hard, almost nothing in the muddy middle.**

Runna’s own tempo vs interval copy: tempo ~10K–HM pace, RPE 7–8; intervals at or just below threshold (shorter reps can go 5K pace), RPE 8–9. Hills are effort, not pace.

### Jack Daniels paces (the practical mapping)

From a current race time → VDOT → five paces. Easy includes the long run. ([VDOT training definitions](https://vdoto2.com/learn-more/training-definitions))

| Code | %VO2max (approx) | Cap | Role |
|---|---|---|---|
| E Easy | 59–74% | 150 min | Daily easy + long. Conversational |
| M Marathon | 75–84% | ~110 min / 18 mi | Race-specific, not a default “intermediate” |
| T Threshold | 83–88% | ~20–40 min quality, ~10% of weekly miles | Tempo |
| I Interval | 95–100% | Reps 1–5 min; total I-pace ≤ 8% of weekly miles and ≤ 10K | VO2 |
| R Repetition | >100% | Reps ≤ ~2 min | Economy / speed. Skip in v1 |

Long run **duration** cap in Daniels: **≤ 25–30% of weekly mileage, or 150 minutes, whichever is less.**

### Injury: the 10% *week* rule is weak; the 10% *session* rule is not

- Nielsen 2014 (874 novices): week-to-week mileage jumps of <10% vs 10–30% vs >30% did **not** change overall injury rate. Distance-related injuries were higher above **+30% over two weeks**. So “never more than 10% a week” is folklore; **don’t jump more than ~30%** is the cautious read. ([JOSPT 2014](https://doi.org/10.2519/jospt.2014.5164))
- Buist GRONORUN 2008 RCT (532 novices): a 13-week 10% program vs an 8-week standard plan: injuries **20.8% vs 20.3%**, no difference. ([AJSM 2008](https://doi.org/10.1177/0363546507307505))
- Nielsen et al. 2025, 5,205 runners, 588k sessions: a **single run >10% longer than the longest run in the previous 30 days** raised overuse-injury rate (HRR 1.64 for +10–30%, 2.28 for doubling). Acute:chronic weekly ratio and week-to-week ratio were **not** associated. ([BJSM 2025](https://bjsm.bmj.com/content/59/17/1203), [PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC12421110/))

Runna independently discovered the same idea: **cap the long run separately from weekly mileage.** Copy that.

Coming back from a break: do not resume the old long run. Cap the first week (Runna). First session after 10+ days off is easy, not intervals.

### Recreational floor (not a training plan)

CDC / ACSM: ≥150 min moderate **or** ≥75 min vigorous aerobic per week, plus 2 days strength. Running three 25-min sessions already meets the vigorous floor. ([CDC](https://www.cdc.gov/physical-activity-basics/guidelines/adults.html))

---

## Algorithm v1 — FitFight coach (spec)

Two entry points, one engine.

```text
inputs
  days_this_week          // 2–6. User says how many they want.
  today_intent            // "plan the week" | "I want to run now"
  minutes_available       // optional, default from recent easy duration
  recent_workouts[]       // HealthKit: started_at, duration, distance, activity_type
  optional_5k_sec         // or 10K. Current ability, not a goal time
  feeling                 // optional: ok | tired | unwell

outputs
  week[] of { day, type, minutes, pace_band, why }
  or one today { type, minutes, pace_band, why }
```

Do not use heart rate in v1. Wrist HR is why Runna refuses it as the driver.

### 1. Fitness estimate

```text
if optional_5k_sec or 10k_sec exists and is ≤ 18 months old:
    fitness = that race time          // Runna: current ability, not goal
else:
    easy_candidates = running workouts last 28 days
                      with duration 20–50 min
                      excluding the fastest 25%
    if easy_candidates ≥ 3:
        easy_pace = median pace of those
        fitness = implied from easy ≈ 70% VO2  // conservative
    else:
        fitness = unknown
        prescribe effort only (RPE), no pace numbers
```

From `fitness`, set paces off **5K speed** when a recent time trial exists. Easy-relative multipliers are the fallback only.

| Band | vs 5K speed (preferred) | vs true easy (fallback) | Use |
|---|---|---|---|
| Easy / long | **0.78–0.85** | 0.95–1.05 | Z1 |
| Tempo | **0.90–0.94** | 1.18–1.22 | Z2 |
| Interval | **0.98–1.02** | 1.28–1.33 | Z3 |

That is Marc’s “percent of a baseline,” with the baseline fixed as **current 5K** (or true easy), never mixed average. If we later add Daniels tables, replace these with VDOT E / T / I. The week builder does not care. If there is no 5K, stay on talk-test easy until there is one.

### 2. Weekly template by days

Quality sessions = tempo **or** intervals. Never two quality days back-to-back. Long day prefers the weekend, or the same weekday each week (Runna).

| Days | Sessions | Hard : easy | Notes |
|---|---|---|---|
| 2 | 1 easy + 1 long (optional light quality) | 0–1 hard | Science default is **not** a weekly interval day. Runna’s 60/40 at 2–3 days is more aggressive than we should ship. |
| 3 | 1 long, 1 quality, 1 easy | 33/67 | Default amateur week. Not 2 quality days. |
| 4 | 1 long, 1 quality, 2 easy | 25/75 | First week that looks like 80/20 |
| 5 | 1 long, 1–2 quality, rest easy | 20–40 / 60–80 | Second quality only if they chose “challenging” and are recovering |
| 6 | 1 long, 2 quality, 3 easy | ~33/67 | Build **weekly km slower** than a 3-day runner. Never T + I + hard long. |

Default difficulty = **balanced** = 1 quality/week at 3–4 days, 2 quality/week only at 5–6 days. At 2 days, quality is optional.

Feel cannot **upgrade** intensity. “I feel great” may allow a quality day the week already wanted. It never creates intervals on a 2–3 day week or after a layoff. Full daily tree: [`run-today-recommendation.md`](run-today-recommendation.md).

Session length, before caps:

- Easy = median duration of last 4 weeks’ easy-ish runs, else 30 min.
- Long = min(1.5 × easy minutes, 30% of last week’s total minutes, 150 min, 1.10 × longest run in 30 days).
- Tempo quality = 20–30 min at tempo **plus** 10 min easy each side.
- Interval quality = e.g. 6 × 2 min at interval pace, equal jog rest, plus 10 min easy each side. Total interval-pace distance ≤ 8% of weekly km.

Every 4th week: deload. Cut long and quality duration ~30–40%. Keep easy days.

Progression week to week (our rule, combining Runna + Nielsen):

- Weekly minutes: +5–15%, never +30%.
- 6-day runners: use the low end.
- Long run: its own +≤10% vs last 30-day max (the 2025 finding).
- After ≥14 days with no long run: long = last completed long × 0.7, then rebuild.

### 3. “I want to run today”

This is the Garmin-style picker, not Runna Instant Workouts (where the user chooses the type).

Walk the list. First match wins.

```text
1. feeling = unwell            → rest. why: illness
2. no run in ≥10 days          → easy, minutes = last completed or 20.
                                 why: re-entry, not intervals
3. last session was yesterday
   AND it was long or quality  → rest or 20–30 min easy.
                                 why: 48h after quality/long
4. this week still needs its long
   AND (today is the long weekday
        OR only 1 run-day left) → long, then apply the 10% session cap.
5. this week still needs quality
   AND hours since last quality ≥ 48
   AND not the day before the long → tempo if last quality was intervals,
                                     else intervals (alternate).
6. else                        → easy at usual minutes
```

If they already have a plan for today, **that** is the recommendation. An extra run on top of a planned day defaults to **easy** and a warning: extra km still count toward the long-run cap. Do not stack a second quality day.

If they only have 25 minutes: never prescribe a long run. Shrink easy, or do a short tempo (15 min) only when rule 5 would have fired.

### 4. Worked week (3 days, no recent 5K)

Last 4 weeks: lots of 35–40 min runs around 6:00/km, plus a few 5:20/km “easy” that were not easy. Algorithm drops the fastest 25%, keeps ~6:00/km as easy.

- Tue quality: 10 easy + 20–25 tempo at **~5:00/km** only if 6:00/km was *conversational*. If those “easy” runs were already 5:20, stay easy until a 5K exists.
- Thu easy: 35 min at 6:00–6:15/km
- Sun long: 50 min at 6:00–6:15/km — **not** 6:40/km (−10% speed)

If they tap “run today” on Wednesday: easy, because yesterday was quality.

If they tap it on Saturday with the long still missing: long, capped at 1.10 × longest of last 30 days.

---

## Running vs cycling vs swimming

**One engine, three adapters.** Do not ship three products.

Shared:

- Z1 / Z2 / Z3
- **~80% of sessions** easy at 5+ days (not 80% of minutes). 1–2 quality sessions/week for amateurs.
- One longer aerobic session per week
- ≥48 h between quality sessions
- Fitness from a **sport-specific** threshold test, then all other sessions scale with it
- Session-RPE × duration is the only load that already works across sports. Do **not** add bike TSS to run TSS as if they were equal.

Not shared:

| | Running | Cycling | Swimming |
|---|---|---|---|
| Anchor | Race pace / VDOT-like 5K scalar | FTP (watts); Grand Tour papers split 3 zones at ~85% and 100% FTP | CSS = (T400 − T200) / 2 per 100 m |
| Easy / tempo / VO2 metric | min/km | %FTP (Coggan Z2 ~56–75%, Z4 ~91–105%) | s/100 m vs CSS. Ignore land HR in the pool. |
| Long session | ~20–30% weekly distance, cap ~150 min. Easy days often ~1 h | Duration *is* the stimulus. Easy days 3–5 h at the top end — **≥3×** running ([Sandbakk 2021](https://doi.org/10.1123/ijspp.2021-0022)) | 60–90 min. Technique/shoulders collapse first. No land-sport long-run analogue. |
| Injury | Session distance spike is the proven risk | Overuse exists; impact is low | Wrist HR unusable. Stroke errors look like “fitness drop” |
| Substitute for an easy run? | — | **Yes**, ~**1.5–2×** the run’s duration for aerobic Z1 | Yes, for aerobic Z1 |
| Substitute for a long run? | — | **Aerobic yes, race-specific no.** Keep the long run in the last 6–8 weeks before a running goal unless injured. | **No** |

Cyclists and distance swimmers historically spend **more time in Z2** than runners (pyramidal). That is an adapter parameter, not a second engine. VO2max and HR **do not transfer 1:1** across sports ([Millet 2009](https://pubmed.ncbi.nlm.nih.gov/19249890/)).

A bike “+20% speed” is meaningless (wind, gearing). Always percent of **that sport’s threshold**, never percent of running easy pace.

v1 for FitFight should be **running only**. HealthKit already has `running`, `cycling`, `swimming` on `private.healthkit_workouts`. The engine can grow later by swapping the adapter.

---

## What FitFight already has vs a coach product

Already stored, privately, not scored: workout `activity_type`, `started_at`, `ended_at`, `duration_seconds`, `distance_m`, `energy_kcal`, optional `effort`. Enough to compute easy pace, weekly minutes, longest-in-30-days, and days since last hard (hard ≈ pace ≥ tempo band, or duration ≥ 1.3 × median).

Missing for a serious coach, and **not required for v1**: per-km splits, heart rate, VO2max, sleep, routes, treadmill vs outdoor flag.

Current product is still **Steps × highest**. A recommender is a different app surface (You, or a later tab). Do not mix it into Fight scoring.

### If Marc later says build

Smallest ship:

1. You → **Today’s run** (one card: type, minutes, pace band, one-line why)
2. Optional: a 7-day strip from `days_this_week`
3. Optional 5K time on You, else infer easy from Health

Do **not** in the first ship: Instant Workout library, watch audio cues, Pace Insights with accept/reject, race-goal plans, strength, Hyrox, post-natal, or cycling/swim plans.

Legal: this is general fitness guidance, not medical advice. Unwell → rest. No diagnosis.

---

## Competitor snapshot

| App | Plan | Today / extra | Pace source | Copy? |
|---|---|---|---|---|
| **Runna** | Full adaptive week, 5K–50K, user-gated Pace Insights | Instant Workout = user picks type. Skip vs move vs Monday realignment | Estimated *current* race time. No goal-time mode. Not published as VDOT | Loop, skip/move, separate long-run cap |
| **Garmin Daily Suggested** | Rolling 7 days | **Auto-picks today**, including rest | VO2 / load / recovery on-watch | Today picker |
| **Garmin Coach / Run Coach** | Two products. Coach = named 5K/10K/half plans. Run Coach = daily plan from VO2, LT, sleep, recovery | Plan overrides DSW. Unplanned runs still change tomorrow | Watch physiology | Too watch-heavy for us |
| **Nike Run Club** | Six named plans, ~300 guided runs | Do the run when you want. Not from your files | Coach-named paces, not your 5K | Tone, not math |
| **TrainingPeaks** | Coach-built, TSS / CTL. “Dynamic plans” = coach broadcasts a calendar, not personal AI | Pair extras to a planned workout. Don’t cram a miss | FTP / threshold | Too pro |
| **Strava** | Owns Runna (17 Apr 2025). Native web running plans ended ~10 Jul; handed to Runna. Cycling CTS remains | Social log. Relative Effort is not a coach | Relative Effort | Social graph, not the coach |

---

## Decision for Marc

Pick one:

1. **Leave it on the backlog.** Keep collecting workouts. Revisit after Active Energy / workout fights exist.
2. **Spec-only freeze.** This file is the algorithm. Next chat implements Today’s run only.
3. **Do not build a coach.** Stay a Steps fight app. Point people at Runna.

Recommended: **1**. The science is settled enough to implement later. The current 1.0 job is still the private Steps fight.

---

## Sources (primary)

- Runna support articles listed in “What Runna actually does”
- Strava acquires Runna (17 Apr 2025). https://press.strava.com/articles/strava-to-acquire-runna-a-leading-running-training-app
- Seiler S. *What is Best Practice for Training Intensity and Duration Distribution in Endurance Athletes?* IJSPP 2010. https://www.edzo.info.hu/images/Seiler2010.pdf
- Stöggl T, Sperlich B. Polarized training RCT. *Front Physiol* 2014. https://doi.org/10.3389/fphys.2014.00033
- Stöggl T, Sperlich B. *The training intensity distribution among well-trained and elite endurance athletes.* Front Physiol 2015. https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2015.00295/full
- Casado A et al. *Training Periodization… Elite Distance Runners.* IJSPP 2022. https://journals.humankinetics.com/view/journals/ijspp/17/6/article-p820.xml
- Haugen T et al. *The Training Characteristics of World-Class Distance Runners.* Sports Med Open 2022. https://pmc.ncbi.nlm.nih.gov/articles/PMC8975965/
- Oliveira PS et al. Polarized TID meta-analysis. *Sports Med* 2024. https://doi.org/10.1007/s40279-024-02034-z
- Daniels J. VDOT training definitions. https://vdoto2.com/learn-more/training-definitions
- Nielsen RO et al. *Excessive Progression in Weekly Running Distance…* JOSPT 2014. https://doi.org/10.2519/jospt.2014.5164
- Buist I et al. GRONORUN 10% rule RCT. *Am J Sports Med* 2008. https://doi.org/10.1177/0363546507307505
- Nielsen RO et al. *How much running is too much?* BJSM 2025. https://bjsm.bmj.com/content/59/17/1203
- Sandbakk Ø, Haugen T, Ettema G. Training modality differences. *IJSPP* 2021. https://doi.org/10.1123/ijspp.2021-0022
- Millet GP, Vleck VE, Bentley DJ. Physiological differences between cycling and running. *Sports Med* 2009. https://pubmed.ncbi.nlm.nih.gov/19249890/
- CDC adult activity guidelines. https://www.cdc.gov/physical-activity-basics/guidelines/adults.html
- Garmin daily suggested workouts. https://www.garmin.com/en-US/blog/fitness/daily-workout-suggestions-for-runners/
- Coggan cycling levels. https://www.trainingpeaks.com/blog/power-training-levels/
- FTP vs threshold pace vs CSS. https://thetriathlete.co.uk/ftp-threshold-pace-css-triathlon-training-zones-explained/

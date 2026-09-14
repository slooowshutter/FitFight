# “I want to run today” — recommendation algorithm (spec)

**Status:** research / spec only. Do **not** implement in the app from this file.  
**Date:** 14 Sep 2026.  
**Audience:** a later engineer. Recreational runners, with or without a weekly plan.  
**Data world:** typical HealthKit / workout history, not a lab, not a WHOOP Recovery score.

This is a daily **session picker**, not a periodized coach. It answers one question:

> Given what this person already did, how they feel, how long they have, and (optionally) what the week already planned — what should they do *today*?

It must be safe when data is thin, boring when they are tired, and useful when they are ready. It must never invent intervals because the calendar looks empty.

FitFight’s shipped product is still private Steps fights. This document is a training-recommendation design, not a new fight type and not a WHOOP/Strava integration. Parent research (Runna reverse-engineer, weekly mix, ±% speed verdict, cycling/swim adapters): [`runna-style-training-algorithm.md`](runna-style-training-algorithm.md). Also [`sports-health-integrations.md`](sports-health-integrations.md) and [`apple-health-next-metrics.md`](apple-health-next-metrics.md).

---

## 1. What other products actually do

None of these apps publish their full scoring function. Public behaviour is still enough to copy the *product shape*.

### 1.1 Runna — extras sit beside the plan; load is counted later

Runna keeps a weekly plan and treats unplanned work as a **separate object**:

- **Instant Workout** — pick a structured session (easy, tempo, intervals, parkrun, …) with time/distance/pace. It is logged on the calendar. It does **not** rewrite the plan by itself. ([Runna Instant Workouts](https://support.runna.com/en/articles/10116460-how-to-use-instant-workouts))
- **Free Run** — unstructured extra. Same: logged, not a plan edit. ([Add extra runs](https://support.runna.com/en/articles/6206280-how-can-i-adjust-my-plan-to-add-extra-runs-parkrun-and-club-runs))
- **Mileage Insights** — after the fact, looks at *all* completed distance (planned + Instant + Free). If the athlete is consistently over or under, it *suggests* changing weekly mileage, long-run distance, or days/week. The athlete accepts or declines. It does not auto-mutate. ([Mileage Insights](https://support.runna.com/en/articles/11794078-what-are-mileage-insights))

Coaching rule they spell out: before adding extras, leave recovery around quality days; if a parkrun or club run is hard, **swap it for that week’s quality session**, don’t stack it on top.

**Steal:** extras are first-class; they count toward load; they do not silently rewrite the week; intensity of an extra should match a *slot*, not sit on top of another hard day.

### 1.2 Garmin Daily Suggested Workouts — load + recovery, plan wins

Garmin DSW is the closest analogue to “what should I do today?” with no printed week.

Inputs Garmin names publicly: training status, training load, Training Load Focus (low-aerobic / high-aerobic / anaerobic bars), VO2 max, recovery time, sleep, recent workout profile, max HR, lactate threshold / FTP. Non-run activities affect suggestions indirectly. Need ~two sport-specific activities in a week before status exists. ([Garmin: three ways your watch can help](https://www.garmin.com/en-US/blog/fitness/three-ways-your-garmin-smartwatch-can-help-you-work-out/); [types of DSW for runners](https://www.garmin.com/en-US/blog/fitness/daily-workout-suggestions-for-runners/))

Session menu: rest, active recovery, endurance/base (typically <80% HRmax), tempo, threshold, VO2max intervals, anaerobic, sprint. After time off, it rebuilds the endurance base first. Sprints only appear when recovery time is low (well recovered). Recovery time after a session is “hours until the *next hard* workout is a good idea,” not “do not move.” Max displayed recovery is **4 days**. Easy work is still allowed while the clock is running. ([Forerunner recovery time](https://www8.garmin.com/manuals/webhelp/forerunner245/EN-US/GUID-DAC27D10-886A-4EA8-8339-674479E9574A.html))

**Scheduled Garmin Coach / event plan overrides DSW.** An unplanned run still feeds training load, so tomorrow’s suggestion changes even if today was not started from the DSW card. Users report: an easy commute “satisfies” an easy DSW; it does **not** retire a pending threshold session.

**Steal:** plan beats daily picker; every recorded session updates load; “recovery remaining” blocks *quality*, not all running; after a layoff, base first.

### 1.3 Nike Run Club — library + mood, not a daily engine

NRC is a **catalog**: audio-guided runs by duration, distance, speed, treadmill, mindfulness, plus fixed plans (Get Started, 5K, 10K, half, marathon). The athlete picks. There is no public “you should do X today because yesterday was Y” engine. Extra recorded runs are just extra recorded runs. The coaching voice (Bennett) is “listen to your body and adapt,” which is a UX, not an algorithm. ([NRC plans](https://www.nike.com/gb/help/a/nrc-plan))

**Steal:** always offer a human-readable *why*; let the user pick an easier alternative; do not require a full plan to recommend a 25-minute easy run.

### 1.4 Strava Instant Workouts — weekly inspiration, not periodization

Strava subscribers get a Monday batch (~20) of suggested activities from focus + recent history: Build fitness / Stay active / Train for an event / Recover (press materials also used Maintain / Explore). Each card has a **why**. Running event plans moved to Runna (July 2026). Instant Workouts are explicitly *not* a progressive race plan. ([Strava Instant Workouts](https://support.strava.com/en-us/articles/15401583-instant-workouts); [press, 8 Jan 2026](https://press.strava.com/articles/strava-launches-new-instant-workouts-feature-worldwide-to-provide))

**Steal:** a focus string (build / maintain / recover) is a cheap, high-leverage input; explain every pick; do not pretend a daily extra is a marathon mesocycle.

### 1.5 WHOOP — readiness modulates intensity, extras consume today’s budget

WHOOP does not prescribe “8×400.” It answers “how much strain can you take *today*?” Recovery (green ≥67%, yellow 34–66%, red ≤33%) sets a Strain Target. An extra workout is reasonable if Recovery is decent **and** today’s accumulated strain is still below target; skip or keep it easy if already at target, ill, or crushed. Red is not a legal order to sit on the couch — WHOOP’s own researchers say it means lower readiness, so technique / easy / shorter. ([Recovery 101](https://www.whoop.com/gb/en/thelocker/how-does-whoop-recovery-work-101/); [Strain Target](https://www.whoop.com/us/en/thelocker/strain-coach/))

Project PR (WHOOP × Outside, ~8 weeks, ~2,500 runners, 5K): dynamic groups who shortened/eased yellow/red days improved 5K about as much as static-plan groups, trained less, and reported fewer injuries (WHOOP: up to 32% fewer in the dynamic groups; beginners on the static plan ~30% more all-cause injuries). This is a **vendor-run, self-reported-injury** study, not a peer-reviewed RCT. Use it as product evidence that *modulating down on bad days* is a good default, not as a medical claim. ([Project PR](https://www.whoop.com/us/en/thelocker/project-pr-runner-study/); [Outside write-up](https://www.outsideonline.com/outdoor-gear/run/want-improve-your-running-focus-recovery/))

HealthKit will **not** give FitFight WHOOP Recovery. Do not depend on it. Optional RPE/energy is the portable substitute.

**Steal:** today’s extra spends a budget; low-readiness days shrink duration and intensity rather than cancelling all movement; never require a proprietary recovery score.

### 1.6 TrainingPeaks — extras are TSS; the plan is a calendar, not an AI

Every completed file, planned or not, gets a Training Stress Score (duration × intensity vs threshold; rTSS from pace for running). Acute Training Load (ATL, ~7-day EWMA, “fatigue”) jumps fast; Chronic Training Load (CTL, ~42-day EWMA, “fitness”) crawls; TSB = CTL − ATL (“form”). An unplanned session is a grey calendar item until someone **pairs** it to a planned workout. The PMC does not auto-rewrite next Tuesday. Coaches move/skip by hand. Guidance for a missed session: **do not squeeze it in** next to the next quality day. A 10–14 day hole means **restructure**, don’t resume the old progression. ([TSS](https://help.trainingpeaks.com/hc/en-us/articles/204071944-Training-Stress-Scores-TSS-Explained); [pair workouts](https://help.trainingpeaks.com/hc/en-us/articles/115002250311-How-can-I-pair-and-unpair-my-planned-and-completed-workouts); [missed workouts](https://www.trainingpeaks.com/blog/how-to-handle-missed-workouts/))

**Steal:** count extras in load immediately; pairing is how “this parkrun *was* Tuesday’s quality”; never cram a missed hard day against tomorrow’s hard day; long layoffs reset the plan.

### 1.7 Pattern to copy

| Situation | Product consensus |
|---|---|
| There is a plan for today and the athlete can do it | Serve the plan (Garmin, TrainingPeaks, Runna). |
| Athlete wants something extra on a rest/easy day | Easy / Instant / Free. Count the load. Don’t add a second quality day. |
| Extra *was* actually the quality session (parkrun, club) | Treat as a **swap**, not a stack. |
| Athlete skips | Look forward. Don’t pile yesterday’s intervals onto today’s long run. |
| 10+ days off | Rebuild easy. Don’t resume the old workout. |
| Proprietary recovery score missing | Use spacing + recent load + optional RPE. Still recommend. |

---

## 2. Science vs coaching — what the rules are allowed to rest on

Label every rule in the algorithm as **S** (peer-reviewed, running-relevant), **C** (coaching practice / product convention), or **P** (product choice for this spec). Do not dress C/P up as physiology.

### 2.1 Intensity mix (S + C)

Elite and trained endurance athletes accumulate ~80% of training time at low intensity (below first ventilatory / lactate threshold) and ~20% hard. That is Seiler’s polarized / pyramidal observation, not a law of nature, but recreational studies that bias time below VT also work. ([Seiler 2010, *IJSPP*](https://doi.org/10.1123/ijspp.2010-0145); Esteve-Lanao et al. 2005; Muñoz et al. 2014 recreational runners.)

Jack Daniels’ Easy (E) pace is conversational, roughly 59–74% of VDOT velocity / ~65–79% HRmax depending on table edition. Garmin’s endurance DSW uses “typically below 80% HRmax.” The **talk test** (can speak in sentences) is a field proxy for being below the first ventilatory threshold.

**Rule we take:** most recommended days are easy. Quality is scarce. Easy means conversational, not “kinda tempo.”

### 2.2 Spacing of hard days (C, weakly S)

Coaches put ≥48 h between quality sessions (intervals, threshold, race). 72 h is common after a brutal session or for masters. Glycogen can refill in ~24 h with enough carbohydrate (**S**, Burke / Ivy), but neuromuscular and tendon load after intervals and long downhill do not; that 48 h figure is **practice**, echoed by Garmin’s “recovery time = ready for the *next hard* workout.”

**Rule we take:** for recreational runners, **no quality within 48 h of another quality or a long run**, unless the user explicitly overrides. This is C, applied as a hard product gate.

### 2.3 Acute:chronic ratio (S, but not the team-sport cartoon)

Gabbett popularised ACWR and a 0.8–1.3 “sweet spot” from **team sports**, plus the claim that spikes cause injury and high *chronic* load is protective. ([Gabbett 2016, *BJSM*](https://doi.org/10.1136/bjsports-2015-095788))

That cartoon does **not** transfer cleanly to running:

- Impellizzeri et al.: ACWR has coupling artefacts, is not shown to be a *causal* knob you should manipulate to cut injuries, and should not drive automated prescriptions. ([Impellizzeri 2020, *IJSPP*](https://doi.org/10.1123/ijspp.2019-0864))
- Nakaoka et al., 435 Dutch recreational runners: **higher** ACWR associated with *lower* predicted RRI (L-shaped), the opposite of the U-curve. EWMA ACWR was uninformative. ([Nakaoka 2021, *Sports Medicine*](https://doi.org/10.1007/s40279-021-01483-0))
- Frandsen, Nielsen et al., 5,205 Garmin runners, 18 months: **single-session distance >10% longer than the longest run in the previous 30 days** raised overuse-injury rates (small spike HRR 1.64, moderate 1.52, large 2.28). ACWR spikes and week-to-week spikes did **not** show the same positive association (ACWR even trended inverse). ([Frandsen 2025, *BJSM*](https://doi.org/10.1136/bjsports-2024-109380))

**Rule we take:** do **not** target 0.8–1.3. Do **not** refuse a run because ACWR is 1.4. **Do** cap today’s distance at ~1.10× the longest run in the last 30 days (S). Use a simple 7-day vs 28-day distance ratio only as a *soft* “your week is already heavy” downrank (C/P), never as a medical score.

### 2.4 The 10% weekly rule (C, weak S)

Buist et al. GRONORUN RCT: a 13-week 10%-per-week novice plan did **not** cut injuries vs an 8-week standard plan (~20.8% vs 20.3%). ([Buist 2008, *AJSM*](https://doi.org/10.1177/0363546507307505))

Nielsen et al.: jumping weekly distance **>30%** over two weeks associated with some (not all) injury types in novices. ([Nielsen 2014, *JOSPT*](https://doi.org/10.2519/jospt.2014.5164))

**Rule we take:** prefer not to jump this week’s projected volume more than ~30% above the last 4-week weekly average. Prefer session-level 10% vs 30-day longest (Frandsen) over a rigid weekly 10% law.

### 2.5 Detraining / return from layoff (S + C)

VO2max and plasma volume drop within 1–2 weeks of stopping; measurable aerobic loss is often cited in the 4–14% range over ~3 weeks. Muscle and tendon lag fitness on the way back. ([Mujika & Padilla 2000, *Sports Med*](https://doi.org/10.2165/00007256-200030020-00002))

TrainingPeaks coaching copy: 10–14 days off → restructure, don’t resume the written progression.

Runners Connect / similar coaching bands (C, used widely):

| Days since last run | Today |
|---|---|
| 1–7 | Easy shakeout, then normal logic tomorrow |
| 8–14 | 3–4 easy days before any quality |
| 15–30 | Rebuild 2–3 weeks; start ~60–70% of recent volume; no intervals week 1 |
| 30–60 | Base phase; several weeks easy before intensity |
| 60+ | Walk-run if needed; treat as a new runner |

**Rule we take:** those bands as hard gates. First run after ≥8 days is **easy or walk-run, never intervals**. First run after ≥15 days is also **shorter** (see §6).

### 2.6 Heat (S, optional module)

ACSM race flags use **WBGT**, not phone “feels like”: green <18 °C WBGT; yellow 18–23 slow down if high-risk; red 23–28 slow everyone / high-risk withdraw; black >28 cancel / voluntary withdrawal. ([ACSM heat and cold illnesses during distance running](https://khsaa.org/sportsmedicine/heat/heatandcoldillnessesduringdistancerunning.pdf); race-director summary of the flag system.)

Phone weather is dry-bulb + humidity, not WBGT. Approximation is OK for a *nudge*, not for a medical stop.

**Rule we take:** heat is an **optional modifier**: if enabled and estimated heat stress is high, forbid quality, shorten, and slow the easy band. Never required for v1.

### 2.7 Readiness without a wearable (C + thin S)

Session RPE × minutes is a validated internal-load proxy (Foster). WHOOP Project PR is vendor evidence that cutting duration/intensity on “bad” days preserves fitness. There is no HealthKit RPE.

**Rule we take:** optional 1–5 energy or 6–20 RPE. Low energy **cannot** upgrade a session; it can only rest / shorten / easy. Missing energy ≠ green light.

---

## 3. Design principles (P)

1. **Safety beats stimulus.** If the tree says rest or easy, do not “add a little speed for engagement.”
2. **Hard constraints, then a tiny menu.** The tree eliminates illegal session types. Scoring only ranks what remains.
3. **Explain in one breath.** Every output has `why[]` a coach could say out loud.
4. **Plan is a constraint, not a vibe.** If a weekly plan exists, the picker **serves or downgrades** it. It does not invent a second plan.
5. **Extras are first-class and counted.** Completing today’s pick updates load before tomorrow’s pick.
6. **Degrade gracefully.** No 5K, no HR, no labels, 3 runs in 90 days → still emit an easy 20–30 min conversational run or rest, with a more cautious why.
7. **Not medical advice.** Pain, illness, pregnancy, chest pain, dizziness: stop and see a clinician. The algorithm never diagnoses.

---

## 4. Inputs

### 4.1 Minimal (ship without these and the feature is a coin flip)

| Field | Notes |
|---|---|
| Workout history ≥ 90 days if present | `start`, `duration_s`, `distance_m` if any, `activity_type` (run / walk / other). HealthKit `HKWorkout`. |
| Local timezone calendar | Week = the user’s current week, not UTC. |
| `time_available_min` | Required the moment they tap “I want to run today.” Cap everything. |
| `days_wanted_this_week` | 2–6. Default 3 if unknown. |

That is enough for: last-run recency, longest-in-30-days cap, weekly count, a crude easy-vs-hard guess from duration, and a capped easy recommendation.

### 4.2 Should-have (makes quality days and paces honest)

| Field | Notes |
|---|---|
| Average pace (or distance + duration) | Classify easy vs quality; set E-pace band. |
| Workout labels | Interval / tempo / long / race / easy if the source wrote them (`HKWorkoutType`, metadata, third-party title). |
| Average HR if present | Helps classification when pace is noisy (hills, treadmill). |
| `feel` optional | Energy 1–5 **or** RPE 6–20 **or** {great, ok, tired, wrecked}. One control, not three. |
| Weekly plan, if any | Per day: session type, duration or distance, intensity, whether it is the long run. See §10. |
| Preferred long-run weekday | Default Saturday or Sunday in the user’s locale. |

### 4.3 Nice-to-have (improve, never block)

| Field | Notes |
|---|---|
| Current 5K estimate | Race, time trial, or Garmin/Apple VO2-derived equivalent. Drives Daniels-like bands. |
| Indoor vs outdoor, elevation | Downhill / hilly long runs are “harder” than the pace suggests (C). |
| Sleep duration last night | Soft downrank of quality if < typical − 90 min. Not a WHOOP substitute. |
| Heat: temp + humidity or WBGT | Optional module. Off by default. |
| User injury flag / “pain today” | Hard rest/walk. |
| Age / masters | Soft: prefer 72 h quality spacing if age ≥ 50 (C). |
| Surface (trail vs road) | Do not change the tree; mention in why if last long was trail and very long. |

**Explicitly out of v1:** HRV, Recovery scores, Body Battery, menstrual-phase programming, strength sessions as load (unless they are in HealthKit as workouts — then count duration as non-run load only for “already trained today,” not for running ACWR).

---

## 5. Derived features

Compute once per request. All windows are rolling, ending at **now**, local time.

### 5.1 Session classification of *history*

For each past run, assign `kind ∈ {walk, easy, quality, long, race, unknown}` and `quality_flavor ∈ {interval, threshold, tempo, race, none}`.

Order of evidence (first match wins):

1. **Label** if present and trusted: race, intervals, repeats, VO2, threshold, tempo, fartlek, strides-only, long, recovery, easy.
2. **Race:** duration 8–180 min and pace ≥ 95% of best 5K-equivalent (if we have one), or title contains race / 5k / 10k / half / marathon *and* effort looks all-out.
3. **Long:** distance ≥ `max(1.35 × median_run_distance_28d, 0.90 × longest_14d)` **and** not labeled quality. Recreational long is usually the weekly peak, not “any run over 45 min.”
4. **Quality (pace):** average pace ≥ 8% faster than `easy_pace_baseline` (definition below) **and** duration ≥ 20 min; **or** ≥ 12% faster for ≥ 8 min (interval-ish). Hills inflate HR and slow pace — if HR is high *and* pace is not fast, do not call it quality from pace alone.
5. **Quality (HR):** mean HR ≥ 88% HRmax if HRmax known; else ≥ 90th percentile of this athlete’s run HR. Use only when a chest or well-worn wrist series exists. Otherwise skip.
6. **Walk:** activity type walk, or pace slower than 9:00/km *and* labeled walk.
7. Else **easy**.

`easy_pace_baseline`: median average pace of runs in the last 42 days classified easy *after a first pass that treats unlabeled runs slower than the 60th percentile pace as easy*. If <4 such runs, use median of all runs × 1.08 (assume they run easy days too fast — C). If no pace at all, baseline is missing; quality detection from pace is off; rely on labels and duration.

**Today already trained:** any run ≥ 10 min with start in local today. If true, the picker recommends rest or a true optional easy only if `time_available` remains and they insist — default **done for today**.

### 5.2 Recency and spacing

- `days_since_any_run`
- `days_since_quality` (quality or race)
- `hours_since_quality` (use 48.0, not calendar days: a Thursday 19:00 interval blocks Friday)
- `days_since_long`
- `hours_since_long`
- `runs_this_week` (local week, completed)
- `quality_this_week`, `long_this_week` booleans
- `projected_week_distance` = completed this week + today’s candidate

### 5.3 Volume caps (S)

- `longest_30d_m` — longest completed run distance in last 30 days. If none, `null`.
- `session_cap_m` = `1.10 × longest_30d_m` if known, else a conservative default from §7.
- `week_avg_28d_m` — mean of the last four complete local weeks’ running distance (weeks with 0 still count as 0). Need ≥2 such weeks or skip.
- `week_spike_ratio` = `(distance_this_week_so_far + candidate) / week_avg_28d_m`

Optional, **never a gate:** `acwr_7_28` = (sum distance last 7 days + candidate) / (mean weekly distance last 28 days). Log it; maybe show “your last week is already heavier than usual” in why. Do not block on 1.3.

### 5.4 Time and preference

- `time_available_min` (input)
- `days_wanted` (input, default 3)
- `slots_left` = `days_wanted − runs_this_week` (if they already exceeded, `slots_left` can be 0 — extras still allowed as easy)
- `long_due` = preferred long weekday is today **or** (no long yet this week **and** preferred long is tomorrow/today and `slots_left` ≤ 2)
- `quality_budget` = 1 if `days_wanted` ≤ 3; 2 if `days_wanted` ≥ 4. Recreational default is one quality + one long, not two intervals (C).

### 5.5 Feel

Map to `readiness ∈ {high, ok, low, very_low, unknown}`:

| Energy 1–5 | RPE 6–20 (pre-run) | Words | readiness |
|---|---|---|---|
| 5 | ≤9 | great | high |
| 4 | 10–11 | ok | ok |
| 3 | 12–13 | tired | low |
| 1–2 | ≥14 | wrecked | very_low |
| missing | missing | — | unknown |

Pre-run RPE is “how does the body feel,” not Foster session RPE. If the UI only has energy, that is enough.

---

## 6. Guardrails (evaluate in this order, stop at first fire)

These override scoring. Each sets `blocked_types` and may force the output.

### G0. Medical / pain (P, safety)

If the user flagged injury, “pain that alters gait,” fever, dizziness, chest pain → **Rest**. Why: not a training day. Do not offer a “light jog it off” alternative as the primary. Secondary alternative may be a walk if they say the issue is mild stiffness, not pain.

### G1. Already ran today (P)

If a run ≥ 10 min exists today → **Done**. Why: extra doubles are how recreational runners accidentally create back-to-back quality. If they insist, only **easy ≤ 20 min** and only if the first session was easy and short (<30 min). Never quality.

### G2. Layoff re-entry (C + S detraining)

| `days_since_any_run` | Forced today | Duration cap |
|---|---|---|
| ≥ 60 | Walk-run or very easy | `min(time_available, 20–30 min)` |
| 15–59 | Easy only | `min(time_available, 0.6 × median_duration_42d, 40 min)` and distance ≤ `0.7 × longest_30d` if known |
| 8–14 | Easy only | `min(time_available, median_duration_42d, 45 min)` |
| 0–7 | No force | Normal tree |

Quality and long are illegal until: 8–14d layoff → 3 easy days completed; 15–29d → 4–6 easy days; 30d+ → at least 2 weeks of easy consistency (`runs_this_week` pattern, not calendar magic). **P** numbers; the *direction* is C/S.

### G3. Hard yesterday (C)

If `hours_since_quality < 48` **or** `hours_since_long < 36` (long is a quality-adjacent hit for most recreational runners):

- Illegal: quality, race, long.
- Legal: rest, walk, easy (recovery-flavoured).
- If `hours_since_quality < 18` **and** `readiness ∈ {low, very_low}` → prefer **Rest**.

36 h after a long (not 48) is **P**: Sunday long, Tuesday quality is the classic week (C). Monday is easy.

### G4. Protect the long run (C)

If `long_due` within 36 h (the long is tomorrow or later today and not yet done):

- Illegal: quality.
- Today’s pick is easy and **shorter than usual** (≤ 70% of median duration) so they don’t trash the long.
- If today *is* the long-run day and G0–G3 pass and `readiness` is not `very_low` → the candidate is **Long**, not intervals.

If they already did the long this week, do not offer another long.

### G5. Quality quota (C)

If `quality_this_week ≥ quality_budget` → illegal quality.

If `days_wanted ≤ 3` and they have not done the long and today isn’t long day → still prefer easy/long over inventing intervals. Three-day weeks are typically **easy / quality / long** or **easy / easy / long**, not two quality (C).

### G6. Session spike cap (S — Frandsen 2025)

Any candidate distance > `session_cap_m` is clipped. If clipping would make a “long” shorter than a normal easy, it is **not** a long day; call it easy.

If `longest_30d` is missing (new user): cap first run at 20–30 min easy. Do not prescribe 90 minutes.

### G7. Weekly volume caution (C, Nielsen-shaped)

If `week_spike_ratio > 1.30`, downrank long and quality; cap today’s distance so the ratio ≤ 1.30 unless today is the designated long *and* the long still respects G6. Never “make up” missed kilometres.

### G8. Feel (C + Project PR-shaped P)

| readiness | Effect |
|---|---|
| very_low | Rest or ≤ 20 min walk/easy. No quality, no long. |
| low | No quality. Easy allowed; shorten 20%. Long only if today is long day **and** they confirm. |
| ok / unknown | No change. |
| high | May *allow* quality if the tree otherwise wants it. **Never** invent quality solely because they feel great. |

### G9. Heat (optional, S-inspired)

If the module is off, skip.

Approximate: if dry-bulb ≥ 28 °C and relative humidity ≥ 60%, or WBGT ≥ 23 °C if you have it: illegal quality; easy only; shorten 20–30%; shift pace band slower; why mentions heat. If WBGT ≥ 28 °C or dry-bulb ≥ 32 °C: primary = **Rest / indoor easy / walk**. This is a **nudge** (phone weather ≠ WBGT).

### G10. Time available (P)

If `time_available_min < 15` → Rest or walk. Do not prescribe a 40-min easy they cannot do.

Clip duration to `time_available − 2` (shoes/buffer). If a planned quality cannot fit (need warm-up + work + cool-down ≥ time), **downgrade** to easy in the time they have. Do not squeeze intervals into 18 minutes.

---

## 7. Decision tree (plain language)

After G0–G10, remaining legal types are a subset of:

`Rest | Walk | WalkRun | EasyRecovery | EasyBase | Long | EasyWithStrides | Tempo | Intervals`

**Strides** = 4–6 × 15–20 s pickups at the end of an easy run. They are **not** a quality day and are illegal under G2/G3 if the last quality was <48 h (keep recovery actually easy). Allowed when easy is legal, layoff <8 days, and they have ≥30 min.

Walk the tree top to bottom. First matching **leaf** is the primary recommendation. Scoring (§8) only breaks ties the tree still leaves open (mainly: rest vs easy, and tempo vs intervals when quality is allowed).

```text
0. Guardrails G0–G10 already applied.
1. If Rest was forced → Rest. Stop.
2. If layoff ≥ 8 days → Easy (or WalkRun if ≥ 60 days or they cannot hold an easy jog). Stop.
3. If quality or long in the last 48 h / 36 h → EasyRecovery if they want to move, else Rest if very_low or they already hit days_wanted. Stop.
4. If today is planned (see §10):
     a. Planned Rest → if they insist on running, EasyRecovery only (extra).
     b. Planned Easy → EasyBase, clipped to time and G6.
     c. Planned Long → Long if G4/G6/G8 allow, else EasyBase.
     d. Planned Quality → that flavor if legal; else EasyBase (downgrade, do not shift quality to tomorrow automatically).
     Stop after emitting planned-or-downgraded.
5. No plan. If today is preferred long day, long not done, slots_left ≥ 1, readiness not very_low, G6 allows a run ≥ 1.2× median:
     → Long (easy). Stop.
6. No plan. If long is tomorrow (G4) → EasyBase short. Stop.
7. No plan. Quality allowed (G3, G5, G8 high/ok/unknown, layoff < 8, not the day before long):
     If they have never done labeled quality in 90 days → EasyWithStrides, not Intervals.
     If 5K or easy-pace baseline exists AND days_wanted ≥ 4 AND quality_this_week == 0 AND last quality ≥ 72 h
        → quality candidate (score Tempo vs Intervals, §8).
     Else if days_wanted ≤ 3 and long not done this week → do not place quality today unless they have no remaining weekend slot; prefer saving the “harder” day for the long.
     Else EasyBase.
8. Default: EasyBase if slots_left ≥ 1 or they explicitly want a run.
9. If slots_left ≤ 0 and they still want a run → EasyRecovery, extra, short, why: “bonus easy, not another workout.”
10. If they do not need a run (already at days_wanted, nothing due) and readiness is not high → Rest is a valid primary with Easy as alternative.
```

### 7.1 What each leaf *is*

Durations below are **before** clipping to `time_available` and G6. `M` = median duration of easy runs last 42 days, default 30 min if unknown.

| Type | Duration / distance | Intensity | Pace band |
|---|---|---|---|
| Rest | 0 | — | — |
| Walk | 20–40 min | very easy | walking |
| WalkRun | 20–30 min, e.g. 2 min jog / 1 min walk | easy | conversational jog |
| EasyRecovery | `min(0.7M, 40, time)` | easy | E slow half of band, or talk test |
| EasyBase | `min(M, 60, time)` typical; 20 min floor if M missing | easy | full E band |
| Long | `min(1.25–1.40 × M, session_cap, time)` | easy (or last 15 min moderate **only** if experienced and readiness high — default **no**) | E band; never quality pace |
| EasyWithStrides | EasyBase + 4–6 strides | easy + neuromuscular | E + short pickups, full recoveries |
| Tempo | Warm-up 10 + 15–25 min steady + cool-down 10, total ≤ time | quality | threshold / “comfortably hard,” ~85–90% 5K pace if known |
| Intervals | Warm-up 10 + 4–6 × 2–3 min hard / equal jog + cool-down 10 | quality | ~3–5K effort; not all-out sprints |

Recreational **tempo before intervals** when both are legal and the athlete’s history has little speed work (C: lower coordination/injury cost). Intervals only if they have done a quality session in the last 8 weeks **or** explicitly want speed.

### 7.2 Pace bands

Priority:

1. **5K time known** — Daniels-style (C, from *Daniels’ Running Formula*):
   - Easy: ~59–74% VDOT velocity → in practice often **5K pace + 45–90 s/km** (wider than many apps; recreational runners run easy too fast).
   - Tempo/threshold: ~5K pace + 15–25 s/km (not 5K race pace).
   - Interval: ~5K pace to 5K − 5 s/km, recoveries jogging.
2. Else **easy_pace_baseline** from history: Easy = baseline to baseline + 30 s/km (slower). Tempo = baseline − 20 to − 40 s/km (faster). If that would be faster than recent 5K-equivalent guess from best 20 min, cap it.
3. Else **no numbers**: Easy = “conversational, nasal or full sentences.” Quality = “could say a few words only.” Write that in the UI. Do not invent 5:10/km.

Always also emit RPE: easy 2–4 / 10, tempo 6–7, intervals 8–9. Talk test is the override: if they cannot talk, it is not easy.

---

## 8. Scoring (only among legal leaves)

Use when the tree leaves two legal options (Rest vs Easy; Tempo vs Intervals; Easy vs EasyWithStrides).

Each candidate gets a score 0–100. Pick the max. If within 8 points, prefer the **easier** one (P: recreational bias).

```text
score = 40
+ 15 if matches days_wanted remaining (they still “owe” a run)
+ 10 if fills Training-Load-like hole:
      too little easy this week → EasyBase
      no long and it’s long day → Long
      no quality in 7–10 days AND quality legal AND days_wanted ≥ 4 → quality
− 20 if type is quality
− 15 if type is long and week_spike_ratio > 1.15
− 25 if type is quality and readiness != high
− 10 if type is easy and they already hit days_wanted (it’s an extra)
+ 10 if duration fits time_available without clipping > 20%
− 30 if duration must clip > 40% (wrong type for the slot)
+ 5  if they have a 5K and quality is legal and last quality 5–12 days ago (maintenance)
```

Garmin-style “add anaerobic because the bar is short” is **intentionally weaker** than spacing. Recreational runners are under-recovered more often than they are under-intervalled (C).

Do not use ACWR as a term in this score. If you log `acwr_7_28 > 1.5`, add `why` “this week is already a lot compared with last month” and apply the G7 cap instead.

---

## 9. Output shape

One primary, plus up to two alternatives (usually easier, and the planned session if different).

```json
{
  "schemaVersion": 1,
  "asOf": "2026-09-14T07:12:00+02:00",
  "mode": "no_plan | serve_plan | downgrade_plan | extra_on_rest_day",
  "session": {
    "type": "easy_base",
    "intensity": "easy",
    "durationMin": 38,
    "distanceM": 5200,
    "distanceIsCap": true,
    "structure": null
  },
  "targets": {
    "paceSecPerKm": { "min": 375, "max": 420 },
    "paceSource": "easy_history | vdot_5k | talk_test",
    "rpe10": { "min": 2, "max": 4 },
    "talkTest": "full_sentences",
    "hrPctMax": { "max": 80 }
  },
  "why": [
    "Last harder run was yesterday, so this is easy.",
    "Your long run is Saturday; keep today short enough to show up for it.",
    "You have 40 minutes; this uses 38."
  ],
  "guardrailsFired": ["G3_hard_recent", "G4_protect_long"],
  "alternatives": [
    { "type": "rest", "why": ["You already have 3 runs this week."] },
    { "type": "easy_recovery", "durationMin": 25, "why": ["Shorter if the legs still feel yesterday."] }
  ],
  "planImpact": {
    "countsAs": "today_planned_easy | extra | swap_for_planned_quality | none",
    "doNotAlsoDo": ["Thursday intervals"],
    "weekAfterThis": "Still missing Saturday long. No more quality this week."
  },
  "confidence": "high | medium | low",
  "dataUsed": ["workouts_90d", "time_available", "days_wanted", "feel"],
  "dataMissing": ["fiveK", "hr", "plan"]
}
```

`structure` for quality:

```json
{
  "warmupMin": 10,
  "work": [{ "reps": 5, "onSec": 120, "offSec": 120, "offType": "jog" }],
  "cooldownMin": 10
}
```

`confidence`:

- **high** — plan served unchanged, or easy with ≥8 runs in 42 days and G3/G4 explained.
- **medium** — classified history without labels; paces from history not 5K.
- **low** — <4 runs in 90 days, or layoff branch, or talk-test-only paces.

UI copy rules:

- Lead with the session (“Easy 35–40 min”).
- One line why from `why[0]`.
- Show pace as a **band**, never a single number, unless VDOT-based and they asked.
- Rest is a first-class success state, not an empty screen.

---

## 10. Compose with a weekly planner

Two products, one load ledger. Copy Runna/Garmin/TrainingPeaks, not NRC’s “pick from a library and hope.”

### 10.1 Definitions

- **Planner** — owns the week: which days are rest, easy, quality, long. Can be user-built or generated. Not this algorithm.
- **Today picker** — this spec. Reads the plan if present.
- **Ledger** — completed sessions (planned, swapped, extra). Both features read it. Tomorrow’s picker never ignores today’s extra.

### 10.2 If there is a plan

| Today’s plan | User intent | Picker output |
|---|---|---|
| Quality / long / easy they can complete | “Run today” | **Serve plan** (`mode: serve_plan`), clipped to time and G6. |
| Quality, but G3/G8/G9/G2 fire | “Run today” | **Downgrade** to easy/rest. `mode: downgrade_plan`. Do **not** auto-move the quality to tomorrow (that can collide with the long). Surface: “Skip or move this workout in the planner.” |
| Rest | “I still want to run” | **Extra** easy only, short. `mode: extra_on_rest_day`. `planImpact.countsAs = extra`. Warn if tomorrow is quality/long. |
| Easy | “I want a workout” | Do **not** upgrade to intervals the day before the long or <48 h after quality. If quality is legal *and* they are swapping (parkrun), `countsAs = swap_for_planned_quality` and the planner should mark the planned quality complete. |
| Missed yesterday’s quality | “Run today” | Follow **today’s** plan. Do not stack missed intervals on today’s long. TrainingPeaks missed-workout rule. |
| 10+ days of missed plan | “Run today” | Ignore the written progression. Layoff tree. Planner should be told to rebuild (out of scope for the picker, but `planImpact` says so). |

**Pairing (TrainingPeaks / Runna):** if the user records a hard parkrun on a rest day, the picker cannot know intent up front. After the file lands, a later job should ask: “Count this as Thursday’s quality?” Default if they don’t answer: extra (load counts, quota `quality_this_week` becomes true anyway because classification will mark it quality — so the picker will refuse another quality even without pairing). That is the important part.

### 10.3 If there is no plan

The picker **is** the planner for 24 hours. It should not materialize a 12-week PDF.

Implicit week template from `days_wanted` (C):

| Days/week | Shape |
|---|---|
| 2 | Easy midweek, long weekend. No intervals until they add a 3rd day. |
| 3 | Easy, quality *or* easy, long. Quality at most 1, ≥48 h from long. |
| 4 | Easy, quality, easy, long. |
| 5–6 | Two quality only if G3 holds (typically Tue quality, Sat long, optional Thu tempo). Default still **one** quality until they have 8 weeks of consistency. |

Place the long on the preferred weekend day. Place quality 48–72 h before the long (e.g. Thursday quality, Sunday long) or Tuesday quality + Sunday long.

The today picker does not write those days; it only knows “long not done, weekend coming” via `long_due`.

### 10.4 After the session is recorded

1. Reclassify the file (§5.1).
2. Update `runs_this_week`, quality/long flags, `longest_30d`.
3. If it was harder than recommended (they hammered an easy day), tomorrow inherits G3. Do not scold in the picker; the tree handles it.
4. If Mileage-Insights-like adaptation of *weekly* days/mileage is desired, that is a **separate weekly job** (Runna Insights), not this daily function. Do not auto-bump `days_wanted`.

### 10.5 What the picker must not do

- Invent a deload week (needs a planner and a training age).
- Move tomorrow’s long to today because they feel great.
- Prescribe races.
- Stack Instant Workout quality on planned quality.
- Use Strength / HIIT from HealthKit to say “you already did intervals” unless duration ≥ 20 min and mean HR is in quality range — even then, treat as **quality-adjacent for G3**, not as a running long.

---

## 11. Minimal vs nice-to-have (implementation order)

**v1 — HealthKit workouts + three questions**

1. Last 90 days of run/walk workouts: start, duration, distance.
2. Time available today.
3. Days they want this week.
4. Optional feel (one slider).

Outputs: Rest / Easy / Long (easy) / WalkRun. **No intervals** until classification is trustworthy.

**v1.1 — labels + pace**

Classify quality vs easy. Enable Tempo/Intervals leaves. Pace bands from history.

**v1.2 — plan object**

`mode: serve_plan | downgrade_plan | extra_on_rest_day`. Pairing prompt after a hard extra.

**v1.3 — 5K estimate**

Tighter bands. Still talk-test override.

**Optional modules, off by default**

Heat, sleep, masters 72 h, HR zones.

**Not required ever for a good recreational picker**

ACWR sweet-spot targeting, WHOOP Recovery, Garmin Training Status, CTL/ATL numbers in the UI. Internally, 7/28 distance ratio as a log line is enough.

---

## 12. Worked examples

Assume `days_wanted = 3`, preferred long = Sunday, no heat module.

**A. Hard yesterday, 40 min free, feels ok**  
Sat long yesterday. Today Sun? If yesterday was quality Friday, today Saturday.  
G3 fires. Leaf: EasyRecovery 25–30 min, conversational. Why: “hard session <48 h ago.” Alternative: rest.

**B. Long due Sunday, today is Saturday, 50 min free, last quality Tuesday**  
G4: no quality. EasyBase ~0.7M (e.g. 30 min), not 50. Why: “save the legs for tomorrow’s long.”

**C. First run in 11 days, wants intervals, 45 min, feels great**  
G2: easy only. EasyBase ~30–40 min talk test. Why: “first week back is easy, even if you feel good.” Feeling great does not unlock intervals (G8 cannot upgrade).

**D. No plan, Tuesday, last run Sunday easy, last quality 9 days ago, 4 days/week, 5K = 28:00, feels great, 50 min**  
Quality legal. Score: Tempo vs Intervals → Tempo (little recent speed work). Structure: 10 wu + 20 min threshold + 10 cd. Why: “you haven’t done a harder run in over a week; Tuesday is far from Sunday long.”

**E. Same as D but `days_wanted = 3` and no long yet**  
Tree §7 step 7: prefer not to place quality; EasyBase. Why: “three-day weeks keep the harder effort for the long run.”

**F. Plan says rest; they want to run; tomorrow is intervals**  
Extra EasyRecovery 20–25 min. `mode: extra_on_rest_day`. Why: “easy only so tomorrow’s workout still counts.”

**G. Plan says 6×800; they have 20 min; feel ok**  
G10: cannot fit the workout. Downgrade EasyBase 18 min. Why: “not enough time to warm up and do intervals well.”

**H. Longest run in 30 days = 8 km; they want a 16 km long today**  
G6 clips to 8.8 km. Type stays long only if 8.8 ≥ 1.2× median; else EasyBase at 8.8 km cap. Why: “jumping one run more than ~10% above your recent longest is the spike that shows up in injury data.”

**I. Wrecked, 60 min free, plan is easy 45**  
G8 very_low: Rest (primary). Alternative: 20 min walk. Why: “today is for getting to tomorrow.”

---

## 13. Suggested unit tests (for the later engineer)

Pure functions, no HealthKit.

1. Quality 20 h ago + high readiness → not quality.
2. Quality 50 h ago + ok readiness + 4 days/week + not pre-long → quality allowed.
3. `days_since_any_run = 10` + user asks intervals → easy.
4. `longest_30d = 10000` → candidate 12000 clipped to 11000.
5. `time_available = 12` → rest/walk, never intervals.
6. Plan rest + insist → extra easy, not tempo.
7. Plan long today + G3 (quality 24 h ago) → easy, not long.
8. Missing all pace/HR/labels, 2 runs in 90 days → easy 20–30, `confidence: low`, talk_test pace source.
9. Feel missing ≠ feel high: unknown does not add quality.
10. Week already 1.4× 28-day average → no second long; cap distance.

---

## 14. Implementation notes (still not code)

- One function `recommendToday(input) -> Recommendation`. Classification of history can be a second function `classify(workouts) -> Session[]` used by both the picker and the planner.
- Do not call this from a SwiftUI view model with inline heuristics. Keep the tree table-driven so G-numbers stay testable.
- HealthKit: `HKWorkout` running/walking, `totalDistance`, `duration`, `averageHeartRate` via statistics query if allowed. Titles live in `metadata` or the source app; they are messy — never require them.
- Time: all “week” math is `Calendar.current` start-of-week for the user.
- Do not store ACWR as a user-facing score. If product later wants a load sentence, use Frandsen language: “this run vs your longest in 30 days.”
- Copy should sound like a coach, not a lab: “Easy 35 minutes. Yesterday was your hard day.”

---

## 15. Sources

### Product (behaviour, not algorithms)

- Runna, Instant Workouts; extra runs / parkrun; Mileage Insights. Support articles linked in §1.1.
- Garmin, Daily Suggested Workouts inputs; DSW types for runners; recovery time manuals. §1.2.
- Nike, NRC training plans help. §1.3.
- Strava, Instant Workouts help + 8 Jan 2026 press. §1.4.
- WHOOP, Recovery 101; Strain Target; Project PR locker posts. §1.5.
- TrainingPeaks, TSS help; pairing; PMC/ATL/CTL explainers; “How to Handle Missed Workouts.” §1.6.

### Science

- Seiler S. What is best practice for training intensity distribution in endurance athletes? *Int J Sports Physiol Perform.* 2010. Polarized ~80/20 observation.
- Esteve-Lanao J, et al. How do endurance runners actually train? *Med Sci Sports Exerc.* 2005 / related TID papers.
- Muñoz I, et al. Does polarized training improve performance in recreational runners? 2014 region.
- Foster C, et al. A new approach to monitoring exercise training. *J Strength Cond Res.* 2001 / session-RPE method.
- Gabbett TJ. The training–injury prevention paradox. *Br J Sports Med.* 2016;50:273–280. ACWR and 0.8–1.3 from team sport.
- Impellizzeri FM, et al. Acute:Chronic Workload Ratio: conceptual issues and fundamental pitfalls. *Int J Sports Physiol Perform.* 2020.
- Nakaoka G, Barboza SD, Verhagen E, van Mechelen W, Hespanhol L. ACWR and RRI in Dutch runners. *Sports Med.* 2021;51:2437–2447. Inverse association in recreational runners.
- Frandsen JSB, Nielsen RO, et al. How much running is too much? *Br J Sports Med.* 2025;59:1203–. Session vs 30-day longest; ACWR not the running signal.
- Buist I, et al. No effect of a graded 10% program (GRONORUN). *Am J Sports Med.* 2008.
- Nielsen RO, et al. Excessive progression in weekly running distance and RRI. *J Orthop Sports Phys Ther.* 2014;44:739–747. >30% weekly jump, some injury types.
- Mujika I, Padilla S. Detraining: loss of training-induced physiological and performance adaptations. *Sports Med.* 2000.
- ACSM. Heat and cold illnesses during distance running (position stand / related ACSM heat guidance). WBGT flag system.
- Daniels J. *Daniels’ Running Formula.* Human Kinetics. E / T / I paces from VDOT (coaching system with a research base, not an RCT).

### Coaching practice (not RCTs)

- ≥48 h between quality sessions; long run as the week’s keystone; 3-day week = easy / quality-or-easy / long; parkrun swaps for quality rather than stacking; do not make up missed hard days next to the next key session; re-entry after 8–14 days is easy first. Consistent with Pfitzinger, Daniels, Garmin DSW copy, Runna extra-run copy, TrainingPeaks missed-workout copy.

---

## 16. Open product choices (do not silently pick in code)

1. Default `days_wanted` if the user never set it: **3**.
2. Default long day: **Sunday** (Saturday if locale weekend starts Friday — keep one constant, document it).
3. Whether strides exist in v1: **no** until easy/long/rest is trusted.
4. Whether “I feel great” can ever create a quality day on a 3-day week: **no** (this spec).
5. Heat module: **off** until weather permission exists.
6. Medical disclaimer in the UI: **yes**, once, not on every card.

If a later chat implements this, start at v1 in §11, with unit tests in §13, and keep this file as the contract.

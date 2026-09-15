# Fight rules and engine notation

Status: **design direction; only Most Steps is production scope**

This document defines how FitFight can support different Metrics and different ways of competing without creating a separate implementation for every combination.

**Review, 15 Sep 2026:** the existing Measure / Score / Result model is a useful foundation. The [proposed extensions](#proposed-extensions-15-sep-2026) below add precise conditions, Stake rules, and Allocation rules. They are design proposals, not approved features, API contracts, or a payment implementation. The three-part core and its existing examples remain below for reference.

The central recommendation is to compose a small set of well-defined operations. A complete Fight must explain **what counts, over which time window, how it is scored, who succeeds or loses, who owes what, and who receives what**. A catalog of named presets can make that model approachable without exposing all its combinations in the app.

## The model

Every Fight rule has three independent parts:

```ts
{
    measure: {},
    score: {},
    result: {}
}
```

- **Measure**: what activity data to use, such as Steps, distance, active minutes, or workouts.
- **Score**: how to calculate the number shown for each member, such as total, average per day, or number of days reaching a goal.
- **Result**: what that number means for winning and losing: first wins, last loses, a goal everyone can hit, a ranked band, or proportional sharing.

Score and Result stay independent. “10,000 Steps every day” vs “10,000 Steps on average” is Score plus Reach. “Only last place pays” vs “first place wins” is Result. Do not invent a new Measure for those.

Do not create a new type for every combination. There should not be separate implementations called `daily_steps`, `daily_distance`, `average_daily_steps`, and `average_daily_distance`. Add a Measure or Score operation once, then allow only the combinations that product rules have approved.

This is dynamic configuration, not an arbitrary formula language. The server owns the allowed Measure, Score, and Result values and rejects combinations whose meaning has not been defined and tested.

## Examples

### Most steps

```ts
{
    measure: { type: "steps" },
    score: { type: "total" },
    result: { type: "highest" }
}
```

The member with the greatest number of Steps during the Fight wins.

### Most days reaching 10,000 steps

```ts
{
    measure: { type: "steps" },
    score: {
        type: "days_reaching",
        value: 10_000
    },
    result: { type: "highest" }
}
```

Each Fight day with at least 10,000 Steps adds one to the member's Score. The member with the most successful days wins.

### Reach 10,000 steps every day

```ts
{
    measure: { type: "steps" },
    score: {
        type: "days_reaching",
        value: 10_000
    },
    result: {
        type: "reach",
        value: "every_day"
    }
}
```

The Score is still the number of successful days, but success requires every Fight day to be successful.

### Reach 10,000 steps on at least five days

```ts
{
    measure: { type: "steps" },
    score: {
        type: "days_reaching",
        value: 10_000
    },
    result: {
        type: "reach",
        value: 5
    }
}
```

Anyone with at least five successful Fight days succeeds.

### Highest average Steps per day

```ts
{
    measure: { type: "steps" },
    score: { type: "average_per_day" },
    result: { type: "highest" }
}
```

The Score is total Steps divided by every scheduled Fight day. The highest average wins.

### Average at least 10,000 Steps per day

```ts
{
    measure: { type: "steps" },
    score: { type: "average_per_day" },
    result: {
        type: "reach",
        value: 10_000
    }
}
```

Anyone whose final average is at least 10,000 Steps per day succeeds.

### Last one loses (Station F tournée)

```ts
{
    measure: { type: "steps" },
    score: { type: "total" },
    result: { type: "last_loses" }
}
```

Everyone still ranks by the same Score. Only last place is on the hook. The typed action is what that person does, for example paying a _tournée_, a round of drinks, on Thursday or Friday. First place is not a special prize unless a ranking zone also marks the top.

`count` marks more than one last place. `{ type: "last_loses", count: 2 }` puts the bottom two on the hook.

This is not “lowest Score wins.” Higher Steps still rank higher. Last-loses only decides who does the action.

### Top three win

```ts
{
    measure: { type: "steps" },
    score: { type: "total" },
    result: {
        type: "highest",
        count: 3
    }
}
```

`highest` without `count` is first place only, which is today's production Fight. `count` is the podium size.

### Ranking zones (league table)

```ts
{
    measure: { type: "steps" },
    score: { type: "total" },
    result: {
        type: "ranking_zones",
        zones: [
            {
                from: 1,
                to: 3,
                outcome: "win",
                label: "Podium"
            },
            {
                from: -1,
                to: -1,
                outcome: "lose",
                label: "Last one loses"
            }
        ]
    }
}
```

Use this when more than one band matters, the way a European league table colors Champions League rows at the top and relegation at the bottom. Positive `from` / `to` are ranks from the top. Negative ranks count from the bottom: `-1` is last, `-2` is second-to-last. Zones must not overlap. Ranks that are not in a zone are still competing; they have no special outcome.

`last_loses` is the same as one lose zone on `from: -1, to: -1`. `highest` with `count: 3` is the same as one win zone on `from: 1, to: 3`.

### Most valid workouts

```ts
{
    measure: {
        type: "workouts",
        minimumMinutes: 20,
        manualWorkouts: "exclude",
        mergeOverlapping: true,
        mergeIfGapUnderMinutes: 10
    },
    score: { type: "total" },
    result: { type: "highest" }
}
```

The Score is the number of workouts that satisfy the disclosed workout rules. A two-minute workout does not count. Overlapping records are deduplicated, and nearby fragments are treated as one workout.

### Most workout days

```ts
{
    measure: {
        type: "workouts",
        minimumMinutes: 20,
        manualWorkouts: "exclude",
        mergeOverlapping: true,
        mergeIfGapUnderMinutes: 10
    },
    score: {
        type: "days_reaching",
        value: 1
    },
    result: { type: "highest" }
}
```

A Fight day counts once when it contains at least one valid workout. Splitting one day into many workouts cannot increase this Score.

## The 8,000 plus 12,000 example

For a two-day Fight in which a member records 8,000 Steps and then 12,000 Steps:

| Rule                         | Score or result      |
| ---------------------------- | -------------------- |
| Total Steps                  | 20,000 Steps         |
| Days reaching 10,000         | One successful day   |
| Reach 10,000 every day       | Failed               |
| Average Steps per day        | 10,000 Steps per day |
| Reach a 10,000 daily average | Succeeded            |

These are intentionally different games using the same underlying Steps.

## Supported combinations

Adding a Measure does not automatically authorize every Score operation. The backend keeps a reviewed compatibility list. For example:

| Measure        | Plausible Score operations                                                     |
| -------------- | ------------------------------------------------------------------------------ |
| Steps          | Total, average per day, days reaching a value, longest streak reaching a value |
| Distance       | Total, average per day, days reaching a value                                  |
| Active minutes | Total, average per day, days reaching a value                                  |
| Workouts       | Total valid workouts, average per day, days reaching a count                   |

This avoids both extremes:

- No Metric × Score explosion in the codebase
- No user-authored formulas or undefined combinations

## Rules that apply to every combination

- A Fight locks its Measure, Score, Result, versions, values, time zone, and tie rule before competition starts.
- The UI states the rule in plain language before anyone accepts.
- Standings chrome follows the Result. Do not let the client invent a different winner or loser than the server Result.
- Every Score includes its unit: Steps, Steps per day, successful days, workouts, or another explicit unit.
- A daily average divides by every scheduled Fight day, never only days containing activity.
- Missing or unsynchronized data is not silently treated as confirmed zero activity while the Fight is live.
- One member uses one selected Data source for the Fight's Measure so duplicate provider data is not added together.
- Raw activity may appear as supporting detail but never acts as an undisclosed tie-breaker.
- Workout rules reduce casual gaming but cannot prove that someone truly exercised. Provenance and verification remain visible.
- Rules and calculations are versioned so completed Fights remain reproducible.
- `last_loses` still ranks by the Score: higher Steps stay above lower Steps. It only assigns the losing outcome to last place.
- `highest.count` and `last_loses.count` cannot exceed the accepted lineup. A five-person Fight cannot have a top-six podium.
- Ranking zones cannot overlap. Unzoned ranks are competing, not an implicit win or loss.

## Standings UI

The Result decides the standings treatment. Do not invent a separate UI-only rule object. No screen yet; this is the mapping the later design should follow.

| Result                                    | Standings                                                                                                                                                         |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `highest` (first wins; everyone competes) | Today's ranked list. Little extra chrome. Moss can mark the current first place.                                                                                  |
| `highest` with `count`                    | A band on the top N, like Ligue 1 Champions League rows: one color on the qualifying ranks, then the rest of the table.                                           |
| `last_loses`                              | A labeled separator between last and second-to-last, such as “Last one loses.” Ember on the last row. The Station F tournée uses this.                            |
| `ranking_zones`                           | One band or separator per zone, using that zone's `label`. Top win bands read like European qualification rows. A bottom lose band uses the last-loses separator. |
| `reach`                                   | Succeeded or failed per member. It is not a race table.                                                                                                           |
| `proportional`                            | Share of the pot, not podium colors.                                                                                                                              |

Moss is winning / you. Ember is urgency / losing. Gold stays progress only. Do not invent a new accent family for league bands.

A two-person Fight with `highest` and a required loser action is already “first wins, last does the action.” A group Fight must say whether only last place is on the hook (`last_loses`) or the top is the story (`highest`).

## Proposed extensions, 15 Sep 2026

### Review findings

The existing examples already cover highest total, last one or last N losing, top N winning, daily averages, successful days, valid workout counts, and ranking zones. The missing pieces are:

1. **Conditions beyond reaching a minimum.** At least once, every day, at most, between two bounds, and combinations of conditions need explicit meanings.
2. **More ways to calculate a Score.** Best day, weakest day, best N days, streaks, and round wins cannot all be described by total or average.
3. **Separate winning from consequences.** A podium identifies winners; it does not decide whether they split equally, receive 50/30/20, or share by Steps. Last three losing does not say whether each owes a dinner or they jointly organize one dinner.
4. **Data requirements.** A final weekly total cannot prove that someone exercised on five different days or reached a particular intensity during one workout.
5. **Defined exceptions.** Ties, incomplete data, zero total, no qualifiers, partial days, and lineup changes affect the agreement itself.

Source check: the native creation flow in [`AppModel.swift`](../FitFight/AppModel.swift) selects Steps, `highest_total`, and an optional action. [`score-fight.ts`](../web/lib/scoring/score-fight.ts) also contains older `proportional` and `hit_your_goal` branches and informational amount calculations. Their presence does not make them current app options or a complete money model. In particular, its finalization filters incomplete members before calculating the pot; a future Stake agreement must explicitly decide whether a forfeiting member still owes their contribution. These are repository observations, not a new live-deployment audit.

### Five questions, plus the Fight context

Keep the existing scoring core and describe the consequence agreement alongside it:

| Part            | Question                                                        | Example                                                                                             |
| --------------- | --------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Measure         | What activity qualifies, with which unit and source definition? | Steps; running distance in meters; workouts lasting at least 20 active minutes                      |
| Score           | How is that activity summarized?                                | Total; average per scheduled day; successful days; best day                                         |
| Result          | Who wins, succeeds, loses, or stays unclassified?               | Top three win; bottom two lose; everyone reaching a condition succeeds                              |
| Stake rule      | Who owes what, and when?                                        | Everyone contributes EUR 10; each failed member cooks once; bottom two organize one dinner together |
| Allocation rule | Who receives the defined pool, and in what shares?              | First takes all; top three split equally; eligible members share by Steps                           |

The context contains the accepted lineup, common Fight window, Fight time zone, scheduled days, locked targets, tie rules, source completeness, final-sync cutoff, and rule versions. These cannot be inferred from a score alone.

**Proposed separation:** `proportional` currently appears as a Result rule in the approved architecture and old backend. In the expanded model, proportional sharing belongs to Allocation. A Fight could recognize first place while allocating the pool proportionally to everyone. Keep the existing API meaning intact; this proposal does not rename a live field or silently change an old Fight.

Ranking does not automatically assign a Stake. Being outside the top three is not the same as being one of the bottom two. A failed personal goal is also a different outcome from finishing last.

Evaluation order is: qualify activity, calculate Scores, determine the eligible ranking population, resolve ranks and ties, assign outcomes, calculate obligations and the pool, then allocate it. A rule must identify which population each step uses. The contributing population and the reward-eligible population can differ.

### A readable condition notation

The following is **design notation**, not JavaScript, an executable language, or a schema accepted by the server. It is intended to describe a rule precisely before a future structured representation is chosen.

```text
stepsByDay = daily(total(steps))

total(steps) >= 70_000
average(stepsByDay) >= 10_000
count_days(stepsByDay >= 10_000) >= 5
every_day(stepsByDay >= 10_000)
any_day(stepsByDay >= 20_000)
longest_streak(stepsByDay >= 8_000) >= 4
```

`daily(...)` groups only in-window activity into the scheduled Fight days. `average` divides by all scheduled days, including confirmed zero days. `count_days` counts distinct days once. `longest_streak` counts consecutive scheduled days; a confirmed failed day breaks the streak. Missing coverage leaves the affected condition unresolved rather than quietly removing a day.

Comparisons are `>`, `>=`, `<`, `<=`, and inclusive `between(lower, upper)`. Values carry units. `all(...)` means every clause must pass; `any(...)` means at least one must pass; `at_least(k, ...)` means at least k listed clauses must pass. The server would allow only reviewed, bounded compositions with a readable explanation. Users would not submit executable formulas.

Compound goals may need several summaries of one Measure, such as its average and its best day. The proposed Result would evaluate those named summaries while the UI explains each condition. This extends the existing single-Score sketch; do not force unrelated conditions into an unexplained number. Reject incompatible units, impossible counts, and contradictory bounds before acceptance.

#### Minimum and maximum need careful wording

For a fully observed, non-empty set of scheduled days:

| Intended rule               | Notation               | Meaning                              |
| --------------------------- | ---------------------- | ------------------------------------ |
| At least one big day        | `max(stepsByDay) >= X` | At least one day reaches X           |
| Never below a daily floor   | `min(stepsByDay) >= X` | Every day reaches X                  |
| Never above a daily ceiling | `max(stepsByDay) <= X` | Every day stays at or below X        |
| At least one low day        | `min(stepsByDay) <= X` | At least one day stays at or below X |

So “your minimum cannot be higher than X” literally means at least one day is at or below X. It does not impose a ceiling on every day. The builder should show the plain-language sentence, not ask a person to interpret `min` and `max`.

An empty or unknown observation set is not a successful minimum/maximum test. For workouts, “every workout lasts 20 minutes” must also require at least one workout if participation is intended; otherwise no workouts would satisfy the condition vacuously.

#### Same day versus different days

```text
all(
    average(stepsByDay) >= 8_000,
    any_day(stepsByDay >= 15_000)
)
```

This means an average of 8,000 and at least one 15,000-Step day. Neither condition implies the other.

```text
any_day(all(steps >= 10_000, workout_count >= 1))
all(any_day(steps >= 10_000), any_day(workout_count >= 1))
```

The first requires both activities on the same day; the second allows different days. The inner values refer to that day's aggregates. This multi-Measure example exceeds today's one-Measure Fight rule and remains a separate extension to review, not a hidden exception to the current architecture.

### Score operations and their evidence

| Operation               | What it answers                                | Evidence needed                                                   |
| ----------------------- | ---------------------------------------------- | ----------------------------------------------------------------- |
| Total                   | Who accumulated most over the window?          | Exact-window aggregate of an additive Metric                      |
| Average per day         | What was the daily average?                    | Exact-window total and agreed scheduled-day denominator           |
| Successful-day count    | On how many days did a condition pass?         | Complete daily values                                             |
| Best day / weakest day  | What was the maximum / minimum daily value?    | Complete daily values, including confirmed zeros                  |
| Best N days             | What is the sum of the N highest daily values? | Daily values; N distinct days; N no greater than scheduled days   |
| Longest streak          | How many consecutive days passed?              | Ordered daily conditions and completeness                         |
| Daily wins              | How many daily rounds did this member win?     | Comparable daily values for the round lineup; explicit tie points |
| Best qualifying workout | What was the best single-session value?        | Qualified, deduplicated sessions with that Metric                 |
| Improvement             | How much did the member improve on a baseline? | A locked, sufficiently complete comparable baseline window        |
| Distance from target    | Who finished closest to a target?              | Explicit unit, absolute deviation, and overshoot policy           |

Highest daily average and highest total produce the same ranking when everyone shares the same denominator. They communicate the Score differently; they are not different competitions in that case. A daily floor and a daily average are different competitions.

“Most wins” needs a scope: daily wins inside one Fight, or wins across a named set of finalized Fights. The latter is a series rule, with its own eligible rounds and tie policy. Do not count whichever historical Fights happen to be available.

Workout count, workout duration, and workout intensity are different Measures. Duration must say elapsed time or active time. Intensity must name a Metric definition, unit, and supported source; a provider score cannot be assumed comparable to another provider's score. Time above an intensity threshold needs interval data, not just a workout's average or maximum. A single peak is not evidence of sustained effort. Summing peak intensity values is not automatically meaningful.

Counting workouts requires disclosed activity filters, minimum qualifying duration, duplicate/overlap handling, fragment-merging rules, and any daily cap. Whether a qualifying workout crosses midnight or the Fight cutoff must be defined before it can score. Existing stored workout summaries and chart buckets are not proof that every proposed rule has sufficient evidence.

### Challenge catalog

All entries below are ideas for review. Names are presets over explicit rules, not new engine implementations.

| Idea                  | Precise rule                                                     | Extra decision or capability                                                |
| --------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Last two / last three | Rank total Steps descending; bottom N lose                       | Tie at the cutoff and individual versus shared action                       |
| One big day           | Reach 20,000 Steps on at least one scheduled day                 | Complete daily values                                                       |
| The daily floor       | Reach 8,000 Steps every scheduled day                            | Full-day schedule and incomplete-day policy                                 |
| Five out of seven     | Reach 10,000 Steps on at least five of seven days                | Distinct successful days                                                    |
| Best two days         | Highest sum of the best two days in the week                     | Days need not be consecutive; say so                                        |
| Consistency wins      | Highest minimum daily Steps                                      | Zero days count; complete coverage required                                 |
| Streak race           | Longest consecutive run of days reaching 8,000 Steps             | Equal streak lengths can tie; no hidden total tie-break                     |
| Daily league          | Most daily wins across seven rounds                              | Example: tied leaders each get one win; no-award rule for an all-zero round |
| Three real sessions   | At least three workouts meeting disclosed qualification rules    | Specify if two workouts on one day may count                                |
| Session peak          | At least one qualifying workout reaches intensity X              | Named intensity definition and valid peak evidence                          |
| Sustained effort      | At least one workout contains T minutes above intensity X        | Interval coverage; cumulative versus uninterrupted minutes                  |
| Stay in the band      | Daily value between L and U on at least five days                | Metric-specific suitability; missing data cannot prove a ceiling            |
| Bullseye              | Smallest absolute distance from a stated target                  | Equal undershoot/overshoot tie unless disclosed otherwise                   |
| Comeback              | Largest improvement over a locked baseline                       | Absolute or percentage improvement; zero-baseline handling                  |
| Capped contribution   | Highest sum of `min(daily_steps, 12_000)`                        | Extra Steps above the daily cap earn no extra score                         |
| Everyone carries      | Every member reaches their own locked target                     | Group `all` condition; one member cannot compensate for another             |
| Shared mountain       | Group total reaches X, with every member contributing at least Y | Group aggregation plus per-member conditions                                |
| Relay                 | Members complete assigned stages in a stated order               | Separate stage state and timestamp evidence                                 |
| Fitness bingo         | Complete any three of five declared activity conditions          | Multiple Measures and distinct-condition counting                           |
| First to the line     | First member to accumulate X after the start                     | Crossing-time evidence; synchronization arrival order never decides         |
| Season champion       | Most wins across a locked set of finalized rounds                | Series membership, canceled rounds, and shared wins                         |

A smaller Score can be better for a specific approved rule, such as deviation from a target. This does not make “fewest Steps” the default interpretation of losing, or authorize every inverse health Metric. Targets in these examples illustrate rule mechanics, not personal exercise recommendations.

Teams, multi-Measure conditions, ordered stages, first-to-finish, and seasons require more than a scalar Score for one member. Document those capabilities separately when prioritized. Do not claim the three-part scalar sketch already implements every possible game.

### Stakes: what is owed

Separate the trigger, the liable people, and the obligation:

| Agreement                                 | Stake rule                                                         |
| ----------------------------------------- | ------------------------------------------------------------------ |
| Last place cooks                          | Each selected losing member owes one stated action                 |
| Bottom three organize dinner              | The selected losing group jointly owes one dinner                  |
| Everyone puts in EUR 10                   | Each accepted contributing member owes EUR 10 to the defined pool  |
| Anyone missing their target puts in EUR 5 | Each failed member owes EUR 5; the pool size depends on the result |
| Every missed day costs EUR 1, up to EUR 5 | EUR 1 per confirmed failed scheduled day, maximum EUR 5 per member |

Action text describes the obligation. It does not supply hidden scoring logic. “Cook dinner” also needs a recipient or beneficiary group and, if relevant, an agreed due date. Multiple losing members do not imply multiple dinners unless the rule says so.

Text actions can coexist with a money agreement only if both are separately stated and accepted. Define the maximum exposure before acceptance for any variable obligation. Stake fulfillment or an external transfer is a separate event from calculating a Final result; fitness data cannot prove that a dinner happened or money changed hands.

### Allocation: who receives which share

Start with a defined pool and an explicit eligible recipient set. Then choose an allocation method:

| Method                                | Example                                                                              |
| ------------------------------------- | ------------------------------------------------------------------------------------ |
| Equal shares                          | First place takes all; tied first share; top three each get one third                |
| Rank weights                          | First / second / third get 50% / 30% / 20%                                           |
| Score weights                         | Each eligible member gets their Score divided by the total Score of eligible members |
| Equal shares among successful members | Everyone reaching their goal shares equally, regardless of excess Steps              |
| Fixed awards                          | EUR 20 for each successful member, only with an explicit funding limit               |

Winner-takes-all is equal sharing with one eligible recipient, subject to the tie policy. A top-three rank selection does not require 50/30/20; those are separate choices.

For Score weights, both numerator and denominator use the **same eligible set**. Example: if only the top two qualify, their shares divide by the sum of those two Scores, not the whole group's Steps. A target-deviation Score where smaller is better cannot be plugged into proportional sharing without a separately reviewed weight definition.

#### Worked example: the same Steps, different agreements

Four members contribute EUR 10 each. Their final Steps are A = 40,000, B = 30,000, C = 20,000, D = 10,000. The pool is EUR 40.

| Allocation               | A         | B         | C     | D     |
| ------------------------ | --------- | --------- | ----- | ----- |
| First takes all          | EUR 40    | EUR 0     | EUR 0 | EUR 0 |
| Top three split 50/30/20 | EUR 20    | EUR 12    | EUR 8 | EUR 0 |
| All share by Steps       | EUR 16    | EUR 12    | EUR 8 | EUR 4 |
| Top two share by Steps   | EUR 22.86 | EUR 17.14 | EUR 0 | EUR 0 |

The table shows gross allocations. Under “all share by Steps,” net outcomes after each EUR 10 contribution are +6, +2, -2, and -6. A percentage of the pool is not the same as profit. Every row allocates exactly EUR 40.

For integer minor units, proposed Score-weight rounding is largest remainder: round shares down, then assign remaining cents in descending fractional-remainder order, with a stable disclosed ordering for equal remainders. That last-cent ordering must never turn a tied sporting result into a win or loss.

For rank weights, a proposed tie policy pools the awards for the occupied positions and shares them equally. If A and B tie first in a 50/30/20 allocation, they each get 40% and C gets 20%. If C and D tie at the third-place boundary, they each get 10%. This deliberately allows more than three recipients; an exact-three rule needs a different, accepted tie-break.

#### Conditions that cannot be left implicit

- No eligible recipients or zero eligible weight: proposed default is to return each contribution to its contributor, or cancel the obligation if not yet transferred. Equal splitting is a different rule that must be explicit.
- Rank percentages must total 100% of the allocated pool. If only part is awarded, name the destination of the remainder. Fewer eligible members than prize positions also needs an explicit unused-award rule. There is no hidden fee or unassigned money.
- Fixed awards require enough committed funding for the maximum allowed qualifiers, or a disclosed cap/proration rule. A scoring operation cannot invent funds.
- A participant can owe a contribution while being ineligible for a reward. Withdrawal, forfeiture, or missing sync must not silently erase liability.
- Late joins can alter ranks, recipient sets, and per-person-funded pool size. Their eligibility and liability must follow the accepted terms. A fixed-budget award cannot admit unlimited new claims.
- Cancellation needs its own contribution-return and action-cancellation rule. A repeating Fight must say whether each round has a separate pool and obligation; no automatic carryover.

All money examples are future agreement calculations. Actual collection, custody, transfers, and dispute handling remain outside this proposal and subject to the existing [money boundary](system-design.md#money-boundary).

### One complete example in proposed notation

```yaml
# Explanatory notation only. This is not a current API payload.
window: seven full calendar days in Europe/Paris
lineup: four accepted members, fixed before start
measure: steps
score: total
result:
    ranking_population: accepted members eligible for awards
    ranking: descending
    win: top 3 positions, including boundary ties
    lose: no losing group
stake:
    contributors: all accepted members
    amount_each: { currency: EUR, minor_units: 1000 }
allocation:
    recipients: winning group
    method: rank weights
    weights: [50, 30, 20]
    ties: pool occupied-position awards and share equally
    rounding: largest remainder, equal remainders by stable member ID
    unoccupied_prize_positions: return their awards equally to the four contributors
    no_eligible_recipients: return contributions
exceptions:
    all_eligible_scores_zero: no awards, return contributions
    incomplete_at_final_sync_deadline: ineligible for award, contribution still owed
    withdrawal: ineligible for award, contribution still owed
    cancellation: cancel obligations and return contributions
finalization:
    grace: 24 hours after the activity window closes
    freeze: input revision, member eligibility, rules and calculation versions
```

This example intentionally fixes a four-member lineup to make the agreement complete. It is not a proposal to remove late joining from today's Steps Fights. Its Stake and exception choices are examples to review, not adopted product defaults.

For example, if only two members remain eligible and do not tie, they receive EUR 20 and EUR 12. The unused EUR 8 third-place award returns EUR 2 to each original contributor. Awards plus returns still equal the original EUR 40 pool. The same rounding policy applies to returns.

### Time, missing data, and ties are part of the rule

**Daily schedules:** proposed first version of daily-goal presets uses full calendar days in the Fight time zone. A partial first or last day needs an explicit include/exclude/prorate policy before support. “One week” should resolve to actual scheduled dates, not silently mean elapsed hours divided by 24. Daylight-saving changes do not create a missing or additional calendar day.

**Unknown is not zero:** no accessible data cannot prove zero activity, a rest day, a ceiling, or success. Conditions can be unresolved while syncing. For the simple additive Steps model, additional data can improve a minimum-threshold result; it can overturn a ceiling result. Corrections and deletions can change either. Finalize only under the agreed completeness and cutoff policy, and keep provisional results labeled.

**Tie groups:** a tie at the top-three or bottom-two cutoff may select more people than the nominal count. Recommend including the whole tied group for a new preset unless an explicit sporting tie-break is chosen. For Scores [100, 80, 80, 60], bottom two with boundary ties selects both 80s and the 60. Competition ranks [1, 2, 2, 4] alone are insufficient to implement “second from bottom.”

**Overlapping outcomes:** top and bottom zones that were disjoint before expanding ties can overlap afterward. A preset must reject that possibility or specify a neutral/draw resolution. Never silently assign both winning and losing outcomes to the same member.

**Targets and qualification:** personal targets stay locked and visible as already defined in the architecture. Ranking people by percentage of a freely chosen target rewards choosing an easy target. Use personal targets for success/failure unless a separate baseline/handicap policy makes competitive comparison meaningful. A qualification condition, such as “at least three valid workouts to be eligible for the podium,” is separate from the Score used to rank qualifiers.

**Existing finalization:** current source forfeits incomplete members and makes an all-incomplete Fight a draw. It does not implement a universal missing-data rule for ceilings, group goals, daily wins, or money. Preserve existing Steps behavior until a separately approved change and compatibility rollout.

### Stress tests before a preset is implemented

| Scenario                                              | Expected interpretation                                                                   |
| ----------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Daily Steps [8,000, 12,000]                           | Average 10,000 succeeds; every day at least 10,000 fails; one qualifying day              |
| Daily Steps [0, 20,000]                               | Average 10,000 succeeds; daily floor fails; best day is 20,000                            |
| Daily Steps [unknown, 20,000]                         | Daily average/floor/ceiling cannot be declared final from these inputs                    |
| Days [8,000, 8,000, 0, 8,000] with target 8,000       | Three successful days; longest streak two                                                 |
| Three valid workouts on one day                       | Workout count three; successful workout days one                                          |
| No workouts                                           | A rule requiring at least one qualifying workout fails; unknown coverage stays unresolved |
| Equal total Steps, different day distributions        | Total ranking ties; daily-win and successful-day rankings may differ                      |
| Ten Steps for A, twenty for B, only B reward-eligible | Proportional allocation gives B 100%, not two thirds                                      |
| EUR 40 pool, tied first under 50/30/20                | EUR 16 each to the tied first pair, EUR 8 to third                                        |
| Nobody reaches the target                             | Empty recipient rule applies; no divide-by-zero or invented winner                        |
| One member joins late or withdraws                    | Re-evaluate eligibility and obligations under the locked terms                            |
| Goal-crossing data arrives out of order               | Use qualified activity time if supported; never upload arrival order                      |

### Recommendation for the future builder

Offer named presets first, with one sentence explaining the agreement and a worked miniature example. Advanced configuration can expose the same reviewed operations later. A natural-language builder should propose a structured rule and ask the creator to resolve ambiguity before anyone accepts it.

Keep a small scoring-module interface: locked terms plus eligible activity evidence and lineup produce Scores, outcomes, obligations, allocations, completeness, and explanations. Payment execution and action fulfillment stay separate from that calculation. Store enough rule/version/input-revision evidence to reproduce the result, within the existing data-retention and deletion rules.

Before implementing each preset, settle its metric/source definition, schedule, predicates, qualifying population, tie behavior, incomplete-data policy, and any Stake/Allocation exceptions. Add only the evidence and operations needed for that preset. Money, teams, multiple Measures, stages, and series each need their own reviewed specification when prioritized.

## Executable Zod draft

The full definition is [`fight-rules-draft.ts`](../web/lib/types/fights/fight-rules-draft.ts). It exports `fightRulesDraftSchema` and its inferred `FightRulesDraft` type. It uses the repository's Zod 3 dependency and is not imported by an application route, native model, or scoring engine.

This supersedes the earlier limited Zod sketch. The original three-part examples above remain shorthand descriptions, not payloads accepted by this expanded schema. `schemaVersion: 1` versions the draft notation; it does not change the current API version or any installed app contract.

### What the draft contains

| Field                | Meaning                                                                                                    |
| -------------------- | ---------------------------------------------------------------------------------------------------------- |
| `window`, `lateJoin` | Exact dates, Fight time zone, partial-day policy, scheduled-day average denominator, and late-entry policy |
| `personalTargets`    | Named target units and allowed bounds; actual values are chosen and locked by each member separately       |
| `measures`           | Named, versioned Metric definitions, units, source policy, and explicit workout qualification when needed  |
| `scores`             | Named calculations over member or group activity                                                           |
| `conditions`         | Comparisons, inclusive ranges, `all`, `any`, `at_least`, and conditions quantified over members            |
| `result`             | Ranking direction and zones, or individual/collective goal success                                         |
| `stake`              | Zero or more action obligations, plus an optional money contribution agreement                             |
| `allocation`         | Recipient selection, equal/rank/Score/fixed awards, rounding, and unused-fund rules                        |
| `finalization`       | Grace, incomplete data, all-zero/all-incomplete cases, withdrawal, and cancellation                        |

A measured Score has two calculation steps: `withinBucket` obtains a value for each Fight/day/workout bucket, then `reduction` combines those values. For example:

| Score               | Buckets | Within each bucket                                                         | Reduction                         | Unit            |
| ------------------- | ------- | -------------------------------------------------------------------------- | --------------------------------- | --------------- |
| Total Steps         | Fight   | Total Steps                                                                | Total                             | `steps`         |
| Daily average       | Day     | Total Steps                                                                | Average across scheduled days     | `steps_per_day` |
| Best day            | Day     | Total Steps                                                                | Maximum                           | `steps`         |
| Successful days     | Day     | Total Steps                                                                | Count values matching a threshold | `days`          |
| Longest streak      | Day     | Total Steps                                                                | Longest consecutive matching run  | `days`          |
| Workout days        | Day     | Total qualified workout count                                              | Count days with at least one      | `days`          |
| Sustained intensity | Workout | Minutes matching the intensity condition, cumulative or longest contiguous | Maximum                           | `minutes`       |

`deviation` and `improvement` can refer to another Score. Logical conditions refer to other named conditions. References may appear in any order, but missing references and cycles are rejected. No field accepts executable code.

### Example: average 8,000 and one 15,000-Step day

This excerpt assumes a Measure named `steps` with unit `steps`, plus the window and policies described above. Complete parseable agreements are in the [schema examples and tests](../web/lib/domain/fights/fight-rules-draft.test.ts).

```ts
const goal: Pick<FightRulesDraft, "scores" | "conditions" | "result"> = {
    scores: [
        {
            id: "daily_average",
            type: "measured",
            measureId: "steps",
            subject: "member",
            buckets: "day",
            withinBucket: { type: "aggregate", operation: "total" },
            reduction: { type: "aggregate", operation: "average" },
            unit: "steps_per_day",
        },
        {
            id: "best_day",
            type: "measured",
            measureId: "steps",
            subject: "member",
            buckets: "day",
            withinBucket: { type: "aggregate", operation: "total" },
            reduction: { type: "aggregate", operation: "maximum" },
            unit: "steps",
        },
    ],
    conditions: [
        {
            id: "average_met",
            type: "comparison",
            scoreId: "daily_average",
            comparison: {
                type: "threshold",
                unit: "steps_per_day",
                operator: "gte",
                target: { type: "fixed", value: 8000 },
            },
        },
        {
            id: "big_day_met",
            type: "comparison",
            scoreId: "best_day",
            comparison: {
                type: "threshold",
                unit: "steps",
                operator: "gte",
                target: { type: "fixed", value: 15000 },
            },
        },
        {
            id: "both_met",
            type: "all",
            conditionIds: ["average_met", "big_day_met"],
        },
    ],
    result: { type: "goal", conditionId: "both_met", scope: "each_member" },
};
```

### Explicit semantics

- Metric definition identifiers in the examples are illustrative references. A future approved-definition registry must resolve them; naming one does not implement that Metric or prove provider support.
- A `group` Score combines eligible group activity before bucketing. A `members` condition lifts a per-member condition into a group condition, such as everyone contributing at least 10,000 Steps. This allows a group total and an every-member minimum to be combined without mixing their scopes.
- `withinBucket.count`, written as `{ type: "aggregate", operation: "count" }`, counts canonical observations, not arbitrary provider records. Workout count normally uses a qualified-workout Metric whose values total to a number of workouts.
- `time_matching` requires interval coverage in the chosen Metric definition. No interpolation across unknown gaps, conversion from peak intensity, or assumption about a provider's intensity scale is implied.
- Rank positions are one-based and count from the stated `top` or `bottom` edge. Shared ties include the whole tied group. Overlapping outcome zones resolve to neutral, meaning no special win/lose/safe outcome.
- Rank-weight allocations order the selected recipients by the Fight's ranking and pool awards across occupied tied positions. `basisPoints: [5000, 3000, 2000]` means 50%, 30%, 20%. Score-weight allocations always use the selected recipient set in both numerator and denominator.
- Unused money returns proportionally to the original contributions, which is an equal return when contributions were equal. Money and an Allocation must be provided together.
- Variable contributions currently use integer counts of matching days or workouts and require an explicit maximum amount per member. Action text never becomes an executable rule.
- `allIncomplete: "draw_cancel_obligations"` and cancellation override ordinary forfeit/withdrawal liability. These are explicit proposed policies, not changes to existing Steps finalization.

### What parsing proves, and what it does not

Parsing checks strict object shapes, finite values, integer money, named references, cycles, unit consistency, member/group scope, target bounds, allowed outcome selections, and rank percentages totaling 100%. The examples exercise Most Steps, compound goals, shared group goals, bottom-three actions, workout days, intensity duration, baseline improvement, and several prize allocations.

Before a future engine accepts a parsed draft, it still needs the actual lineup, member-selected targets, the approved Metric/operation compatibility list, provider evidence, and the schedule:

- Resolve Metric definitions and confirm declared units, comparable sources, nonnegative proportional weights, and meaningful operations. A syntactically valid total of peak intensities is not automatically an approved Score.
- Construct scheduled calendar buckets in the Fight time zone, enforce the chosen partial-day policy, and reject impossible day/member/rank counts.
- Validate actual target selections, baseline comparability and coverage, invitation/withdrawal eligibility, and sufficient award funding.
- Apply complete/unknown/zero distinctions, rule locking, result explanations, and reproducible finalization. Parsing does not calculate or settle a Fight.

The draft represents single-round member and group agreements. Same-day compound conditions across multiple Measures, team membership, ordered relays, crossing-time races, and multi-round seasons still need dedicated definitions. Their absence is explicit; there is no arbitrary formula escape hatch pretending to implement them.

## Current scope

The current production Fight is equivalent to:

```ts
{
    version: 1,
    measure: { type: "steps" },
    score: { type: "total" },
    result: { type: "highest" }
}
```

Do not implement the other examples until they are moved into the backlog and approved for production. `last_loses`, `highest.count`, and `ranking_zones` are specified here so a later Advanced form or natural-language parse can fill them. They are not production scope.

# Fight rules

Status: **design direction; only Most Steps is production scope**

This document defines how FitFight can support different Metrics and different ways of competing without creating a separate implementation for every combination.

## The model

Every Fight rule has three independent parts:

```ts
{
  measure: {},
  score: {},
  result: {}
}
```

- **Measure** — what activity data to use, such as Steps, distance, active minutes, or workouts.
- **Score** — how to calculate the number shown for each member, such as total, average per day, or number of days reaching a goal.
- **Result** — what that number means, such as highest wins, reach a stated value, or proportional sharing.

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

| Rule | Score or result |
| --- | --- |
| Total Steps | 20,000 Steps |
| Days reaching 10,000 | One successful day |
| Reach 10,000 every day | Failed |
| Average Steps per day | 10,000 Steps per day |
| Reach a 10,000 daily average | Succeeded |

These are intentionally different games using the same underlying Steps.

## Supported combinations

Adding a Measure does not automatically authorize every Score operation. The backend keeps a reviewed compatibility list. For example:

| Measure | Plausible Score operations |
| --- | --- |
| Steps | Total, average per day, days reaching a value, longest streak reaching a value |
| Distance | Total, average per day, days reaching a value |
| Active minutes | Total, average per day, days reaching a value |
| Workouts | Total valid workouts, average per day, days reaching a count |

This avoids both extremes:

- No Metric × Score explosion in the codebase
- No user-authored formulas or undefined combinations

## Rules that apply to every combination

- A Fight locks its Measure, Score, Result, versions, values, time zone, and tie rule before competition starts.
- The UI states the rule in plain language before anyone accepts.
- Every Score includes its unit: Steps, Steps per day, successful days, workouts, or another explicit unit.
- A daily average divides by every scheduled Fight day, never only days containing activity.
- Missing or unsynchronized data is not silently treated as confirmed zero activity while the Fight is live.
- One member uses one selected Data source for the Fight's Measure so duplicate provider data is not added together.
- Raw activity may appear as supporting detail but never acts as an undisclosed tie-breaker.
- Workout rules reduce casual gaming but cannot prove that someone truly exercised. Provenance and verification remain visible.
- Rules and calculations are versioned so completed Fights remain reproducible.

## Draft Zod shape

This is an engineering sketch, not production code. It validates the object shape; the server's compatibility list performs the product-level validation of allowed combinations.

```ts
import { z } from "zod";

const measureSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("steps")
  }).strict(),

  z.object({
    type: z.literal("distance"),
    sport: z.string().min(1).optional(),
    unit: z.enum(["meters", "kilometers"])
  }).strict(),

  z.object({
    type: z.literal("active_minutes")
  }).strict(),

  z.object({
    type: z.literal("workouts"),
    minimumMinutes: z.number().int().positive(),
    manualWorkouts: z.enum(["include", "exclude"]),
    mergeOverlapping: z.boolean(),
    mergeIfGapUnderMinutes: z.number().int().nonnegative()
  }).strict()
]);

const scoreSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("total")
  }).strict(),

  z.object({
    type: z.literal("average_per_day")
  }).strict(),

  z.object({
    type: z.literal("days_reaching"),
    value: z.number().nonnegative()
  }).strict(),

  z.object({
    type: z.literal("longest_streak_reaching"),
    value: z.number().nonnegative()
  }).strict()
]);

const resultSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("highest")
  }).strict(),

  z.object({
    type: z.literal("reach"),
    value: z.union([
      z.number().nonnegative(),
      z.literal("every_day")
    ])
  }).strict(),

  z.object({
    type: z.literal("proportional")
  }).strict()
]);

export const fightRuleSchema = z.object({
  version: z.literal(1),
  measure: measureSchema,
  score: scoreSchema,
  result: resultSchema
}).strict();

export type FightRule = z.infer<typeof fightRuleSchema>;
```

Some relationships need validation with Fight context rather than object shape alone. Examples: `every_day` requires a day-based Score; a five-day goal cannot exceed a three-day Fight; a Score operation must be approved for its Measure; and every numeric target must use the Score's derived unit.

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

Do not implement the other examples until they are moved into the backlog and approved for production.

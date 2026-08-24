# Types, layers, SoD

**SoD** = Source of Data. Every numeric fact from L1 up carries one. **Zod** validates the TypeScript/Vercel side (same word on a phone keyboard). Swift `Codable` mirrors the wire. Views never take L0.

## SoD

```ts
export const SodSchema = z.enum([
  "healthkit",
  "strava",
  "scale",
  "manual",
  "derived",
  "user",
  "system",
]);
```

| Value | Meaning |
| --- | --- |
| `healthkit` / `strava` / `scale` | Origin device/API |
| `manual` | Typed sample (not in v1 scoring) |
| `user` | Intent: name, buy-in, goal |
| `system` | Server-made: fight code, ids |
| `derived` | Any computed number: day sum, rank, today, net, pot |

`user` ≠ `manual`. A handle is `user`. A typed step count would be `manual`.

## Units

Integers only on the wire.

| Metric | Canonical | Display |
| --- | --- | --- |
| steps | step | `61.4k` |
| active minutes | **second** | minutes, whole |
| workouts | count | integer |
| money | **cents**, ISO currency | `$10` |
| mass later | gram | kg, 1 decimal |

Do not store “display minutes” as the source of truth. Convert at L5.

## Layers

```
L0 raw          vendor payload on the ingest wire only — not a JSONB column
L1 canonical    metric_samples row, one unit, SoD = origin, deduped
L2 daily        (user, metric, civil date, tz) total SoD=derived — computed, not stored
L3 fight days   L2 clipped to fight window + fight tz — stored
L4 standing     rank, today, net, safe — iOS derives from PostgREST L3
L5 view         "12 min behind Leo" — iOS only
```

iOS captures L0 (HealthKit encode) and maps L3/L4 → L5. Vercel persists L1 and writes L3. Postgres stores L1 samples + L3 days + fight rows. No raw vendor JSON in the database. Vercel `/api/v1` envelopes are for ingest/wake; fight reads are PostgREST + Realtime (snake_case).

### What must not happen

- SwiftUI decoding PostgREST `metric_samples`
- English kickers in JSON
- Averaging HealthKit + Strava
- `rank: 0` for invited people — use `null`
- `today: 0` meaning “not in the fight”
- UTC midnight as a fight day
- iOS recomputing net as product truth (debug assert only)

## Quantity

```ts
export const QuantityV1Schema = z.object({
  amount: z.number().int(),
  unit: z.enum(["step", "second", "count", "gram"]),
  sod: SodSchema,
});

export const MoneyV1Schema = z.object({
  cents: z.number().int(),
  currency: z.string().length(3),
  sod: SodSchema,
});
```

Naked `number` stops at L0 vendor JSON.

## Wire (L4)

Envelope:

```ts
{
  api: "v1",
  viewerUserId: UserId,
  asOf: Instant,       // ISO offset
  staleAfter: Instant,
  data: T,
  warnings?: WireErrorV1[]
}
```

`isYou` is never on the wire. Client: `person.id === viewerUserId`.

Fight (abbrev): ids, code, name, metric, frozen `timezone`, civil `start`/`end`, `lifecycle`, `myMembership`, `buyIn` (sod user), `pot` (sod derived), `settlement`, `dailyGoal?`, counts, `myRank?`, `standings[]`, `days[]` (accepted members’ daily totals), `sync` watermarks.

Standing: `score?`, `rank?` (null if invited), `today?` (derived, fight civil today), `net?` `{ money, phase: projected|final, formula }`, `safety?` (goal only).

**Today** is L2 for `(user, fight.metric, fightCivilToday, fight.timezone)`, not the phone calendar.

**Net** replaces `projectedNet`. Same field after freeze with `phase: "final"`.

## L5 (iOS)

`FightCardVM` holds kicker prefix/emphasis/rest, list subtitle, payout line, invite pitch, `61.4k`, `+$20`. Produced by `FightCopy` from L4. Design experiments call the same functions.

Map of today’s `AppModel.Fight`:

| Now | Layer |
| --- | --- |
| id, code, name, metric, lengthDays | L4 |
| daysLeft, endedLabel | L5 from end + asOf |
| pot, buyIn | L4 Money |
| kicker*, listSubtitle, payoutLine, invitePitch | L5 |
| standings.score / today / projectedNet | L4 derived |
| Person.isYou | comparison |
| Person.photo asset name | L5 |

## Remote state

```ts
type Remote<T> =
  | { status: "idle" }
  | { status: "loading"; previous?: T }
  | { status: "ready"; data: T; asOf: string; stale: boolean }
  | { status: "empty"; reason: "no_fights" | "no_samples" | "not_joined" }
  | { status: "error"; error: AppError; previous?: T };
```

Loading ≠ empty ≠ zero score ≠ stale.

## Versioning

- `/v1/` + `api: "v1"`. Additive optional fields stay on v1. Clients strip unknown keys.
- New required field, unit change, or meaning change → `/v2/`. Never reuse `projectedNet` dollars as cents.
- Ingest envelope is **strict**. Vendor `payload` is opaque.
- Fixtures: `packages/contracts/fixtures/v1/*.json` parsed by Zod in CI. Swift tests decode the same files when those tests exist.

Hand-mirror Swift until two production decode failures or ~25 objects. Then OpenAPI → generator.

## Naming

| World | Case |
| --- | --- |
| Postgres / PostgREST | snake_case |
| Vercel `/api/v1` JSON | camelCase |
| Swift domain | camelCase `Fight`, `Standing` |

One mapper at the PostgREST client. Do not camelCase the database.

# Types and source of data (SoD)

Every value in the app came from somewhere. Stamp that. Do not let a view invent a number that looks like HealthKit.

SoD = **source of data**, not “system of record.” System of record is the next table.

## Systems of record

| Fact | SoR | May cache on phone |
| --- | --- | --- |
| Body (steps, workouts) | HealthKit | Daily totals for live/grace fights only |
| Fight window, members, rules | Server Postgres | `cache_fight` / `cache_membership` |
| Accepted daily scores | Server `score_days` | `cache_score_day` |
| Settlement, IOUs | Server, once | `cache_settlement` immutable |
| Session | Our refresh token (Keychain) | never iCloud |
| Look / design variant | `UserDefaults` | yes |
| Formatted copy | Presenter (ephemeral) | no |

## SoD enum

```swift
enum SourceOfData: String, Codable, Sendable, Hashable {
    case healthKit
    case strava          // later; not a second addend if already in HK
    case connectedScale  // later dual-challenge
    case manual          // not a scoring source in v1
    case server
    case fixture
    case derived         // projections only
}

struct SourceCite: Hashable, Sendable {
    var sources: Set<SourceOfData>   // never empty on an aggregate
}
```

| Layer | Allowed SoD |
| --- | --- |
| External raw | Implicit (HK / Strava / HTTP). Do not stamp vendor types. |
| Ingress DTO | `healthKit` \| `strava` \| `server` \| `fixture` |
| Canonical sample | `healthKit` \| `strava` \| `manual` \| `fixture` — **not** `server`, **not** `derived` |
| Aggregate (`DailyScore`) | Union of contributing samples |
| Domain fight / member / ledger | `server` \| `fixture` |
| Projection | always `derived` + optional cite of sample sources |
| Presentation | none (may show a badge from the cite) |

A `Fight` does **not** inherit HealthKit SoD. Its scores were built from samples that had SoD. Projection carries the cite for “You → Data sources” and for the double-count bug.

## Layers (raw → UI)

```
Views  →  Presentation (FightPresented, formatters)
              →  Projection (pace, money-if-unchanged, rank, SAFE)
                  →  Domain (Fight, Member, Stake, SettlementRule)
                      ↑
         Aggregates ← CanonicalSample ← Ingress DTO ← External raw
```

Dependencies point **inward**. Core (domain + projection + presenter) imports Foundation only. HealthKit and URLSession live in adapters.

### 0. External raw

Not ours. Not `Codable` into the app.

- `HKQuantitySample`, `HKWorkout`, `HKStatistics`
- Strava JSON `Data` (later)
- HTTP body `Data`

### 1. Ingress DTOs

Dumb, 1:1 with the wire. Mapping only to canonical samples or domain snapshots.

```swift
struct ScoreBatchDTO: Codable, Sendable {
    var fightId: FightID
    var compiledAt: Date
    var source: SourceOfData          // .healthKit
    var fingerprint: String           // hash of contributing HK sources, not sample UUIDs
    var days: [ScoreDayDTO]           // local_date in fight TZ, integer value
}

struct FightSnapshotDTO: Codable, Sendable {
    var fight: FightDTO
    var members: [MemberDTO]
    var scoreDays: [ScoreDayDTO]
    var settlement: SettlementDTO?
    var serverTime: Date
}
```

Never DTO → view.

### 2. Canonical samples (device, short-lived)

Used to compile a day. **Not** stored in GRDB, **not** uploaded.

Identity for workouts: `(source, foreignID)` first (`HKWorkout.uuid`). Fallback overlap window is how you merge a Strava HK write with a Watch HK write — you still upload **one** day total, not both.

### 3. Aggregates

```swift
struct DailyScore: Hashable, Sendable {
    var userId: UserID
    var day: FightDay          // yyyy-MM-dd in fight TZ
    var value: MetricValue     // integer, unit from metric
    var cite: SourceCite
    var compiledAt: Date
}
```

Authoritative fight scores = **server** aggregates after ingest. Phone aggregate is preview until ACK + refetch.

### 4. Domain

No formatted strings. No `daysLeft`. No rank.

```swift
struct FightID: Hashable, Codable, RawRepresentable { var rawValue: String }
struct UserID: Hashable, Codable, RawRepresentable { var rawValue: String }
struct FightDay: Hashable, Codable, RawRepresentable { var rawValue: String } // yyyy-MM-dd

struct Money: Hashable, Sendable {
    var cents: Int64
    var currency: String       // "USD"
}

enum MetricValue: Hashable, Sendable {
    case steps(Int64)
    case seconds(Int64)        // active minutes stored as seconds
    case count(Int64)          // workouts
    case grams(Int64)          // later mass
}

struct Fight: Hashable, Sendable {
    var id: FightID
    var publicCode: String
    var name: String
    var metric: MetricKind
    var rulesVersion: Int
    var timeZone: String       // IANA
    var window: FightWindow    // instants + civil start/end
    var graceUntil: Date
    var status: FightStatus    // scheduled, live, grace, settled, cancelled
    var stake: Stake
    var settlement: SettlementKind
    var dailyGoal: MetricValue?
    var seriesId: SeriesID?
}

enum Stake: Hashable, Sendable {
    case none
    case money(buyIn: Money)
    case action(text: String)
}

enum FightStatus: String, Sendable {
    case scheduled, live, grace, settled, cancelled
}

struct Member: Hashable, Sendable {
    var userId: UserID
    var role: MemberRole       // racer (v1)
    var status: MemberStatus   // invited, accepted, declined, left, kicked
    var buyIn: Money
}

struct LedgerEntry: Hashable, Sendable {
    var from: UserID
    var to: UserID
    var amount: Money
    var fightId: FightID
    var status: ObligationStatus
}
```

Phone **does not create** ledger rows. Preview money is projection.

### 5. Projection

Pure functions. Clock in. **Not persisted.**

| Question | Function | UI |
| --- | --- | --- |
| Money if nothing changes | Freeze current scores, `SettlementEngine.preview` | `projectedNet`, “if nothing changes” |
| Pace | `score × length / elapsed` | “on pace for 98 min” |
| Rank / SAFE | from scores + goal rule | badges |

`daysLeft` uses `server_time` offset, not the device clock as truth.

### 6. Presentation

What the eleven Fights designs already read. Today’s `Fight` **is** this layer. Rename toward `FightPresented` when the façade lands; until then a typealias is enough.

Contains: kickers, `listSubtitle`, `payoutLine`, `invitePitch`, formatted scores (`61.4k`), `ago` strings.

**Golden tests** pin copy for the six fixture fights so a presenter change cannot silently rewrite the mock.

## Field map (today → tomorrow)

| `AppModel.Fight` today | Layer |
| --- | --- |
| `id`, `name`, `metric`, `lengthDays`, `buyIn`, `settlement`, `dailyGoal` | domain |
| `code` | domain `publicCode` (generator changes) |
| `pot` | projection from memberships |
| `daysLeft`, `endedLabel`, `rank`, `of`, `pending` | projection |
| `kicker*`, `listSubtitle`, `payoutLine`, `invitePitch`, `paceNote`, `standingsMeta` | presentation |
| `standings[].score` / `today` | aggregate |
| `standings[].projectedNet` / `safe` | projection |
| `standings[].invited` | domain member status |
| `days[]` | aggregates by `FightDay` |
| `RequestItem.ago` | presentation |
| `HistoryItem.detail` | presentation from settled fight |

## Dedup

Happens at **canonical ingest**, not in a view.

Policy: **HealthKit is the merge plane.** If HK already contains the Strava workout, do not ingest Strava again. `HKStatisticsQuery` merges overlapping **quantity** sources; it does **not** merge `HKWorkout`. Workouts need identity (uuid / overlap). See [`ingest.md`](ingest.md).

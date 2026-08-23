# FitFight type layers

Target: 6–9 months, HealthKit + a server, same screens. Cloud agents build this on Linux; CI compiles iOS. The phone shows state. The server owns the clock, settlement, and money.

Today: `AppModel` is a fixture bag. `Fight` already is a **presentation** type (kicker, `payoutLine`, `listSubtitle`). Domain maths leak into views (`ringProgress`, `projectedPace`, `safe`). Stop that by splitting types, not by adding a framework.

## Verdict

| Choice | Pick | Why |
| --- | --- | --- |
| Observation | **`@Observable` + `@MainActor` stores**, protocols for I/O | Least glue. Agents write it without inventing a runtime. |
| TCA | **No** | Reducers + `Sendable` ceremony; Linux cannot compile the app to catch it; 11 design variants would all grow reducers. |
| SwiftData | **No as architecture.** Maybe later as a private cache behind `SampleStore` | Domain is not a `@Model`. HK samples, API snapshots, and `Fight` have different lifetimes. Schema migrations are a tax this app does not need until offline query of months of samples hurts. |
| Persistence now | **Server snapshots + fixture memory.** `UserDefaults` only for look (`ff.design`, theme). | Product rule: server does the work. |
| Money | **`Money` in minor units (`Int` cents, USD)** | Never `Double`. Today's whole dollars are `cents = dollars * 100`. |
| IDs | **Named string-backed structs** (`FightID`, not `UUID`, not `ID<Tag>`) | Fixtures are `"sweat"`. Server will be strings. Phantom generics get copy-pasted wrong. |
| Packages | **One Foundation package `FitFightCore`**, adapters stay in the iOS target until they need their own tests | Linux `swift test` for settlement and presenters. HealthKit cannot live in that package. |

Do not rewrite the eleven Fights designs in the first PR. They keep reading one model. That model becomes a **facade over presented fights**.

## Dependency rule

Arrows mean “imports / calls”. They point **inward**.

```
SwiftUI views  →  Presentation (FightPresented, formatters)
                      ↓
                 Projection (pace, money-if-unchanged, rank)
                      ↓
                 Domain (Fight, Member, Ledger, SettlementRule)
                      ↑
                 Aggregates ← CanonicalSample ← Ingress DTO ← External raw

Repository protocols live in Core.
Fixture / API / HealthKit implement them and depend on Core.
Core imports Foundation only. Never SwiftUI, HealthKit, UIKit, or Ingress types.
```

**Forbidden**

- View or design variant applies settlement, rank, pace, or “safe / at risk”.
- Domain `Fight` stores `payoutLine`, kickers, or `endedLabel`.
- Canonical samples know about fights (membership is domain).
- Domain imports an Ingress DTO or an `HKQuantitySample`.
- A HealthKit SoD stamped onto a `Fight` or a `LedgerEntry`.
- Phone writes a real `LedgerEntry`. Preview deltas are projection, not ledger.

**SoD flows with the bytes, never backwards.** A fight is `.server` or `.fixture`. Its scores were *built from* samples that had SoD; the fight does not inherit them. Projection carries a **cite** of which sample sources fed the numbers, for the You → Data sources row and the double-count bug.

## Source of Data

```swift
enum SourceOfData: String, Codable, Sendable, Hashable {
    case healthKit
    case strava
    case manual
    case server
    case fixture
    case derived
}
```

| Layer | SoD allowed |
| --- | --- |
| External raw | Implicit (the module). Do not stamp HK types. |
| Ingress DTO | `healthKit` \| `strava` \| `server` \| `fixture` |
| Canonical sample | `healthKit` \| `strava` \| `manual` \| `fixture` — **not** `server`, **not** `derived` |
| Aggregate | Union of contributing samples (`Set<SourceOfData>`). Empty set illegal. |
| Domain fight / member / person | `server` \| `fixture` |
| Ledger | `server` \| `fixture` only |
| Projection | Always `derived`. Must cite input sample SoDs when the number came from scores. |
| Presentation | None. May show a badge (“Health + Strava”) from the projection cite. |

**Dedup (request “Strava counted twice”)** happens at canonical ingest, not in views.

Policy: **HealthKit is the merge plane.** If an HK sample’s `sourceRevision` is Strava (or already includes that workout), do not also ingest the same Strava activity as a second sample. Identity is `(source, foreignID)` first; fallback `(source, personID, start, end, metric)`.

## Layers

### 0. External raw

Vendor objects. Not ours. Not `Codable` into the app.

- `HKQuantitySample` / `HKWorkout`
- Strava JSON `Data`
- HTTP body `Data`

Live in iOS adapters (`FitFight/Health`, `FitFight/Networking`). Tests fake them with protocols, never with real HK in unit tests.

### 1. Ingress DTOs

Ours, dumb, 1:1 with the payload. `Codable`, `Sendable`. Mapping **only** to canonical samples or to domain snapshots. Never to views.

### 2. Canonical samples

One workout / quantity slice, one SoD, one `foreignID`. This is the last layer that may disagree with another source about the same sweat.

Persisted locally (upload queue) and sent to the server. Phone may show “today so far” from here before the server echoes.

### 3. Aggregates

`DailyScore` per `(personID, calendarDay, metric)`. Built from canonical samples **or** received from the server for a fight window.

**Authoritative fight scores are server aggregates.** The phone’s aggregate is a preview for the open app.

### 4. Domain

`Fight`, `Member`, `Person`, `SettlementRule`, `LedgerEntry`, `FightWindow`.

No formatted strings. No `daysLeft`. No `rank`. Status is `live / invited / finished` (plus `pending` as member status, not a counter on the fight).

### 5. Projection

Pure functions. Clock in, numbers out. **Not persisted.**

Two different questions — do not mix them (today’s UI already does not):

| Question | Function | UI |
| --- | --- | --- |
| Money if nothing changes | Freeze current scores, run `SettlementEngine.preview` | `projectedNet`, “Money right now” |
| Pace if this rate continues | Linear: `score * lengthDays / elapsedDays` | `paceLine`, `paceNote` |
| Goal safe / at risk | `dailyAverage >= goal` (elapsed days ≥ 1) | `safe` badge |

Server **settles** at window close from uploaded samples. The phone engine is **preview only**. Same test vectors both sides when the backend exists. Until then, the Swift engine is the spec.

### 6. Presentation

`FightPresented` — this is **today’s `Fight`**. Kickers, `payoutLine`, `listSubtitle`, `endedLabel`, `invitePitch`, formatted scores.

Views and every design variant take **presented** values. They may arrange pixels. They may not recompute pot shares.

Formatters are locale-aware and metric-aware (`12 min`, `3.2k steps`). `AppModel.formatScore` moves here.

## What stays in AppModel vs repositories

`AppModel` today = fixture world + navigation + formatters + vote/join sets.

**Keep in `AppModel` (session facade, `@MainActor`, stay `ObservableObject` until designs migrate to `@Observable`):**

- Navigation: `tab`, `openFightID`, `showingVersions`
- Ephemeral chrome: `voted`, `joined` (until those hit repositories)
- Read-only facades the UI already uses: `you`, `people`, `fights` (as `FightPresented`), `requests`, `history`, `live` / `invitations` / `finished`
- `fight(id:)`, `youStanding(in:)` — thin lookups

**Leave `AppModel`. Put in stores/repos:**

| Concern | Protocol | First impl |
| --- | --- | --- |
| Fights | `FightRepository` | `FixtureFightStore` |
| People / me | `PersonRepository` | `FixturePersonStore` |
| Requests | `RequestRepository` | `FixtureRequestStore` |
| Samples | `SampleStore` | `InMemorySampleStore` then HK-backed |
| Ledger | `LedgerRepository` | Fixture no-op / server later |
| Theme / design | existing `ThemeStore`, `DesignStore` | unchanged, not domain |

**Forwarding, then delete:** `formatScore`, `formatDelta`, `projectedPace`, `paceLine`, `projectedNet`. Those are presentation / projection. During the facade phase `AppModel` may call the presenter so the eleven designs keep compiling.

`history` is not a store. It is finished fights + your ledger delta, presented.

`ThemeStore` / `DesignStore` stay UI. They must not grow fight data.

## Stop views doing settlement

1. **Types make it unrepresentable.** Domain `Fight` has no `payoutLine`. If a view wants copy, it takes `FightPresented`.
2. **One engine.** `SettlementEngine.preview` / `.settle` is the only place pot shares, winner-takes-all, and goal refunds are computed. Views bind to `MemberProjection.moneyIfUnchanged`.
3. **Presenter owns copy.** `payoutLine`, kicker parts, `listSubtitle`, `paceNote` are functions of `(Fight, FightProjection, PersonID you, Locale)`. Golden tests pin today’s fixture strings.
4. **Design contract unchanged:** variants read the same presented fights. A redesign that needs a new number is a product change (add a projection field), not a view-local formula.
5. **Move now-leaked maths:**
   - `FightDetailView.ringProgress` → `FightProjection.ringProgress`
   - `AppModel.projectedPace` / `paceLine` → projection + presenter
   - `Standing.safe` / `projectedNet` → projection; standing rows become `MemberPresented`
   - `extension Fight.ranked` / `yourPlace` → projection (`rank` is already on the card; stop re-sorting in the view except for stable display order supplied by the presenter)

`NewFightView` stake summary (`$10 each — winner takes all $N`) is **compose-time preview**. Same engine, inputs from the form, not a second formula.

## Observation vs TCA vs SwiftData (for this repo)

Cloud agents, public repo, no local Xcode, screenshot CI as the UI oracle.

- **`@Observable` @MainActor stores** for session and live lists. `@Environment(FightStore.self)` once designs are off `ObservableObject`. Until then, one `AppModel` facade is cheaper than a 12-file environment migration.
- **Protocols + structs** for Core. No actor unless there is actual isolation (HK store wrapper, URLSession client).
- **Not TCA.** The app is five tabs and a detail screen. TCA pays for a composition root this size does not have. Agents will emit 200-line reducers for a kicker string.
- **Not SwiftData for Fight.** When sample volume needs a query engine, put **canonical samples only** in SwiftData (or GRDB) behind `SampleStore`. Fight lists stay a decoded server snapshot in memory.

## File / folder map

Horizons, not separate apps. Do not create nine SPM packages on day one.

```
Packages/FitFightCore/                 # Foundation, Linux-testable
  Sources/FitFightCore/
    IDs.swift
    SoD.swift
    Money.swift
    Quantity.swift
    Clock.swift
    Domain/
      Person.swift
      Fight.swift                      # window, rule, members — no copy
      Member.swift
      Ledger.swift
      Settlement.swift                 # SettlementRule + Engine
    Samples/
      CanonicalSample.swift
      DailyScore.swift
    Projection/
      FightProjection.swift
      MemberProjection.swift
    Presentation/
      FightPresented.swift             # today’s Fight shape
      FightPresenter.swift
      MetricFormat.swift
    Repositories/
      FightRepository.swift
      PersonRepository.swift
      SampleStore.swift
      RequestRepository.swift
  Tests/FitFightCoreTests/
    SettlementTests.swift
    PresenterGoldenTests.swift
    DedupTests.swift
    PaceTests.swift

Packages/FitFightFixtures/
  Sources/FitFightFixtures/
    FixtureFightStore.swift
    FixturePersonStore.swift
    FixtureRequestStore.swift
    FixtureWorld.swift                 # Leo, Sam, the six fights as domain

FitFight/                              # iOS target
  App/
    FitFightApp.swift
    AppModel.swift                     # session facade
    ContentView.swift
  Features/Fights/
    FightsListView.swift
    FightDetailView.swift
  Features/New/
    NewFightView.swift
  Features/Requests/
    RequestsView.swift
  Features/You/
    YouView.swift
    VersionsView.swift
  Features/Designs/                    # unchanged contract: same presented fights
  DesignSystem/
  Health/                              # iOS only, later
    HealthKitClient.swift
    HealthKitMapper.swift
  Networking/                          # later
    FitFightClient.swift
    APIDto.swift
```

**Horizon A (now):** `FitFightCore` + `FitFightFixtures`. App target depends on both. `AppModel` constructs fixture stores and presents. Views still take today’s `Fight` (renamed typealiased to `FightPresented`).

**Horizon B (HealthKit on device):** `FitFight/Health` maps HK → `CanonicalSample`. `SampleStore` persists an upload queue (JSON files are enough). You → Data sources reads store status, not hardcoded strings.

**Horizon C (backend):** `FitFight/Networking` decodes server snapshots into domain `Fight`. Fixture stores remain the screenshot / preview world (`FF_SHOOT=1`). Do not delete fixtures.

Xcode: add the packages to the project; new app `.swift` files still go in `project.pbxproj`. Core files do **not**.

## Testing seams

| Seam | How | Where |
| --- | --- | --- |
| Settlement | Table tests: scores + rule + buy-in → `[PersonID: Money]` | Linux, Core |
| Presenter copy | Golden strings from today’s six fights | Linux, Core |
| Pace / elapsed | `Clock` protocol (`SystemClock` / `FixedClock`) | Linux, Core |
| Sample dedup | Two DTOs, one canonical | Linux, Core |
| Repositories | Swap `FixtureFightStore` for a `RecordingFightStore` | Linux |
| HealthKit | `HealthKitReading` protocol; never instantiate `HKHealthStore` in unit tests | iOS tests later |
| UI | Existing screenshot workflow + `FixtureWorld` | CI `macos-26` |
| Views | Do not unit-test SwiftUI. If a view has a formula, the formula is in the wrong layer. | — |

`ScreenshotExport` keeps using whatever `AppModel` publishes. After the split, that payload must still be the six fixture fights with the same copy.

## Mapping rules (which way)

```
Raw HK/Strava/HTTP     → Ingress DTO          (adapter)
Ingress DTO            → CanonicalSample      (mapper, stamps SoD, foreignID)
CanonicalSample[]      → DailyScore           (aggregate, SoD union)
DailyScore[] + Fight   → MemberScore          (join on personID + window)
Fight + MemberScore[] + Clock
                       → FightProjection      (engine, pure)
Fight + FightProjection + Locale + you
                       → FightPresented       (presenter)
FightPresented         → SwiftUI              (pixels only)

Server Fight snapshot  → Domain Fight         (API mapper)
Domain Fight           ↛ Ingress DTO
FightPresented         ↛ Domain
Projection             ↛ persistence
```

Compose (New fight) walks the same path in reverse for **preview only**: form state → intended `SettlementRule` + roster → `SettlementEngine.preview` → summary copy. Commit is a repository `create`, then the server owns it.

---

## Type catalog

Legend: **P** persist, **C** Codable, **S** Sendable. Persist means “this type is stored on purpose,” not “could JSONEncoder it in a test.”

### IDs and values

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `FightID` | ID | — | n | y | y | `String` raw. `"sweat"`. |
| `PersonID` | ID | — | n | y | y | `"you"`, `"leo"`. |
| `MemberID` | ID | — | n | y | y | Optional; `(fightID, personID)` is enough at first. |
| `SampleID` | ID | — | n | y | y | Ours, assigned at ingest. |
| `LedgerEntryID` | ID | — | n | y | y | Server-minted. |
| `RequestID` | ID | — | n | y | y | `"r1"`. |
| `SourceOfData` | meta | self | n | y | y | See table above. |
| `Money` | value | — | n | y | y | `cents: Int`, `currency: .usd`. Signed for deltas. |
| `Quantity` | value | — | n | y | y | `value: Double` + `MetricKind`. Not money. |
| `MetricKind` | domain | — | n | y | y | `activeMinutes`, `steps`, `workouts`. Display names are presentation. |
| `Clock` | seam | — | n | n | y | Protocol. `now: Date`. |
| `FixedClock` | seam | — | n | n | y | Tests. |

```swift
struct FightID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    var raw: String
    init(raw: String) { self.raw = raw }
    init(stringLiteral value: String) { raw = value }
}
```

Same shape for the other IDs. `Identifiable.id` is the typed ID, not `String`.

### External raw (not our types)

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `HKQuantitySample` | raw | implicit HK | n | n | n | Adapter only. |
| `HKWorkout` | raw | implicit HK | n | n | n | |
| `Data` (Strava / HTTP) | raw | implicit | debug only | n | y | Do not decode in a view. |

### Ingress

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `HealthSampleDTO` | ingress | `healthKit` | optional cache | y | y | start, end, metric, value, `foreignID`, HK source bundle id. |
| `StravaActivityDTO` | ingress | `strava` | optional cache | y | y | Activity id is `foreignID`. |
| `FightSnapshotDTO` | ingress | `server` | y (as blob ok) | y | y | API fight JSON. Maps to domain, **not** to `FightPresented`. |
| `LedgerSnapshotDTO` | ingress | `server` | y | y | y | |
| `FixtureFightDTO` | ingress | `fixture` | n | y | y | Optional; fixtures may construct domain directly. |

### Samples and aggregates

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `CanonicalSample` | sample | one of HK/Strava/manual/fixture | y | y | y | `id`, `personID`, `metric`, `quantity`, `start`, `end`, `sod`, `foreignID`. |
| `SampleIdentity` | sample | inherited | n | y | y | Dedup key. |
| `DailyScore` | aggregate | `Set<SourceOfData>` | cache | y | y | Per person, calendar day, metric. |
| `MemberScore` | aggregate | union | n (derived) | y | y | Window sum + `today`. What `Standing.score` / `.today` are now. |
| `CalendarDay` | value | — | n | y | y | `year, month, day` + `timeZoneID`. Fight days are these, not `"Day 1"` strings. |

### Domain

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `Person` | domain | server/fixture | y | y | y | `id`, `displayName`, `handle`, `initials`. **No** `photo` asset name. |
| `Fight` | domain | server/fixture | y | y | y | `id`, `code`, `name`, `metric`, `window`, `rule`, `stake`, `status`, `members`. No kickers. |
| `FightWindow` | domain | inherited | y | y | y | `start`, `lengthDays`, `timeZoneID`. End is derived. |
| `FightStatus` | domain | inherited | y | y | y | `live`, `invited`, `finished`. |
| `Member` | domain | inherited | y | y | y | `personID`, `status` (`joined` / `invited`), `buyIn`. |
| `Stake` | domain | inherited | y | y | y | `bragging` \| `money(Money)` \| `action(String)`. |
| `SettlementRule` | domain | inherited | y | y | y | `winnerTakesAll` \| `proportional` \| `hitGoal(Quantity)`. |
| `SettlementEngine` | domain | — | n | n | y | Static/pure. Preview vs settle. |
| `LedgerEntry` | domain | server/fixture | y | y | y | Phone **does not create**. `kind`: buyIn / settlement / refund. |
| `LedgerDelta` | projection-ish | derived | n | y | y | Preview only. Never stored as a ledger row. |
| `FightCode` | domain | inherited | y | y | y | `"FIGHT-742"`. Display as-is. |

`MetricKind.eyebrow` / `.title` / `.blurb` and `SettlementKind.title` / `.blurb` **leave domain**. They are presenter / copy catalogs (`MetricCopy`, `SettlementCopy`). Domain enums stay raw.

### Projection

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `FightProjection` | projection | derived (+ cite) | n | n* | y | `daysLeft`, `rank`, `of`, `pendingCount`, `ringProgress`, `paceNoteQuantity`, `pot`, `sampleCite`. |
| `MemberProjection` | projection | derived | n | n* | y | `personID`, `rank`, `moneyIfUnchanged`, `pace`, `safe`, `gapToLeader`. |
| `Pace` | projection | derived | n | n | y | Quantity at current rate to window end. |
| `SampleCite` | projection | derived | n | y | y | `Set<SourceOfData>` that fed the scores. You-tab sources. |
| `RingProgress` | projection | derived | n | n | y | 0…1. Goal: `score / (goal * elapsedDays)`. Else: `you / leader`. |

\*Codable optional for debug dumps; not a persistence format.

**Money-if-unchanged** (spec):

- Winner: current max score takes `pot`; everyone else `−buyIn`; winner net = `pot − buyIn` (today’s Sweat: Leo +20, others −10 on $10 buy-in / $30 pot).
- Proportional: `pot * score / sum(joined scores)` minus `buyIn`. Invited people: `−buyIn` or excluded — **excluded from the split, shown invited** (Nina on Derby).
- Goal: joined members with `dailyAverage >= goal` are `safe`; they split the buy-ins of those who are not. Exact split is engine output; today’s Club numbers (+7 / −20) are fixture fudge — **golden tests may pin fudge until engine + fixtures are regenerated together**. Do not re-fudge in a view.

### Presentation (today’s UI types)

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `FightPresented` | presentation | — | n | n | y | **Rename of today’s `Fight`.** Kickers, `listSubtitle`, `payoutLine`, `endedLabel`, `invitePitch`, `inviteAction`, `standingsMeta`, `paceNote`, `daysLeft`, `rank`, `of`, `pending`, `pot` as `Int` dollars for `FFMoney`, `standings: [StandingPresented]`, `days: [DayPresented]`. |
| `StandingPresented` | presentation | — | n | n | y | Today’s `Standing`. |
| `DayPresented` | presentation | — | n | n | y | Today’s `FightDay` (`label: "Day 1"`). |
| `DayScorePresented` | presentation | — | n | n | y | Today’s `DayScore`. |
| `PersonPresented` | presentation | — | n | n | y | Domain person + `photo` asset name + `isYou`. |
| `RequestPresented` | presentation | — | n | n | y | Today’s `RequestItem` including `ago`. |
| `HistoryPresented` | presentation | — | n | n | y | Today’s `HistoryItem`. |
| `FightPresenter` | presentation | — | n | n | y | `present(fight:projection:people:you:locale:)`. |
| `MetricFormat` | presentation | — | n | n | y | `formatScore`, `formatDelta`. Leaves `AppModel`. |
| `Kicker` | presentation | — | n | n | y | `prefix`, `emphasis`, `rest`. |
| `MetricCopy` | presentation | — | n | n | y | eyebrow / title / blurb. |
| `SettlementCopy` | presentation | — | n | n | y | title / blurb. |

During Horizon A, `typealias Fight = FightPresented` so designs do not move.

### Session / app

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `AppModel` | session | — | n | n | n | `@MainActor` `ObservableObject` facade. Navigation + published presented data. **Not** `Sendable`. |
| `FightStore` | session | — | n | n | n | Later `@Observable` owner of `[Fight]` + projections. |
| `ThemeStore` | UI | — | UserDefaults | n | n | Stays. |
| `DesignStore` | UI | — | UserDefaults | n | n | Stays. Variants consume presented fights only. |

### Repositories (protocols in Core, impls in Fixtures / iOS)

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `FightRepository` | protocol | — | — | n | y | `func fights() async -> [Fight]`; `func fight(id:) async -> Fight?`; later `create` / `accept`. |
| `PersonRepository` | protocol | — | — | n | y | `var you: Person`; `func roster() async -> [Person]`. |
| `RequestRepository` | protocol | — | — | n | y | `func items()`; `func toggleVote(id:)`. |
| `SampleStore` | protocol | — | — | n | y | `func ingest(_:CanonicalSample)`; `func samples(person:range:)`. |
| `LedgerRepository` | protocol | — | — | n | y | Read-only on device. |
| `HealthKitReading` | adapter protocol | HK | n | n | n | iOS. Query → `[HealthSampleDTO]`. |
| `FixtureFightStore` | fixture | fixture | n | n | y | Implements `FightRepository`. Domain fights, **no copy strings**. |
| `FixtureWorld` | fixture | fixture | n | n | y | Cast + six fights as domain + scores. Single seed. |

### Requests (bounded context — keep small)

| Type | Layer | SoD | P | C | S | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| `FeedbackRequest` | domain | server/fixture | y | y | y | id, kind, status, authorID, title, body, `createdAt`, counts. |
| `RequestPresented` | presentation | — | n | n | y | `ago` formatted. Do not store `"3d ago"`. |

Not HealthKit. Same fixture protocol trick. Do not over-layer this.

---

## Today → tomorrow (field map)

| Today | Becomes |
| --- | --- |
| `Fight.id: String` | `FightID` |
| `Fight.daysLeft`, `rank`, `of`, `pending` | `FightProjection` |
| `Fight.kicker*`, `listSubtitle`, `payoutLine`, `paceNote`, `invite*`, `endedLabel`, `standingsMeta` | `FightPresenter` |
| `Fight.standings[].score/today` | `MemberScore` |
| `Fight.standings[].projectedNet/safe` | `MemberProjection` |
| `Fight.standings[].invited` | `Member.status` |
| `Fight.days[].label` | presenter (`Day 1`) from `CalendarDay` |
| `Standing.person.isYou` | `personID == youID` |
| `Person.photo` | presenter: `"Avatar-\(isYou ? "maya" : id.raw)"` |
| `AppModel.projectedNet` | sum of your `MemberProjection.moneyIfUnchanged` on live fights |
| `AppModel.history` | presenter over finished fights |

## Horizon checklist (agents)

1. Extract `FitFightCore` IDs, `Money`, `SettlementRule`, domain `Fight` / `Member` / `Person`. Fixture world as domain. Presenter that **still emits the current strings** (hardcode map by `FightID` is allowed for one PR). `AppModel` loads fixtures through the protocol. Views unchanged via `typealias Fight = FightPresented`.
2. Put maths in `SettlementEngine`. Presenter computes kickers. Golden tests. Delete copy from fixture data. Regenerated Derby/Club nets if they disagree with the engine — change fixtures + goldens in the same PR, not the views.
3. `CanonicalSample` + ingest policy + You-tab sources from `SampleCite` / store (still fake HK).
4. API snapshots replace live `FightRepository` in the app; fixtures remain for screenshots.
5. Real HealthKit adapter + upload. Server settles. Phone preview stays.

If a task needs a number that is not on `FightPresented`, add a projection field and present it. Do not format a new rule inside `D3Arena.swift`.

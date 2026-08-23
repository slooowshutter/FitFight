# iOS layout (when this leaves paper)

Keep the eleven Fights designs compiling against one façade. Do not put `URLSession` in a list view “just this once.”

Law: [`../sync.md`](../sync.md). Types: [`layers.md`](layers.md).

## Folders

```
FitFight/
  App/            FitFightApp, AppModel façade, tabs
  DesignSystem/   tokens, components (already here)
  Designs/        eleven directions — read AppModel only
  Features/       Fights, New, Requests, You
  Domain/         IDs, Fight, Member, SettlementEngine — Foundation only
  Presentation/   FightPresented, formatters, kickers
  Persistence/    AppDatabase, Migrations/0001_….swift, Records/
  Sync/           SyncEngine, APIClient, OutboxDrainer, ScoreCompiler, CacheWriter
```

New `.swift` files still go in `project.pbxproj` (explicit list).

## Allowed imports

| Import | Allowed in |
| --- | --- |
| HealthKit | `FitFight/Sync/ScoreCompiler.swift` only |
| GRDB | `Persistence/`, `Sync/` |
| URLSession | `FitFight/Sync/APIClient.swift` only |
| SwiftUI | App, DesignSystem, Designs, Features — not APIClient |

CI: `scripts/check-sync-boundaries.py` on every PR. Forbidden even before the folders exist: SwiftData, CloudKit, `NSUbiquitousKeyValueStore`.

## AppModel

Stays `ObservableObject` until designs migrate. **Read-only** except `submit` and `refresh`. Published `fights` are **presented**. Preview / `FF_SHOOT=1`: `AppModel.preview()`, **no sqlite**. Production `@main` must not call `preview()`.

```swift
enum UserIntent: Equatable {
    case createFight(CreateFightDraft)
    case acceptInvite(FightID)
    case declineInvite(FightID)
    case vote(RequestID)
    case unvote(RequestID)
}
```

A `CreateFightDraft` is not a `Fight`. A fight exists after the server applies the command.

## Observation vs TCA vs SwiftData

**`@Observable` / current `ObservableObject` + protocols.** Not TCA (ceremony, Linux can’t typecheck the app). Not SwiftData as architecture (CloudKit footgun; `@Query` bypasses Sync). GRDB when persistence lands; until then fixtures through `CacheWriter` in DEBUG or `preview()` only.

## Packages

Optional later: `FitFightCore` (Foundation) so Linux `swift test` can run settlement without Xcode. HealthKit adapters stay in the iOS target. Do not start a third language or a shared codegen package until the third duplicated field actually hurts.

## Design variants

They consume **facts**: name, metric, memberships, buckets, stake, derived rank/net/days. They compose sentences. They must not require `kickerPrefix` stored on the model. Palette + radius + layout only. When one wins: delete `FitFight/Designs/` and the tab.

## First code PR (do not skip)

0. This doc + the grep script (this PR).
1. GRDB shell + `CacheWriter` + `AppModel` reading sqlite. Fixtures through the writer in DEBUG.
2. `APIClient` + ETags + SWR + PTR against stub HTTP. Empty production cache, no Leo.
3. `UserIntent` + `outbox_command`.
4. `ScoreCompiler` + `outbox_score_batch` (needs Marc: HealthKit capability).
5. Silent push + server grace job.

Marc still flips HealthKit, Push, SIWA in the developer portal. Agents cannot.

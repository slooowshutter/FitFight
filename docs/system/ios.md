# iOS client (6–9 months)

Today: one target, `AppModel` is a fixture god-object, L5 copy stored on `Fight`. Keep compiling. Split before HealthKit.

## Folders (not SPM packages)

Stay inside `FitFight/`. Extra targets wait for a widget/watch.

```
FitFight/
  App/            FitFightApp, AppContainer, AppRouter
  Domain/         L4 types, repository protocols, FightCopy (L4→L5)
  Data/Remote     URLSession, DTOs
  Data/Local      SwiftData L4 cache, ingest outbox
  Data/Fixtures   today’s cast implementing the same protocols
  Features/       Fights, New, Requests, You, Boss
  Health/         HK reader — never CloudKit
  DesignSystem/   tokens (unchanged)
  Designs/        temporary
```

Chrome (version banner, tab bar) stays app-level.

## Protocols

```swift
protocol SessionStore: AnyObject {
    var currentUser: Person? { get }
    func restore() async
    func signIn() async throws
}

protocol FightRepository: AnyObject {
    var fights: [Fight] { get }
    func refresh() async throws
    func fight(id: Fight.ID) -> Fight?
    func create(_ draft: FightDraft) async throws -> Fight
    func acceptInvite(id: Fight.ID) async throws
}

protocol IngestClient: AnyObject {
    func enqueue(_ window: MetricWindow)
    func uploadPending() async throws
}
```

Views never import URLSession. `AppContainer` is the only place that knows fixture vs remote.

Fixtures implement all three. Screenshot export uses the same container.

`MetricWindow` is user-level evidence `{ metric, start, end, value, externalId, source }`. The server attaches it to live fights. Do not send `fightID` on samples. Not `HKSample` blobs.

## Kill `AppModel` in slices

1. `AppRouter`: `tab`, `openFightID`, `showingVersions` (tab change clears detail)
2. Protocols + fixtures; `AppModel` façade so Designs still compile
3. Original Fights/New/You take `FightStore`
4. Point Designs at the same store
5. Delete `AppModel`

New stores: `@Observable`. Do not convert Theme/Design/Boss in the same PR. No TCA.

## L4 vs L5

Remove from `Fight`: kicker fields, `listSubtitle`, `payoutLine`, invite pitch, pace note. Those live in `FightCopy` used by original **and** every Design. Same gap to Leo in all eleven looks.

`rank` is `Int?`. Invited is `nil`, never `0`.

## Navigation

Two coordinates: tab + optional fight id. Push payload later is the same. No URL router. Scroll offset does not persist across tabs.

## Local data

SwiftData **without CloudKit**. Cache L4 + outbox only. If SwiftData is annoying, a JSON file outbox is enough until volume is real. Not GRDB until it hurts.

Health never in iCloud, never in the fight cache as samples.

## Files in pbxproj

This project is an **explicit** file list. Disk-only Swift does not compile on CI. Four edits per file: `PBXBuildFile`, `PBXFileReference`, group, Sources. JSON in Resources.

## Do not

- HealthKit as settlement
- Per-design domain models
- Firebase
- Moving the version label into the tab bar
- Making the Design tab permanent
- Adding HK/Push entitlements before the code that needs them

## First implementation slice (when coding)

Folders + protocols + move fixture arrays. `FightCopy` so screenshots still match. `AppRouter`. Stop. Backend is the next slice behind the same protocols.

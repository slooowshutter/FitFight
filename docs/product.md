# Product

One line: challenge your friends, winner takes the glory.

## Names (they’re different)

| What | Value |
| --- | --- |
| On-device display name | **FitFight** |
| App Store Connect listing name | **FitFight MVP** (`FitFight` / `Fitfight` was already taken) |
| SKU | `fitfight` |
| Bundle ID | `com.fitfight.mvp` |
| Team | Marc Lamy, Team ID `C92DPD8ME2` |
| Xcode target / scheme | `FitFight` |

Do not rename the bundle ID without Apple + CI updates.

## v0.3 (approved design)

The web kit in [`docs/design/source/`](design/source/README.md) is the look. SwiftUI ports it:

- Four tabs: **Fights**, **New**, **Requests**, **You**
- Theme = dark/light × one of ten accents (default dark + blue)
- Live fight cards carry their own leaderboard and money line
- Version label at the top; Versions under You → Settings

Marketing version: `0.8.0`. Frozen for TestFlight. CI bumps **build number** from TestFlight (`latest + 1`). Do **not** bump marketing version for a TestFlight ship — Apple re-reviews each new `0.8.x` / `0.9.0` for external testers. See [`shipping.md`](shipping.md#versions-vs-builds-why-friends-wait).

## v0.6 (design exploration)

A fifth tab, **Design**, holds eleven directions for the Fights screen — `original`
plus ten experiments — rendered live side by side. Tap one and the whole app takes
its palette. The pick persists in `UserDefaults` under `ff.design`.

- One file per direction in [`FitFight/Designs/`](../FitFight/Designs/); `DesignVariant.swift`
  holds the enum, the palettes and the dispatcher.
- A direction owns colour and corner radius only. Type scale and spacing still come
  from `tokens.json`, so the approved system is still the base underneath.
- Every direction reads the same `AppModel`. Same fights, same names, same money.
  If a redesign needs different data, that is a product change, not a design one.
- `original` is the approved v0.3 design and the default. Only it follows You → Look;
  the other ten pin their own palette and light/dark mode.
- `ScreenshotExport` renders `design-<name>.png` for each one, so CI publishes all
  eleven on every PR.

This is an experiment shelf, not a shipped feature set. When one wins, keep it, delete
the rest and the tab with them.

Placeholder themes (Arena, Pulse, Locker, Rogue) from v0.2 are retired — the v0.6
directions named Arena and Pulse are unrelated to them.

## v0.7 (talk to the boss)

Requests has a **Talk to the boss** button. It opens a private chat with Marc,
separate from the public vote board. There is still no server, so sending a
message opens Mail to `marc@marclamy.com`. He replies from his inbox.

## v0.8 (Apple account + HealthKit Steps)

You can **Sign in with Apple**. You shows the real `profiles` handle. You → Data sources
reads today’s Apple Health **Steps** aggregate (not a sum of every raw source) and
lists contributing apps when HealthKit names them. Empty reads say “No accessible data”.
You → Settings has **Delete account**. Fights are still fixtures. HealthKit is not
uploaded to the server yet.

## v0.9 (live Steps Fight)

Sign in, add friends by handle, start a real Steps fight. Apple Health uploads to the
server. Standings come from the database. Fights are no longer the fixture people.
When the days are up the server closes the fight (app open or cron). Signed out, the
app is only a welcome screen plus Sign in with Apple. The Design tab still previews
the old mock. Requests is unchanged.

## Not this project

- Hermes (a home-Mac agent) is unrelated. Ignore it.
- GoPrime / humanedger is a different app Marc tested. Not source of truth here.

## Next product work

The living list is [`backlog.md`](backlog.md). You can sign in, add friends, start a Steps fight, and see live standings. The golden guide is [`system-design.md`](system-design.md) — follow it, do not implement all of it. First real Metric is **Steps**. Don’t invent the gaps listed in [`design/source/INVENTORY.md`](design/source/INVENTORY.md).

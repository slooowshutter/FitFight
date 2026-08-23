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

Placeholder themes (Arena, Pulse, Locker, Rogue) are retired.

Marketing version: `0.3.0`. CI bumps **build number** from TestFlight (`latest + 1`). Don’t bump marketing version for a daily CI-only ship.

## Not this project

- Hermes (a home-Mac agent) is unrelated. Ignore it.
- GoPrime / humanedger is a different app Marc tested. Not source of truth here.

## Next product work

Real challenges / friends / scoring — the screens exist as a design-accurate mock with fixture people. No HealthKit, no backend, no notifications. Don’t invent the gaps listed in [`design/source/INVENTORY.md`](design/source/INVENTORY.md).

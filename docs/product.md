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

## v0 (now on TestFlight)

One screen whose job was to prove the loop:

- Title **FitFight** and tagline
- Version at the **top of the screen** via `VersionBanner` / `AppVersion.label` → `MARKETING_VERSION (CFBundleVersion)`
- **Versions** button → sheet listing `Changelog.releases` (version, date, notes). Stays in every future build.

Marketing version: `0.1.0`. CI bumps **build number** from TestFlight (`latest + 1`). Don’t bump marketing version for a daily CI-only ship.

## Not this project

- Hermes (a home-Mac agent) is unrelated. Ignore it.
- GoPrime / humanedger is a different app Marc tested. Not source of truth here.

## Next product work

Real challenges / friends / scoring — not started. Keep the version chrome and Versions list when you add that.

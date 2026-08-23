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
- **Settings** → **Language** opens iOS Settings so the user can pick FitFight’s language (phone can stay French, app English).

Marketing version: `0.1.0`. CI bumps **build number** from TestFlight (`latest + 1`). Don’t bump marketing version for a daily CI-only ship.

## Language

Do this the iOS way. Do **not** write a custom in-app language engine (`AppleLanguages`, Bundle swizzling, or a SwiftUI locale override as the source of truth).

- iOS picks the language from preferred languages, not country ([QA1828](https://developer.apple.com/library/archive/qa/qa1828/_index.html)).
- Strings live in `FitFight/Localizable.xcstrings` (String Catalogs). SwiftUI `Text` / `Button` literals + `String(localized:)`. Source English, French in the same file.
- Users change FitFight’s language in **iOS Settings → FitFight → Language** (always shown via `UIPrefersShowingLanguageSettings`, WWDC24). In-app Settings only jumps there (`openSettingsURLString`, WWDC19/24). iOS relaunches the app in the new language.

Adding a language later is a catalog column + `knownRegions` — not a rewrite.

## Not this project

- Hermes (a home-Mac agent) is unrelated. Ignore it.
- GoPrime / humanedger is a different app Marc tested. Not source of truth here.

## Next product work

Real challenges / friends / scoring — not started. Keep the version chrome, Versions list, and String Catalog when you add that.

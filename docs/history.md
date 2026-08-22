# History

## 2026-08-22 — approved design ported

`docs/design/source/` dump from fitfight-v2. SwiftUI now has four tabs matching that kit. Arena/Pulse/Locker/Rogue retired. Marketing version `0.3.0`.

## 2026-08-22 — design system

Tokens in `FitFight/DesignSystem/themes.json` (later replaced). Four placeholder themes (Arena, Pulse, Locker, Rogue). Marketing version `0.2.0`.

## 2026-08-22 — loop proven

Cloud agent (not Marc’s Mac) created the SwiftUI app, Fastlane, and GitHub Actions in https://github.com/marclelamy/FitFight.

Marc (Account Holder) did the one-time Apple side:

- Registered App ID `com.fitfight.mvp` (explicit, no capabilities).
- App Store Connect app: listing name **FitFight MVP** (plain FitFight taken), SKU `fitfight`.
- App Store Connect API: Request Access, then key **FitFight GitHub** (Admin). Secrets added on the GitHub repo.
- Merged pipeline PR #1, then **Run workflow**.

CI failures before the first successful upload:

1. `xcodebuild: option '-authenticationKeyPath' may only be provided once` — Fastlane gym concatenated `xcargs` + `export_xcargs`. Fix: `xcargs` only.
2. App Store Connect 409: built with iOS **18.5** SDK (runner `macos-15` / Xcode 16.4). Required iOS **26** SDK. Fix: `runs-on: macos-26`.

Successful upload: [TestFlight run #32580212460](https://github.com/marclelamy/FitFight/actions/runs/32580212460) on `main` (`c32176a`), ~4m40s. First binary: **0.1.0 (1)**.

## Don’t repeat

- Do not scaffold on `/Users/marclamy/...` or treat any local Mac folder as source of truth.
- Do not add a home runner “because Marc has a Mac.”
- Do not send Marc through App Store Connect documentation while he’s in a voice loop.

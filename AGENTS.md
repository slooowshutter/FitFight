# FitFight — for agents

Read this first, then `docs/`. Marc talks from his phone, often transcribing. Be concise. Do the work in the cloud. Do not send him into Apple/GitHub docs.

**Owner:** Marc Lamy (`marc@marclamy.com`)  
**Repo:** https://github.com/marclelamy/FitFight (public)  
**Loop:** Marc (phone) → Cursor **cloud** agent → git push → GitHub Actions `macos-26` → TestFlight → iPhone.

## Hard rules

- Cloud only. No home Mac, no Hermes, no self-hosted runner, no Xcode on Marc’s desk.
- This Linux environment cannot compile or upload iOS. CI on GitHub-hosted `macos-26` does that.
- Never put `.p8` / API keys / provisioning profiles in git or chat.
- Keep the repo **public** (free GitHub macOS minutes). Don’t make it private without saying so.
- Version label stays at the **top of the screen** (not the nav bar), e.g. `0.1.0 (12)`.
- Permanent **Versions** button: every user-facing ship adds a row in `FitFight/Changelog.swift`.
- Talk to Marc only for things only he can do: Apple login, GitHub secrets, TestFlight testers, legal. Same-day TestFlight: he taps **Actions → TestFlight → Run workflow** (agents cannot `workflow_dispatch` here).

## What exists (2026-08-22)

- Native SwiftUI iOS app, scheme `FitFight`, bundle ID `com.fitfight.mvp`.
- First TestFlight upload **succeeded** (build `0.1.0 (1)`).
- Daily TestFlight at **18:00 UTC** + manual `workflow_dispatch`.
- Simulator compile on every PR.

Details: [docs/product.md](docs/product.md) · [docs/shipping.md](docs/shipping.md) · [docs/history.md](docs/history.md)

## When you change the app

1. Branch off `main`. PR unless Marc says otherwise.
2. Add new `.swift` files to `FitFight.xcodeproj/project.pbxproj` (explicit file list, not a synchronized group).
3. If users will see it: append a `ReleaseNote` in `Changelog.swift` (and bump `MARKETING_VERSION` when it’s a real version, not just a daily CI build).
4. User-facing copy: SwiftUI string literals plus a French translation in `FitFight/Localizable.xcstrings` in the same PR. Don’t hardcode new UI text.
5. Don’t ask Marc to open Xcode or his Mac.

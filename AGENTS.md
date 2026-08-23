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
- Version label stays at the **top of the screen** (not the nav bar), e.g. `0.3.0 (12)`.
- Permanent **Versions** button: under You → Settings, and the version label at the top. Every user-facing ship adds a row in `FitFight/Changelog.swift`.
- Design tokens live in `FitFight/DesignSystem/tokens.json` (same file as `docs/design/source/tokens.json`). Don’t hardcode colours. Theme is **base × accent**. After token changes, copy the dump into the app bundle file.
- Talk to Marc only for things only he can do: Apple login, GitHub secrets, TestFlight testers, legal. Agents cannot `workflow_dispatch`. App pushes (PR branch or `main`) upload to TestFlight by themselves. Tell Marc a build is coming; he opens TestFlight → Update. Do not ask him to Run workflow.

## What exists (2026-08-22)

- Native SwiftUI iOS app, scheme `FitFight`, bundle ID `com.fitfight.mvp`.
- First TestFlight upload **succeeded** (build `0.1.0 (1)`).
- TestFlight on every app push (PR branch or `main`), plus daily **18:00 UTC**.
- Simulator compile on every PR.
- Approved design dump in `docs/design/source/` (338 tokens, 76 screenshots). App has four tabs: Fights, New, Requests, You. Dark/light + 10 accents.

Details: [docs/product.md](docs/product.md) · [docs/backlog.md](docs/backlog.md) · [docs/shipping.md](docs/shipping.md) · [docs/history.md](docs/history.md) · [docs/design/source/README.md](docs/design/source/README.md)

Product ideas go in [`docs/backlog.md`](docs/backlog.md). Marc says “put X on the backlog”; do not open GitHub Issues or a Notion board unless he asks.

## When you change the app

1. Branch off `main`. PR unless Marc says otherwise.
2. Add new `.swift` files to `FitFight.xcodeproj/project.pbxproj` (explicit file list, not a synchronized group). JSON in `DesignSystem/` must also be in the Resources build phase.
3. If users will see it: append a `ReleaseNote` in `Changelog.swift` (and bump `MARKETING_VERSION` when it’s a real version, not just a daily CI build).
4. Don’t ask Marc to open Xcode or his Mac. After you push app code, TestFlight uploads itself. He opens TestFlight → Update. Do not ask him to merge first, or to Run workflow.

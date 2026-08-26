# FitFight — for agents

Read this first, then `docs/`. Marc talks from his phone, often transcribing. Be concise. Do the work in the cloud. Do not send him into Apple/GitHub docs.

Next.js / server rules live in [`web/AGENTS.md`](web/AGENTS.md) (copied from Blend `develop`). Do not use those on SwiftUI.

**Owner:** Marc Lamy (`marc@marclamy.com`)  
**Repo:** https://github.com/marclelamy/FitFight (public)  
**Loop:** Marc (phone) → Cursor **cloud** agent → PR into `develop` → you try it → merge `develop` into `main` when it should be production → GitHub Actions `macos-26` → TestFlight → iPhone.

## Hard rules

- Cloud only. No home Mac, no Hermes, no self-hosted runner, no Xcode on Marc’s desk.
- This Linux environment cannot compile or upload iOS. CI on GitHub-hosted `macos-26` does that.
- Never put `.p8` / API keys / provisioning profiles in git or chat.
- Keep the repo **public** (free GitHub macOS minutes). Don’t make it private without saying so.
- Version label stays at the **top of the screen** (not the nav bar), e.g. `0.9.0 (48) · staging · 25 Aug`.
- Permanent **Versions** button: under You → Settings, and the version label at the top. Every user-facing ship adds a `ReleaseNote` in `FitFight/Changelog.swift` (same marketing version, new date/notes) and updates **Last TestFlight** in `docs/backlog.md`.
- **Do not bump `MARKETING_VERSION` for TestFlight.** Phones already have **0.9.0** from the live-fight builds. Stay on `0.9.0`. Do not drop back to `0.8.0` — TestFlight will not replace `0.9.0 (42)` with `0.8.0 (47)`. CI still increments the **build number**. Changelog rows reuse `0.9.0`. Only bump marketing version for an App Store ship or if Marc asks.
- Design tokens live in `FitFight/DesignSystem/tokens.json` (same file as `docs/design/source/tokens.json`). Don’t hardcode colours. Theme is **base × accent**. After token changes, copy the dump into the app bundle file.
- Talk to Marc only for things only he can do: Apple login, GitHub secrets, TestFlight testers, legal, the hosted Supabase dashboard. Agents cannot `workflow_dispatch`. App pushes (PR branch, `develop`, or `main`) upload to TestFlight by themselves. Tell Marc a build is coming; he opens TestFlight → Update. Do not ask him to Run workflow.
- Never nuke the hosted database. No `supabase db reset` / `db push` against production or `develop`, no `DROP TABLE` / `TRUNCATE` / `DROP SCHEMA` / `DROP DATABASE` unless Marc asked in that chat and the migration starts with `-- allow-destructive`. Never put `sb_secret_...`, `service_role`, or the database password in git, chat, or iOS. Never merge to `main` unless Marc asked to ship to production. Never merge to `develop` unless Marc asked. Production migrations apply only after `develop` is merged to `main`.

## What exists (2026-08-26)

Current map: [`docs/status.md`](docs/status.md). Sign-in, username, create/accept Steps fight, HealthKit upload, and standings work on staging. #30 is on `develop`. No Vercel required for that path.

- Native SwiftUI iOS app, scheme `FitFight`, bundle ID `com.fitfight.mvp`.
- First TestFlight upload **succeeded** (build `0.1.0 (1)`). Latest user-facing ship: **0.9.0** welcome + develop Supabase.
- TestFlight on every app push (PR branch or `main`), plus daily **18:00 UTC**.
- Simulator compile on every PR.
- Approved design dump in `docs/design/source/` (338 tokens, 76 screenshots). Dark/light + 10 accents.
- Four tabs: Fights, New, Requests, You. The Design experiment tab is gone.

**What works vs fake vs next:** [`docs/status.md`](docs/status.md). Read that before building.

Details: [docs/status.md](docs/status.md) · [docs/product.md](docs/product.md) · [docs/backlog.md](docs/backlog.md) · [docs/system-design.md](docs/system-design.md) · [docs/backend.md](docs/backend.md) · [docs/shipping.md](docs/shipping.md) · [docs/history.md](docs/history.md) · [docs/design/source/README.md](docs/design/source/README.md)

[`docs/system-design.md`](docs/system-design.md) is the golden guide for production. Follow it so new work fits. Do **not** implement that document. Do **not** build Active Minutes, Workout Count, WHOOP, Strava, payments, notifications, social, or the website until the backlog says so.

Right now: empty platform in `supabase/` (see [`docs/backend.md`](docs/backend.md)), then the minimum Steps Fight. The mock UI may still show three metrics because that is the design kit. Production scoring is Steps only.

Product ideas go in [`docs/backlog.md`](docs/backlog.md). Marc says “put X on the backlog”; do not open GitHub Issues or a Notion board unless he asks.

## When you change the app

1. Branch off `develop`. Open a PR **into `develop`**. Do not PR into `main` unless Marc is shipping to production.
2. Add new `.swift` files to `FitFight.xcodeproj/project.pbxproj` (explicit file list, not a synchronized group). JSON in `DesignSystem/` must also be in the Resources build phase.
3. If users will see it: append a `ReleaseNote` in `Changelog.swift` using the current `MARKETING_VERSION` (`0.9.0`). Do **not** change `MARKETING_VERSION` in `project.pbxproj`. CI bumps the build number. Only bump marketing version when Marc is shipping to the App Store or he asked in that chat.
4. Don’t ask Marc to open Xcode or his Mac. After you push app code, TestFlight uploads itself. He opens TestFlight → Update. Do not ask him to merge first, or to Run workflow.
5. Shipping to production is Marc merging `develop` → `main`. Agents do not do that unless he said so in that chat.
6. Merged feature branches are deleted by CI. `main` and `develop` stay. Do not enable GitHub’s “Automatically delete head branches.”

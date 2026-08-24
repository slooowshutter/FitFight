# Shipping

```
Marc (phone) → cloud Cursor agent → git push (PR or main)
  → GitHub Actions (hosted macos-26 + Xcode 26)
  → Fastlane `beta` → TestFlight
  → Marc taps Update
```

Not: agent on Marc’s laptop or home Mac → local Xcode.

## Workflows

| Workflow | File | When | Runner |
| --- | --- | --- | --- |
| Simulator | `.github/workflows/ios-build.yml` | PR + push to `main` | `macos-26` |
| Screenshots | `.github/workflows/ios-screenshots.yml` | PR + push to `main` | `macos-26` |
| TestFlight | `.github/workflows/ios-testflight.yml` | any app `push` (PR or `main`), cron `0 18 * * *` UTC | `macos-26` |
| Database | `.github/workflows/database.yml` | PR + push to `main` | `ubuntu-latest` |

Both **must** stay GitHub-hosted. Never `self-hosted`. Apple requires **Xcode 26 / iOS 26 SDK** to upload (Xcode 16.4 / iOS 18.5 is rejected).

Fastlane: `fastlane/Fastfile` lane `beta`. Archive uses automatic signing + App Store Connect API key (`-allowProvisioningUpdates`). Do **not** also set `export_xcargs` to the same `-authenticationKeyPath` flags — gym passes `xcargs` into export and duplicates the flag.

Build number is not committed; CI sets `CURRENT_PROJECT_VERSION` at archive time.

## Seeing the UI without a build

Every PR renders each screen in the simulator and uploads them as the `screens` artifact,
including `design-<name>.png` for each of the eleven design directions.
`FitFight/ScreenshotExport.swift` runs when the app is launched with `FF_SHOOT=1`, renders
each screen with `ImageRenderer` (scroll views stay blank in that renderer, so `FFScreen`
switches to a plain stack via `\.ffStaticRender`) and writes PNGs the workflow copies out
of the simulator container.

An agent can pull them and measure them against the design:

```bash
gh run list --branch <branch> --workflow Screenshots --limit 1
gh run download <run-id> -n screens -D /tmp/shots
```

That is the fidelity loop: measure `docs/design/source/screenshots/app/*.png`, change the
SwiftUI, push, download `screens`, compare the same numbers. Don't ask Marc to eyeball it.

## GitHub secrets (already set)

Names only. Never print values. Never ask Marc to paste the `.p8` into chat.

| Secret | What it is |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key ID for key named `FitFight GitHub` (Admin) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID on Users and Access → Integrations |
| `APP_STORE_CONNECT_API_KEY` | Full `.p8` contents |
| `APPLE_TEAM_ID` | `C92DPD8ME2` |

There is a separate Expo EAS key in App Store Connect. Do not reuse it.

Do **not** add a Supabase `service_role` or `sb_secret_...` key to GitHub. Deploys use GitHub Integration. See [`backend.md`](backend.md).

## What Marc still does

- TestFlight install / Update when a build is ready (~10–20 min after a push).
- Internal testers (himself) vs external friends (first external build waits on Apple beta review ~1–2 days once).
- Apple account / legal / new secrets if they rotate.

He should **not** operate certificates day to day, open Xcode, or use a Mac for builds.

## Agent limits on GitHub

- `gh` here is effectively read-only for Actions (cannot `workflow_dispatch` or set secrets).
- Opening/updating PRs: use the PR tool, not `gh pr create`.
- Don’t merge unless Marc asks. He said docs go through a PR onto `main`.

## After you push app changes

The push starts TestFlight. Tell Marc: wait for the TestFlight notification, then **Update**. First processing of a new build is ~10–20 minutes. That is Apple, not GitHub. Do not ask him to merge first or Run workflow.

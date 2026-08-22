# Shipping

```
Marc (phone) → cloud Cursor agent → git
  → GitHub Actions (hosted macos-26 + Xcode 26)
  → Fastlane `beta` → TestFlight
  → Marc + friends
```

Not: agent on Marc’s laptop or home Mac → local Xcode.

## Workflows

| Workflow | File | When | Runner |
| --- | --- | --- | --- |
| Simulator | `.github/workflows/ios-build.yml` | PR + push to `main` | `macos-26` |
| TestFlight | `.github/workflows/ios-testflight.yml` | cron `0 18 * * *` UTC, and **Run workflow** | `macos-26` |

Both **must** stay GitHub-hosted. Never `self-hosted`. Apple requires **Xcode 26 / iOS 26 SDK** to upload (Xcode 16.4 / iOS 18.5 is rejected).

Fastlane: `fastlane/Fastfile` lane `beta`. Archive uses automatic signing + App Store Connect API key (`-allowProvisioningUpdates`). Do **not** also set `export_xcargs` to the same `-authenticationKeyPath` flags — gym passes `xcargs` into export and duplicates the flag.

Build number is not committed; CI sets `CURRENT_PROJECT_VERSION` at archive time.

## GitHub secrets (already set)

Names only. Never print values. Never ask Marc to paste the `.p8` into chat.

| Secret | What it is |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | Key ID for key named `FitFight GitHub` (Admin) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID on Users and Access → Integrations |
| `APP_STORE_CONNECT_API_KEY` | Full `.p8` contents |
| `APPLE_TEAM_ID` | `C92DPD8ME2` |

There is a separate Expo EAS key in App Store Connect. Do not reuse it.

## What Marc still does

- TestFlight install / Update (~30 min/day).
- Internal testers (himself) vs external friends (first external build waits on Apple beta review ~1–2 days once).
- Same-day extra build: **Actions → TestFlight → Run workflow** on `main`. This agent **cannot** dispatch workflows (GitHub 403).
- Apple account / legal / new secrets if they rotate.

He should **not** operate certificates day to day, open Xcode, or use a Mac for builds.

## Agent limits on GitHub

- `gh` here is effectively read-only for Actions (cannot `workflow_dispatch` or set secrets).
- Opening/updating PRs: use the PR tool, not `gh pr create`.
- Don’t merge unless Marc asks. He said docs go through a PR onto `main`.

## After you land app changes on `main`

Daily 18:00 UTC will pick them up. For a same-day phone test, tell Marc to Run workflow (one tap). First processing of a new build is ~10–20 minutes, then TestFlight → Update.

# Shipping

```
Marc (phone) → cloud Cursor agent → PR into develop
  → you try it on staging
  → merge develop → main when it should be production
  → App Store flow only when Marc asks
```

Not: agent on Marc’s laptop or home Mac → local Xcode.

## Workflows

| Workflow | File | When | Runner |
| --- | --- | --- | --- |
| Simulator | `.github/workflows/ios-build.yml` | PR + push to `main` or `develop` | `macos-26` |
| Screenshots | `.github/workflows/ios-screenshots.yml` | PR + push to `main` or `develop` | `macos-26` |
| TestFlight | `.github/workflows/ios-testflight.yml` | any non-`main` app `push`, plus a daily `develop` build at `0 18 * * *` UTC; `main` is blocked | `macos-26` |
| Database | `.github/workflows/database.yml` | PR + push to `main` or `develop` | `ubuntu-latest` |
| Delete merged branch | `.github/workflows/delete-merged-branch.yml` | PR merged | `ubuntu-latest` |

Both **must** stay GitHub-hosted. Never `self-hosted`. Apple requires **Xcode 26 / iOS 26 SDK** to upload (Xcode 16.4 / iOS 18.5 is rejected).

Fastlane: `fastlane/Fastfile` lane `beta`. Archive uses automatic signing + App Store Connect API key (`-allowProvisioningUpdates`). Do **not** also set `export_xcargs` to the same `-authenticationKeyPath` flags — gym passes `xcargs` into export and duplicates the flag.

Build number is not committed; CI sets `CURRENT_PROJECT_VERSION` at archive time from TestFlight (`latest + 1`). Leave `MARKETING_VERSION` at `0.9.0` (already on phones). Do not drop it — TestFlight will not offer `0.8.0` over an installed `0.9.0`.

## Versions vs builds (why friends wait)

Apple beta-reviews the **first build of each marketing version** for external TestFlight groups (~1–2 days). Later builds of the *same* version — `0.8.0 (13)`, `0.8.0 (14)` — usually skip that wait and show up after processing (~10–20 min).

That is why we do **not** bump `MARKETING_VERSION` on ordinary ships. We used to (0.4.1, 0.4.2, 0.5.0…) and every feature made testers wait for Apple again.

| What | Who sets it | When it changes |
| --- | --- | --- |
| Marketing version (`0.8.0`) | `MARKETING_VERSION` in `project.pbxproj` | App Store ship, or Marc asked |
| Build number (`13`) | CI / Fastlane at archive time | Every TestFlight upload |
| Versions list | `FitFight/Changelog.swift` | Every user-facing change; reuse `0.8.0` |

On-screen label is `0.8.0 (13)`. Testers tap Update; they do not need a new `0.8.x`.

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

## GitHub variables (TestFlight environment)

Names only. Never print values. Settings → Secrets and variables → Actions → Variables.

| Variable | Used when | What it is |
| --- | --- | --- |
| `SUPABASE_STAGING_URL` | every TestFlight | Persistent `develop` Supabase project URL |
| `SUPABASE_STAGING_PUBLISHABLE_KEY` | every TestFlight | Publishable key for that project (`sb_publishable_...`) |
| `FITFIGHT_API_URL` | every TestFlight | `https://staging.fitfight.app` |

Every TestFlight ships `https://zstzbfocunthczzubggz.supabase.co` (GitHub `SUPABASE_STAGING_*` variables override if set). The staging publishable key must be that project’s key, not production’s. Persistent `develop` must stay persistent so merging to `main` does not delete it. Scheduled workflows normally inherit GitHub's default branch, so TestFlight CI explicitly checks out `develop`. The top version label always shows `staging`. `main` never uploads to TestFlight.

Vercel also needs `CRON_SECRET` (Preview + Production). Vercel Cron sends it as `Authorization: Bearer …` to `/api/internal/close-fights` once daily at **03:00 UTC**, which is compatible with Hobby. Opening the app also closes due fights, so the cron is a safety net rather than the only close path. Never put this value in git or chat.

## What Marc still does

- TestFlight install / Update when a build is ready (~10–20 min after a push).
- Internal testers (himself) vs external friends. Internal: no Apple review. External: wait ~1–2 days **once per marketing version**, then later builds of that version skip the long review.
- Apple account / legal / new secrets if they rotate.

He should **not** operate certificates day to day, open Xcode, or use a Mac for builds.

## Feature branches

After a feature PR merges, CI deletes that branch. `main` and `develop` stay — we ship by merging `develop` into `main`, so GitHub’s “Automatically delete head branches” toggle must stay **off** (it would delete `develop`).

## Agent limits on GitHub

- `gh` here is effectively read-only for Actions (cannot `workflow_dispatch` or set secrets).
- Opening/updating PRs: use the PR tool, not `gh pr create`.
- Don’t merge unless Marc asks. Feature PRs go onto `develop`. Production is merging `develop` into `main`.

## After you push app changes

A non-`main` push starts TestFlight. Tell Marc: wait for the TestFlight notification, then **Update**. First processing of a new build is ~10–20 minutes. That is Apple, not GitHub. Do not ask him to merge first or Run workflow.

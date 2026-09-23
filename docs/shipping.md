# Shipping

```
Marc (phone) → cloud Cursor agent → PR into develop
  → merge develop → preview when you want a TestFlight
  → merge preview → main when it should be production
  → App Store flow only when Marc asks
```

Not: agent on Marc’s laptop or home Mac → local Xcode.

## Workflows

| Workflow             | File                                         | When                                                                                                                                             | Runner          |
| -------------------- | -------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ | --------------- |
| Simulator            | `.github/workflows/ios-build.yml`            | PR + push to `main`, `develop`, or `preview`                                                                                                     | `macos-26`      |
| Screenshots          | `.github/workflows/ios-screenshots.yml`      | PR + push to `main`, `develop`, or `preview`                                                                                                     | `macos-26`      |
| TestFlight           | `.github/workflows/ios-testflight.yml`       | push to `preview` (app/fastlane paths), plus optional `workflow_dispatch` on that branch. No cron. Feature branches and `develop` do not upload. | `macos-26`      |
| App Store candidate  | `.github/workflows/ios-app-store.yml`        | app push to `main`; uploads only and never submits for review                                                                                    | `macos-26`      |
| Database             | `.github/workflows/database.yml`             | PR + push to `main`, `develop`, or `preview`                                                                                                     | `ubuntu-latest` |
| Delete merged branch | `.github/workflows/delete-merged-branch.yml` | PR merged                                                                                                                                        | `ubuntu-latest` |

The iOS workflows **must** stay GitHub-hosted. Never `self-hosted`. Apple requires **Xcode 26 / iOS 26 SDK** to upload (Xcode 16.4 / iOS 18.5 is rejected).

Fastlane: `fastlane/Fastfile` lane `beta` uploads staging TestFlight builds. Lane `app_store_candidate` is CI- and `main`-only, archives Release with production configuration, and uploads the binary to App Store Connect without selecting it or submitting it for review. Both use automatic signing + App Store Connect API key (`-allowProvisioningUpdates`) and share one non-cancelling concurrency group so signing and build-number allocation cannot race. The production lane does not revoke team certificates; it fails safely if automatic signing cannot create one. Do **not** also set `export_xcargs` to the same `-authenticationKeyPath` flags — gym passes `xcargs` into export and duplicates the flag.

Build number is not committed; CI sets `CURRENT_PROJECT_VERSION` at archive time from TestFlight (`latest + 1`). The next prepared marketing version is **1.1.2**, requested by Marc on 17 Sep 2026 for the App Store description update. See `status.md` for uploaded builds. Apple closed the 1.0.0 train, so do not upload 1.0.0.

## Selective Cursor Bugbot reviews

The prepared policy runs Bugbot for ready PRs targeting `preview` or `main`,
PRs labeled `origin:cursor`, and same-repository branches beginning `cursor/`.
Other development PRs leave Bugbot optional. Cursor cloud agents add the label
when opening an authorized PR, including when using Grok. The workflow also adds
it to detected Cursor branches. The label identifies the workflow that produced
the work, not a model inferred from the diff or GitHub author.

`.github/workflows/bugbot-review.yml` uses `pull_request_target` and reads code
only from the trusted default-branch SHA. It never checks out or executes PR
code. GitHub runs this event from `main`, so merging only into `develop` does
not activate it. Its repository variable `BUGBOT_ROUTING_ENABLED` must be
`true`; otherwise it makes no review requests.

The workflow fetches current PR metadata, skips drafts and closed PRs, and
serializes requests per PR. A marker records the head commit and base branch
and commit in the trigger comment. Repeated events for that diff do not post
again. A new commit or changed destination can request another review. Only
markers posted by the configured trigger account count as previous requests.
This deduplicates requests, not successful reviews; a failed Bugbot run can be
retried with a manual `cursor review` comment by an authorized user.

Activation order for an agent with the required access:

1. Store a dedicated GitHub user token as the `BUGBOT_GITHUB_TOKEN` repository
   secret. Limit it to FitFight with Pull requests read/write access. The user
   must have access to Bugbot for this repository. Do not reuse an interactive
   agent's GitHub credential. The normal Actions token is used only to read
   unselected PRs when this secret is absent; selected reviews fail without it.
2. Land the workflow and its script on `main` through separately authorized
   PRs and merges. Marc's authorization is still required for every merge.
3. Set Bugbot to manual-only while keeping the repository enabled. For a team,
   the documented admin setting is `manualTriggerOnly: true`. For a personal
   account, verify that "Run only when mentioned" covers the actual PR authors.
4. Set `BUGBOT_ROUTING_ENABLED=true`. Verify a Conductor development PR receives
   no automatic review, a Cursor PR receives one, both release targets receive
   one, and a new commit requests a fresh review without duplicate comments.
5. Activate the prepared `Bugbot before release merges` ruleset only after
   verifying live trigger delivery. Its payload is
   `.github/bugbot-release-ruleset.json`; it starts disabled and targets only
   `preview` and `main`. The expected check is `Cursor Bugbot` from Cursor's
   GitHub App, ID `1210556`, verified on an existing FitFight check run.

The ruleset requires a PR, the Bugbot check, and resolved review threads.
Bugbot normally reports findings as `neutral`, which GitHub accepts for required
checks. Enable Cursor's fail-on-unresolved-issues setting if available and verify
it before claiming findings block a release. Thread resolution is not proof
that a finding was fixed, and an internal Bugbot error may also be neutral.

If activation fails, restore Cursor's automatic reviews before disabling
`BUGBOT_ROUTING_ENABLED`. Do not disable Bugbot for the repository, since that
also removes the ability to request manual reviews.

References: [Cursor Bugbot configuration and check behavior](https://cursor.com/docs/bugbot),
[GitHub's default-branch execution for pull_request_target](https://github.blog/changelog/2025-11-07-actions-pull_request_target-and-environment-branch-protections-changes/).
Current activation evidence is recorded in [status](status.md#selective-bugbot-reviews-prepared-17-sep-2026).

## Versions vs builds (why friends wait)

External TestFlight builds must be submitted for beta review and distributed to their tester groups. Apple fully reviews the first submitted build; later builds of the same marketing version may receive a shorter review, but approval is not guaranteed or immediate. Stay on **1.1.2** for follow-up builds. See [Apple's external testing rules](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers).

We used to bump 0.4.1, 0.4.2, 0.5.0 on every feature, so friends waited every time. Stay on **1.1.2** until Marc asks or Apple closes that train.

| What                        | Who sets it                              | When it changes                                               |
| --------------------------- | ---------------------------------------- | ------------------------------------------------------------- |
| Marketing version (`1.1.2`) | `MARKETING_VERSION` in `project.pbxproj` | App Store ship, Apple closed the train, or Marc asked         |
| Build number (`105`)        | CI / Fastlane at archive time            | Every distribution upload                                     |
| Versions list               | `FitFight/Changelog.swift`               | Every user-facing change; reuse the current marketing version |

The next version label is `1.1.2 · build N · staging`. Testers tap Update after upload and availability; ordinary follow-up builds keep `1.1.2` and only increment the build number.

### Everyone: Internal, External, Friends Beta

The beta lane waits for build processing, then assigns **every** TestFlight group: Internal testers (automatic after processing; Apple rejects assigning them by hand), every External group, and **Friends Beta** (`https://testflight.apple.com/join/wcZKdwVZ`). Missing Internal testers, missing Friends Beta, or missing all External groups fails CI. Uploaded builds are registered separately from the latest _installable_ (external) release. The advertised public release advances only after a build is `IN_BETA_TESTING` on every external group. TestFlight update prompts are optional in the prepared 1.1.1 app, so Friends can keep using their installed build.

Marc must be on **Internal Testing** in App Store Connect (Users and Access) to see new preview uploads. External testers and Friends wait for Apple beta review on the first 1.1.2 build, then later 1.1.2 builds of the same version.

Apple allows only one build per version in beta review at a time and up to six beta review submissions in 24 hours. Upload limits are separate: the 5 Sep runs failed with `Upload limit reached` after build **153** uploaded successfully. Creating more builds does not release one already waiting for external review.

For the 5 Sep invitation report, build **114** (`d1a3534`, uploaded 2 Sep) still writes directly to `fight_members` when accepting or declining a username invitation. The server-owned-writes migration now denies those operations. Build **153** (`bc3795a`, uploaded 4 Sep) uses the authenticated backend commands. Historical unblock for friends was TestFlight → Friends Beta, Submit Review or Start Testing, Automatically notify testers. Friends then open TestFlight → FitFight → Update. Apple approval and each phone's installation timing remain outside CI's control.

Before a future migration removes an operation used by installed apps, verify that a compatible build is actually available to the external group. An uploaded internal-only build is insufficient. Preserve compatibility during rollout; do not reopen direct membership or score writes to support an old binary.

Run the release regression checks with `bundle exec ruby fastlane/testflight_test.rb`. They execute the beta lane with Apple and signing actions replaced by test doubles; they do not upload a build or verify a tester's live Apple account.

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

The simulator build also exports `FitFight-Simulator`. Xcode uses the ad-hoc identity
(`CODE_SIGN_IDENTITY=-`) with signing enabled so it embeds iOS entitlements in the
simulator executable. `scripts/package_simulator_app.py` verifies these Mach-O sections
and the signature before archiving. Do not add iOS entitlements to the host Mac code
signature afterward; that can prevent Simulator from launching the app.
A raw `CODE_SIGNING_ALLOWED=NO` build lacks the embedded capabilities and can fail
Google sign-in when the SDK saves credentials. The screenshot workflow checks this
on a disposable hosted simulator: the probe without embedded capabilities must return
`-34018`, and add/read/delete must succeed with Xcode's generated simulator entitlements.
This checks secure storage; a real Google consent and Supabase session exchange still
need interactive testing. Before that exchange, the app asks the staging or production
API to attach Google to an existing account with the same verified email, including
an Apple identity email. Hide My Email addresses do not match a Google inbox. The
artifact installs only in Simulator, not on an iPhone or through TestFlight.

## GitHub secrets (already set)

Names only. Never print values. Never ask Marc to paste the `.p8` into chat.

| Secret                        | What it is                                     |
| ----------------------------- | ---------------------------------------------- |
| `APP_STORE_CONNECT_KEY_ID`    | Key ID for key named `FitFight GitHub` (Admin) |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID on Users and Access → Integrations   |
| `APP_STORE_CONNECT_API_KEY`   | Full `.p8` contents                            |
| `APPLE_TEAM_ID`               | `C92DPD8ME2`                                   |

There is a separate Expo EAS key in App Store Connect. Do not reuse it.

### Still needed for crash reports

Names only. Never print values. Never paste the PostHog project token in chat.

| Secret                    | Used when                                     | What it is                                                   |
| ------------------------- | --------------------------------------------- | ------------------------------------------------------------ |
| `POSTHOG_PROJECT_API_KEY` | TestFlight (`preview`) and App Store archives | PostHog **project** API key (`phc_...`). Crash reports only. |

Optional Actions **variable** `POSTHOG_HOST`: `https://us.i.posthog.com` (default) or `https://eu.i.posthog.com` if the PostHog project is EU Cloud. In PostHog, turn on error-tracking exception autocapture and leave session replay off.

Do **not** add a Supabase `service_role` or `sb_secret_...` key to GitHub. Deploys use GitHub Integration. See [`backend.md`](backend.md).

## GitHub variables (TestFlight environment)

Names only. Never print values. Settings → Secrets and variables → Actions → Variables.

| Variable                           | Used when                          | What it is                                                                                            |
| ---------------------------------- | ---------------------------------- | ----------------------------------------------------------------------------------------------------- |
| `SUPABASE_STAGING_URL`             | every TestFlight                   | Persistent `develop` Supabase project URL                                                             |
| `SUPABASE_STAGING_PUBLISHABLE_KEY` | every TestFlight                   | Publishable key for that project (`sb_publishable_...`)                                               |
| `FITFIGHT_API_URL`                 | every TestFlight                   | `https://staging.fitfight.app`                                                                        |
| `POSTHOG_HOST`                     | TestFlight and App Store, optional | PostHog ingest host. Default `https://us.i.posthog.com`. Use `https://eu.i.posthog.com` for EU Cloud. |

Every TestFlight ships `https://zstzbfocunthczzubggz.supabase.co` (GitHub `SUPABASE_STAGING_*` variables override if set). The staging publishable key must be that project’s key, not production’s. Persistent `develop` must stay persistent so merging to `main` does not delete it. TestFlight CI builds the `preview` commit that triggered it. The You version label always shows `staging`. `main` never uploads to TestFlight.

## App Store production candidate

An app change merged to `main` starts `.github/workflows/ios-app-store.yml`. It waits until all four production routes are live and valid:

- `https://fitfight.app/api/health`
- `https://fitfight.app/api/app-release`
- `https://fitfight.app/privacy`
- `https://fitfight.app/support`

The workflow injects the production Supabase project, its iOS publishable key, and `https://fitfight.app` into `BuildEnv.swift`. Before upload it verifies the production Supabase URL/key, confirms its Apple provider is enabled, and requires the API health check to prove the production database, latest deletion migration, server key, and Apple server credentials are ready. It then checks the signed IPA for HealthKit background delivery, a valid privacy manifest, and the production configuration, and rejects any generated staging configuration. The public defaults match the values already compiled in the app; optional repository variables `SUPABASE_PRODUCTION_URL` and `SUPABASE_PRODUCTION_PUBLISHABLE_KEY` can rotate them, but the URL must remain the documented production project and the key must validate against it.

Fastlane increments only the build number. The workflow requires the project marketing version to equal `FITFIGHT_RELEASE_VERSION` (`1.1.2`) and requires a matching `1.1.2` release note. The reviewed App Store release PR into `develop` carries that version and launch note. Marc then merges `develop` → `preview` when he wants a TestFlight, and `preview` → `main` when he approves the production ship. The workflow does not change `MARKETING_VERSION`, upload metadata or screenshots, submit the build for review, or release it. After it succeeds, the candidate waits in App Store Connect for the separate metadata, review-information, build-selection, and submission steps.

**Automatic publication is the standing default**, requested by Marc on 17 Sep
2026. For every App Store version, select **Automatically release this version**
and verify it before submitting. Apple publishes the approved version without a
manual Release action. See [Apple's release options](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option).

`scripts/app-store-release-audit.rb` reads the target version from
`FITFIGHT_RELEASE_VERSION`. Its authorized `configure`, `prepare`, and `submit`
modes set `releaseType: AFTER_APPROVAL`; `configure` stops after saving that
setting. Submission still requires an explicit registered
production build and a healthy production backend. The script verifies automatic
publication after submission. The push-triggered release-tools workflow remains
an audit. Existing PR, merge, and submission authorization rules still apply.

Vercel also needs `CRON_SECRET` in Production. Once `web/vercel.json` reaches `main`, Vercel Cron calls `/api/internal/close-fights` every **15 minutes** with `Authorization: Bearer <secret>`. This interval requires Pro or Enterprise. Vercel Cron runs only on Production, so staging Preview needs `CRON_SECRET` there and the separate **hosted Supabase Cron** job in `supabase/deferred-migrations/20260911153000_supabase_cron_15m.sql`. Its Vault `cron_secret` must match the Preview value. That job calls the same protected route every 15 minutes for fight-end sync reminders (T+0, 12h, 6h, 1h left). Opening the app also closes due fights and drains the notification outbox. Cron delivery is best effort; the next scheduled run is the normal target, not an exact-second guarantee. Never put either secret in git or chat.

Vercel Preview + Production also need the FitFight APNs secrets from [`docs/research/apns-remote-push-plan.md`](research/apns-remote-push-plan.md): `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, `APNS_TOPIC`, and `APNS_TOKEN_ENCRYPTION_KEY` (separate from Sign in with Apple). Without them the outbox enqueues intents but send stays a no-op.

## What Marc still does

- Be listed under App Store Connect **Internal Testing** so new `preview` uploads appear in TestFlight (no beta review).
- TestFlight → Update when a new _internal_ build is ready (~10–20 min after a `preview` push). Friends Beta is submitted in the same upload; Apple beta review may still delay the public join link.
- Friends: TestFlight → Update, or https://testflight.apple.com/join/wcZKdwVZ after Apple approves. Friends can enable Automatic Updates inside TestFlight.
- Apple account / legal / new secrets if they rotate.
- After a production candidate passes: finish the App Store Connect metadata and review information, select the uploaded build, and explicitly submit it when ready.

He should **not** operate certificates day to day, open Xcode, or use a Mac for builds.

## Feature branches

After a feature PR merges, CI deletes that branch. `main`, `develop`, `preview`, and `testflight-latest` stay — we ship by merging `preview` into `main`, so GitHub’s “Automatically delete head branches” toggle must stay **off** (it would delete `develop`). `testflight-latest` stores public release metadata (`releases.json`), the builds that contain the update gate (`builds.json`), and `latest.json` for older TestFlight notices; it is not app code.

## Agent limits on GitHub

- `gh` here is effectively read-only for Actions (cannot `workflow_dispatch` or set secrets).
- Opening/updating PRs: use the PR tool, not `gh pr create`.
- Don’t merge unless Marc asks. Feature PRs go onto `develop`. TestFlight is merging `develop` → `preview`. Production is merging `preview` into `main`.

## After you push app changes

A push to `preview` that touches the app or Fastlane starts TestFlight. Feature-branch and `develop` pushes do not. Tell Marc only after that upload: wait for the TestFlight notification, then **Update**. Tester gets it after processing. Friends wait for Apple beta review on a new marketing version. Check the workflow result before promising a build. Do not ask him to Run workflow.

Both staging and production binaries check `/api/app-release` at launch, on foregrounding, and every minute while active. In the prepared 1.1.1 app, TestFlight only offers a newer public `latest`, never an internal/review-only update. Cancel keeps the app usable and dismisses that release across checks and relaunches. Failed checks clear the TestFlight notice, and saved locks from older binaries are ignored. Production keeps its mandatory update gate. The version line remains on You only.

## API compatibility for every change

The app explicitly calls `/api/v1` through `FitFightAPI`. Its marketing version and
build travel separately in `X-FitFight-Version` and `X-FitFight-Build` for update
enforcement. Database migrations version storage independently. There is currently
no `/api/v2` or automatic selection of an API version from the build number.

Use `/api/v1` for ordinary releases. Decide whether a change is compatible by checking
the requests, decoded responses, and behavior of supported installed apps:

| Change                                                                                  | Required treatment                                                                                                          |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| UI change, new endpoint, or compatible bug fix                                          | Keep the API version.                                                                                                       |
| New optional request field                                                              | Keep the existing behavior when older apps omit it.                                                                         |
| New response field                                                                      | Verify older decoders ignore it; extra fields alone must not expose unsupported behavior.                                   |
| Rename/remove an API field, change its type/nullability/meaning, or make input required | Preserve the existing contract, or introduce an incompatible version for the affected endpoint while retaining the old one. |
| New enum value                                                                          | Check old decoders and behavior; a new value can break an old app even though the field is unchanged.                       |
| Internal column rename/type change, new constraint, or permission change                | Stage the database/backend transition; preserve supported API behavior, old writers, and running backend versions.          |

For a future `/api/v2/fights`, keep `/api/v1/fights` as the old contract while it is
supported. Both handlers may call shared business logic and the same database;
rebuild neither the database nor unrelated routes. Explicitly update the native
request path for that endpoint when needed. Do not add a version router or duplicate
all routes in anticipation of a future change.

For each affected contract, agents must:

1. Read the affected environment's live `/api/app-release` and identify the public,
   internal, and review builds it admits. Preserve legacy behavior too while backend
   enforcement is off. Inspect the relevant released client code/contracts; the
   manifest identifies builds but does not prove their compatibility. Staging changes
   reach Friends Beta's database on `develop`, before any new TestFlight upload.
2. Describe how old requests and responses remain valid. For storage changes, add
   support first, deploy compatible backend code, backfill and maintain concurrent
   writes consistently, then switch storage usage. Keep the public API shape stable
   when the change is internal. Do not put a later incompatible cutoff in the same
   automatically applied migration batch.
3. Preserve representative requests/responses for affected supported clients. Test
   old requests against the new handlers and new responses against the old decoding
   expectations, alongside the new contract. Schema changes also need those database
   paths checked against the migrated disposable cloud database. Do not overwrite
   the previous contract fixtures to bless a breaking change.
4. Use the [rollout sequence below](#mandatory-updates-and-database-rollout). Upload,
   approval, and actual installability are separate. Admit the review candidate
   before Apple tests it. Remove behavior needed by retired clients only after
   verifying the replacement is installable and required; include admitted candidates
   and running backend versions in that decision. A purely internal cleanup can happen
   sooner when all supported contracts remain intact.

Existing CI checks the native database boundary, release selection, update blocking,
shared profile/Fight fixtures, backend tests, and disposable database migrations/RLS.
It does **not** automatically compare every released binary against every new schema
or detect every semantic API break. The SQL guard catches selected destructive SQL,
not all incompatible constraints, renames, or grants. Add regression coverage for the
actual affected contract; follow [AGENTS.md](../AGENTS.md#mobile-api-and-database-compatibility--every-agent).

## Mandatory updates and database rollout

**TestFlight updates are optional; production retains mandatory updates.** This policy is prepared in the workspace on 15 Sep 2026 at Marc's request. The staging backend always serves `enforced: false` and does not return `426` for version/build mismatches, even if the publisher still records enforcement in its raw manifest. Authentication and account checks still apply. The next prepared TestFlight marketing version is `1.1.1`; build numbers distinguish follow-up releases. Production has no independently adjustable minimum.

`fastlane refresh_app_releases` reads Apple availability. A staging build must be valid, unexpired, in `IN_BETA_TESTING`, and assigned to every external group to become `latest` (Friends Beta / public join). The newest registered VALID staging build that is newer than that public latest is `internal` and is also copied into `review` so existing binaries stop prompting Internal testers who already installed it. Production uses only `READY_FOR_DISTRIBUTION` App Store versions and their exact build; `PROCESSING_FOR_DISTRIBUTION` is not installable yet. A registered staging build waiting for or in beta review is separately admitted. For production, the registered build selected in App Store Connect is admitted for review; uploading or submitting it never replaces the public release. The public registry contains only channel/version/build numbers, no Apple credentials.

Upload workflows register binaries that contain the update dialog. For production, the first installable release containing it activates backend enforcement automatically; enforcement cannot silently revert to a binary lacking the gate. Staging overrides the publisher's flag so future uploads cannot restore the TestFlight API lock. Older TestFlight binaries ignore `enforced` in their own overlay logic: deploying the backend alone cannot add Cancel or clear every cached native lock. They need to install the new native build once.

`.github/workflows/app-releases.yml` refreshes availability every 15 minutes on GitHub-hosted Linux, using the existing App Store Connect secrets. Upload jobs also refresh it. All publishers share `ios-distribution` concurrency and preserve the pointer branch history. GitHub schedules only run once the workflow exists on the default branch; include it in the normal production promotion before relying on updates after Apple review. Scheduling and Apple's availability propagation can delay the requirement; the app does not pretend that upload success means installation is possible.

Deployment order:

1. Publish `releases.json` from the cloud workflow before deploying the new version checks. It initially records the existing installable release with enforcement off if that binary predates the gate. The server selects staging or production from the existing `NEXT_PUBLIC_SUPABASE_URL`; client headers cannot choose another release channel. Deploy `/api/app-release` and the compatible backend before distributing the new native build. GET `/api/app-release` still returns `503` when this environment's channel cannot be read. Authenticated commands fail open on that failure so Feed and other tabs stay usable. Pad two-part App Store versions (`1.0` → `1.0.0`) so a production row cannot invalidate the staging policy. Never advertise a build that is not actually installable.
2. Database changes must preserve supported API contracts and running backend versions. Internal column renames, constraints, and cleanup do not automatically wait for Apple; stage backend/database changes as needed. During review, preserve the API behavior and information required by both the live app and its candidate. New response fields must be ignored by old decoders; new request fields must not become required for supported clients.
3. After a production build is selected for submission, verify that `/api/app-release` identifies it as `review` before Apple tests it. The live public app keeps working. This check does not submit or release anything.
4. When Apple makes the update installable for Friends Beta (every external group), the publisher makes that exact version/build the advertised `latest` automatically. TestFlight shows a cancellable notice only when this release is newer than the installed app. Internal/review builds remain recorded for older clients but are never offered to other testers. Production alone returns `426 update_required` for missing or mismatched version/build headers when enforcement is on, unless they match an admitted release.
5. Retire API behavior needed by an older app only after a separately approved compatibility cutoff. Optional TestFlight updates do not establish that cutoff: preserve installed clients' contracts and do not apply deferred permission removals based on the published `latest`. Production still requires installability and enforcement evidence, including admitted review candidates. Internal database cleanup can happen sooner if supported APIs and running backends remain compatible. The update gate does not secure direct table access or replace RLS. Follow existing migration/merge authorization rules.

For the initial profile migration: apply `20260909132922_backend_profile_reads.sql`, deploy
`GET/PATCH /api/v1/me` and the backend using `fitfight_backend_reader`, verify readiness,
then distribute the native build. Preserve old client grants during this stage. Only
later promote the cutoff from [`supabase/deferred-migrations`](../supabase/deferred-migrations/README.md),
after installability, enforcement, review-candidate compatibility, staging checks, and
old-backend drainage are verified. CI tests both permission states on disposable Supabase.

Verification: Ruby release tests cover review, group availability, expiry, the first gated rollout, internal-only TestFlight latest, and production candidates. Backend tests cover old/current/new TestFlight headers, advisory metadata, authentication, and production enforcement. The GitHub-hosted macOS simulator workflow runs `tests/AppUpdateCheckerTests.swift` for TestFlight cancellation during a check, persistence across relaunches, stale metadata/426 recovery, public-only offers, API access, and the existing production gate. Check both English and French, Cancel, launch/resume, and the store link on a real staging build before shipping. Deploy the compatible backend through an authorized `develop` promotion first, verify staging no longer rejects old headers, then distribute the native change through `preview`.

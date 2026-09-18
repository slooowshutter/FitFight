# FitFight status: what works, what’s fake, what’s next

Read this before building. Last updated **18 Sep 2026**. Production candidate: **1.1.1 (202)**.

Do **not** restore removed surfaces. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, or a broader marketing site unless the [Notion Product Backlog](https://app.notion.com/p/3d38907c7ecf816facdff36cb59f463e) says so. Fight posts, the Feedback tab, challenge-reminder pushes, and feed social notifications are in this build. Only the public privacy and support pages exist on the web.

---

**Last TestFlight:** 15 Sep 2026 at 22:16 UTC. **1.1.1 (201)** from [#243](https://github.com/slooowshutter/FitFight/pull/243). Apple processing is `VALID`. Internal Tester receives it; Friends Beta is assigned the same IPA and waits for Apple beta review (`WAITING_FOR_BETA_REVIEW`). The published release manifest lists `latest` 190, `review` 200, and `internal` 201.

## Develop merge verification, 18 Sep 2026

Merged `origin/develop` at `f17a456` into `feedback-status-notifications`. The
resolution retains shared-membership Profile visibility, onboarding HealthKit sync,
separate Feedback comment buttons, and deferred feedback progress. It incorporates
the incoming Profile statistics, saved time zones, Feed, companion, administration,
and release configuration changes. History uses `develop`'s explicit selected-round
navigation. Calendar-day rematch data takes precedence when present; older responses
retain the saved-time-zone and exact-duration behavior.

The original Profile expansion migration from `develop` already creates private
history identifiers. The redundant, undeployed follow-up migration was removed;
the merged backfill checks retain both scheduled-result and identifier-isolation
coverage. `/api/v1` and the optional `membershipState` and `duration_days` additions
remain compatible. Frozen build 201/202 decoders and legacy request fixtures are
unchanged.

**Cloud checks passed on `6a060e2`:**

- [Web API](https://github.com/slooowshutter/FitFight/actions/runs/35352310881):
  strict typecheck, all 315 backend tests, and API contract parsing.
- [Database](https://github.com/slooowshutter/FitFight/actions/runs/35352310911):
  schema lint, 228 pgTAP checks, all 40 integration tests before and after the
  deferred permission cutoff, build 113 compatibility, and historical
  backfill/deletion rehearsals. Supported-client HTTP cases include builds
  113, 190, 200, 201, 202, and 203.
- [iOS simulator](https://github.com/slooowshutter/FitFight/actions/runs/35352310913):
  app compilation on GitHub-hosted `macos-26`, all native regression checks from
  both branches, and English/French validation passed.
- [Bugbot routing tests](https://github.com/slooowshutter/FitFight/actions/runs/35352310894)
  passed for the incoming workflow.

The validation snapshot matches the merged app, backend, migrations, and tests.
Only this evidence record and isolated CI/deployment configuration differ.
Read-only release checks still show staging latest 1.1.1 (201), review/internal
1.1.2 (203), enforcement off; production latest 1.1.1 (202), no candidates,
enforcement on. No live deployment occurred. Existing rollout order remains
additive migrations, compatible backend, then an authorized native release.
Installed-device HealthKit, interaction, and accessibility checks remain outstanding.

## Profile interaction fixes, 18 Sep 2026

**Code prepared, not deployed.** Joining a Suggested Fight during onboarding now
waits for the existing post-membership HealthKit sync, standings refresh, and offer
reload. The sync reads the newly joined Fight windows instead of coalescing with an
earlier sync. Continue and Skip stay disabled during the join; account changes stop
the old screen from publishing a later response.

Profile history opens the exact selected round through navigation and subsequent
refreshes. The main Fight list and Feed/deep links still select the current round
when opening it. In Feedback, the author opens their Profile and the separate
comment-count button opens the request discussion, both with 44-point tap targets.

**Contract:** these are native interaction changes using existing `/api/v1` requests
and models. No API field, database schema, or frozen client fixture changed. The
previous release-policy observations and backend compatibility checks below still
apply. The new English/French release note keeps marketing version **1.1.1**.

**Cloud checks passed on `b5b6bf2`:**

- [iOS simulator](https://github.com/slooowshutter/FitFight/actions/runs/35349335903):
  the GitHub-hosted `macos-26` app build, English/French validation, existing native
  regressions, and the new onboarding/navigation interaction checks passed.
  Suspended API and HealthKit boundaries verify join-before-sync ordering, no
  coalescing with earlier windows, repeated taps, rejected joins, account changes,
  selected finished/pending rounds, final-sync refreshes, and current-round Feed links.
- [Database](https://github.com/slooowshutter/FitFight/actions/runs/35349335792):
  all 35 integration tests passed before and after the deferred client-permission
  cutoff, with schema lint, pgTAP, build 113 compatibility, and deletion rehearsals.
  Supported-build HTTP coverage remains unchanged.
- Backend code is unchanged from the [277-test Web API run](https://github.com/slooowshutter/FitFight/actions/runs/35347391067)
  recorded below, including its strict typecheck and contract parsing.

The [initial interaction run](https://github.com/slooowshutter/FitFight/actions/runs/35349065629)
reproduced the missing sync and wrong-round navigation before the fixes. The passing
snapshot matches the workspace's app, backend, and test contents; only documentation
and isolated CI/deployment configuration differ. Feedback tap routing was checked
in the view code. Real-device HealthKit, tap, and VoiceOver checks remain after an
authorized release. No PR, merge, TestFlight upload, or deployment was performed.

## Shared Fight list correction, 18 Sep 2026

**Code prepared, not deployed.** Another person's Profile now requests **Fights
together**, regardless of their Competitive/Public settings. Both people must still
have accepted or deferred membership in the round and, when present, its series.
Scheduled, live, finished, and cancelled shared rounds remain eligible. Leaving a
series hides its older rounds from this list even when their frozen results remain.
The standalone Rivalry Rematch button is removed. A person's own result history
and historical competitive totals are unchanged.

**Contract:** `/api/v1/profiles/{userID}/history?shared=true` now applies current
shared membership before pagination. Response fields and cursors keep their existing
shapes. The existing nullable `rivalry.rematch` field also requires current shared
membership, preventing private action text from leaking through historical scores.
No database schema change or fixture replacement is required for this correction.

**Cloud checks passed on `5119c57`:**

- [Web API](https://github.com/slooowshutter/FitFight/actions/runs/35347391067):
  strict typecheck, all 277 backend tests, and API contract parsing.
- [Database](https://github.com/slooowshutter/FitFight/actions/runs/35347391089):
  disposable migrations, schema lint, pgTAP, build 113 compatibility, and all 35
  integration tests before and after the deferred client-permission cutoff.
  The existing HTTP cases for builds 113, 190, 200, 201, 202, and 203 still pass.
- [iOS simulator](https://github.com/slooowshutter/FitFight/actions/runs/35347391041):
  GitHub-hosted `macos-26` app build, English/French validation, Profile state tests,
  unchanged frozen build 201/202 decoders, and existing native regressions.

The new regressions cover departure by either person, series departure with retained
old-round membership, scheduled/final/cancelled rounds, private/Casual profiles, and
pagination. The first cloud run reproduced the shared-history and native filter
failures before implementation. This snapshot checked the shared-list changes;
the subsequent native interaction fixes are recorded above.
The live release policies remain as recorded below. These are cloud test results,
not installed-client or live deployment evidence.

**Remaining:** the per-Fight new-week action is not implemented while the choice
between another round in the original series and a separate Fight is pending.
The three other review findings are addressed above. Deploy the branch's existing
additive Profile migrations, then the compatible backend, then an authorized native release.
Neither environment was changed; installed-device checks remain after rollout.

## Feedback progress deferred, 18 Sep 2026

Marc deferred request progress tracking. The current branch removes its status and
Next UI, status command, automatic system comments, Send approval/build transitions,
workflow configuration, and unapplied two-column migration. Ordinary feedback,
votes, user comments, author Profile links, and the existing explicit Send to Cursor
remain. Profiles, Friends, rivalries, Suggested Fights, and their review fixes stay.
The [proposal](proposals/feedback-workflow.md) and [historical plan](proposals/feedback-implementation-plan.md)
are marked deferred. A Notion backlog entry is pending a connected Notion account.

**Contract:** `/api/v1` is unchanged. Feedback uses its existing request/response
contract, with the retained optional comment `author_id` for shared Profiles.
The removed workflow fields and endpoint were unreleased. Frozen build 201/202
feedback decoders and the old response fixture remain unchanged; current Profile
responses receive a separate fixture. No hosted schema or data was changed.

**Live policy observation, 18 Sep:** staging latest **1.1.1 (201)**, review/internal
**1.1.2 (203)**, enforcement **off**; production latest **1.1.1 (202)**, no
review/internal candidates, enforcement **on**. These were read-only observations,
not deployments or installed-client tests. Legacy staging clients still require
compatibility while enforcement is off.

**Cloud verification passed on `e798399`:**

- [Web API](https://github.com/slooowshutter/FitFight/actions/runs/35339092473):
  strict typecheck, all 276 backend tests, and API contract parsing.
- [Database](https://github.com/slooowshutter/FitFight/actions/runs/35339092545):
  disposable migrations, schema lint, pgTAP, build 113 compatibility, and all 33
  integration tests before and after the separately deferred client-permission
  cutoff. Deletion and historical backfill rehearsals also passed. Feedback HTTP
  requests cover builds 113, 190, 200, 201, 202, and 203, ordinary comments/votes,
  optional Profile author IDs, metadata privacy, and authorized explicit Send.
  A controlled provider response verifies Send without launching a real agent.
- [iOS simulator](https://github.com/slooowshutter/FitFight/actions/runs/35339092465):
  GitHub-hosted `macos-26` app build, English/French validation, frozen build 201/202
  feedback decoding, Profile access/state tests, rematches, and existing native
  regressions. Build 203 is covered by HTTP headers, not a separately frozen decoder.

The validation snapshot matches the workspace's app, backend, migrations, and tests.
Its only configuration differences select the isolated validation branch for CI and
disable that branch's Vercel deployment. All 21 pre-existing Profile/discovery fixes
were checked unchanged against the starting workspace. These cloud checks do not
constitute a live deployment or installed-device verification.

**Rollout:** no workflow schema/configuration step is needed. Retained Profile
migrations still precede compatible backend code and a separately authorized native
release. No branch merge, PR, TestFlight upload, or production deployment was performed.
Signed-in device checks remain after rollout.

### Retained Profile review fixes, 17 Sep 2026

Suggested Fight cards now distinguish invitations from accepted/deferred membership.
The `/api/v1` list response adds optional `membershipState` without changing
`alreadyMember`, so existing clients retain their contract. New native cards keep
invitations actionable on both New and onboarding.

Rematches add optional `duration_days`, calculated in the original Fight's time
zone, while preserving `duration_seconds` and `action_text`. Native composition uses
calendar days for the existing presets, including Fights spanning either clock
change. Older responses without the new field still decode.

Profile history rows and cursors now use stable, random identifiers for each
participant's record. After merging `develop` on 18 Sep, these identifiers are part
of the original Profile expansion migration. The redundant, undeployed follow-up
migration was removed. Identifiers remain stable during participation updates.
A reader with Fight access still receives the real `fight_id`; other readers
cannot correlate participants through identical IDs. Profiles remain an unreleased
contract; installed builds 113, 190, 200, 201, and 202 do not use these history cursors.

## Companion descriptions and habitat tabs: prepared 17 Sep 2026

**Code:** choosing a stock animal keeps the saved custom description. The picker
has All, Yours, Make it yours, Mountains, Water, Forest, and Jungle tabs using
the 12 existing animals. Yours reuses saved descriptions without duplicates; the account library
also works on another device. Local caches are scoped to the user, hidden while
signed out, and removed on account deletion. English/French copy and a 1.1.2 release
note are included. This is a description library, not image generation. Additional
species and their artwork are not implemented. Previously erased descriptions
cannot be reconstructed from the current profile.

**Contract and rollout:** `GET /api/v1/me/companions` is a new authenticated read
returning a string array. Existing profile requests/responses and `/api/v1` remain
unchanged, including null `companion_prompt` for stock animals. The additive
`20260917010915_saved_companion_prompts.sql` migration backfills current descriptions
into a private library. An internal capture trigger preserves subsequent writes
from both older and newer backends; there is no app-facing RPC or client grant.
Deploy the migration, then the backend, then distribute the native build through
an authorized preview promotion. Read-only release checks on 17 Sep returned
staging latest 1.1.1 (201), enforcement off, and production latest 1.1.1 (202),
enforcement on; review/internal were null in both. Those builds' profile decoders
were inspected; their contract is unchanged. Legacy build 113 fixtures are retained.

**Cloud checks:** the [native regression](https://github.com/slooowshutter/FitFight/actions/runs/35169363752)
reproduced the erased prompt before the fix. [Web checks](https://github.com/slooowshutter/FitFight/actions/runs/35170095838)
pass TypeScript and all 272 tests. [Disposable database checks](https://github.com/slooowshutter/FitFight/actions/runs/35170095821)
pass migrations/RLS, build 113 compatibility, and all 21 integration tests before
and after the deferred permission cutoff, without skips. The companion assertions
cover legacy stock requests with an explicit null prompt, reuse, concurrent saves,
failed writes, owner isolation, and account deletion. A separate migration rehearsal
preserved a pre-existing prompt through backfill and a subsequent old backend write.
The [iOS checks](https://github.com/slooowshutter/FitFight/actions/runs/35170180506)
pass the actual companion-store regressions, existing native/API checks, localization,
and a simulator build on `macos-26`. Seventeen running simulator captures were
inspected: All, Yours, Custom, and Mountains in English/French and Day/Night, plus
Yours at the largest French accessibility text size. The retained prompt is visible
in Custom and prior descriptions are visible in Yours. These use isolated preview
fixtures and verify layout, not touch interactions or live signed-in writes.
Validation-only workflow triggers and screenshot fixture injection stayed on a
temporary branch. These checks preceded integration with develop at `85d054f`;
PR CI verifies the combined branch. No app tests ran on the workstation.

**Live deployment:** none. No hosted database changes, release-branch merge,
TestFlight upload, or production deployment. Physical-device interaction remains
separate from cloud state and layout checks.

**Develop integration, 18 Sep:** merged `origin/develop` at `51e777f`, retaining
the direct Make it yours and Change animal entry points, editor guidance,
accessible field label, and save errors beside the editor. Tabs handle the
switch between the animal grid and editor without clearing the draft. Both
sets of translations and release notes are retained. Cloud checks for the
combined revision run on PR #272; no API or schema contract was changed
while resolving this merge.

## Develop merge into Profiles branch, 17 Sep 2026

**Code:** merged `develop` at `88c5932` into `profiles-friends-and-stats`.
Profile identity links, exact historical-round navigation, saved personal and
Fight time zones, and the Health upload/refresh ordering remain alongside the
new Feed activity, notification targets, pagination, and companion controls.
Suggested Fights retain immutable-admin authorization and transaction locks;
the same transaction creates upstream's pending invitations and notification
intents. Acceptance stays explicit. Upstream's approved 1.1.2 version is retained.

**Cloud checks:**

- [Web API at `ab8fe24`](https://github.com/slooowshutter/FitFight/actions/runs/35248653718): strict typechecking, all 312 backend tests, API contract parsing, and English/French privacy-page rendering passed.
- [Database at `ab8fe24`](https://github.com/slooowshutter/FitFight/actions/runs/35248653719): all 35 integration tests passed before and after the deferred client-permission cutoff, including invitation idempotency and real WebSocket commit/rollback delivery. Build 113 compatibility, 223 pgTAP checks, 18 cutoff checks, and historical deletion/profile-record migration replay passed. Authenticated `/me` fixtures retain builds 113, 190, 200, 201, 202, and 203.
- [iOS simulator at `f35e254`](https://github.com/slooowshutter/FitFight/actions/runs/35247525681): full compilation on GitHub-hosted `macos-26`, native regression tests, and English/French localizations passed. Native source and fixtures are unchanged in `ab8fe24`.

Database validation exposed interference between shared fixtures once suggestions
began inviting all users: the live-update case passed in isolation after failing
in the parallel suite. Database files now run sequentially; explicit concurrent
joins, privacy edits, and finalization races still run inside their tests. Both
complete passes now succeed without the temporary diagnostic run or changed
assertions. Existing supported-client fixtures remain in place.

**Live deployment:** none. The feature branch has Vercel deployment disabled and
cannot upload TestFlight. No hosted database, `develop`, `preview`, or `main` was
changed. The documented additive-migration, compatible-backend, then-app rollout
and separate permission-cutoff requirements still apply.

## Selective Bugbot reviews, prepared 17 Sep 2026

**Code:** the prepared GitHub workflow requests reviews for ready PRs into
`preview` or `main`, labeled `origin:cursor`, or on same-repository `cursor/*`
branches. It skips other development PRs and duplicate requests for the same
diff. Cursor cloud instructions preserve the origin label across agent handoffs.
The release-ruleset payload targets only `preview` and `main` and starts disabled.

**Checks:** workflow syntax passes `actionlint`. All 20 routing tests passed on
[GitHub-hosted Ubuntu](https://github.com/slooowshutter/FitFight/actions/runs/35170980509)
at `09ab408`. They cover selection, forks, drafts, missing credentials, duplicate
events, changing commits/targets, and trigger failure. The live `Cursor Bugbot`
check was verified as originating from GitHub App `cursor`, ID `1210556`.

**Activation:** not enabled. The available Cursor key received HTTP 401,
`Invalid Team API Key`, from the Bugbot settings API; no connected browser is
available. The GitHub repository has no `BUGBOT_GITHUB_TOKEN` secret. The
`origin:cursor` label exists, `BUGBOT_ROUTING_ENABLED=false`, and the prepared
[release ruleset](https://github.com/slooowshutter/FitFight/rules/23573610) is
disabled. Existing automatic reviews and active branch protections remain unchanged. Activation
requires the dedicated credential, Cursor manual-only configuration, and the
workflow on `main` through separately authorized PRs and merges. Live trigger
delivery and fail-on-unresolved-issues behavior remain unverified. See the
[activation order](shipping.md#selective-cursor-bugbot-reviews).

## Mention notifications: prepared 17 Sep 2026

**Code:** typing `@` in a Feed post or comment shows username typeahead from
`GET /api/v1/feed/people`. The backend parses `@handle` tags (and existing
`tagged_user_ids` on posts), persists eligible post tags, and enqueues a
FitFight-sent `mention` alert that names the author. Copy has no scores. Tagged
people skip the generic fight-post or comment alert for that event. Older create
post/comment requests stay valid: `tagged_user_ids` remains optional, comment
bodies are unchanged, and a missing mention kind is unused by old backends.

**Contract:** additive `mention` outbox kind plus `mention_post` /
`mention_comment` copy keys. No app-facing RPC. Preference GET/PATCH shape is
unchanged. Mentions are not user-toggleable.

**Checks:** `npm run typecheck` passed. `npm test` passed (291 tests).
`python3 scripts/check_localizations.py` and
`python3 scripts/check_native_api_boundary.py` passed. Cloud iOS compile,
screenshots, and disposable-database migration checks are on
[#275](https://github.com/slooowshutter/FitFight/pull/275).

**Live deployment:** not deployed. No hosted database write or reset. Deploy the
additive migration and compatible backend before the native app. Physical-device
two-user mention delivery remains outstanding.

## In-app beta access: prepared 17 Sep 2026

**Code:** You → Settings → Try the beta opens a scrollable sheet in English or
French. It includes the existing Friends Beta TestFlight invite and App Store
listing, warns that accounts, fights, and progress use separate databases without
automatic syncing, and explains how to reinstall the App Store version to return.
Both links remain available in both builds. The version banner stays on You, and
a 1.1.1 release note is included. Apple's [TestFlight guidance](https://testflight.apple.com/)
confirms that installing a beta replaces the installed App Store app.

**Checks:** localization, native API-boundary, download-link consistency, and
whitespace checks passed. All seven new catalog entries have French translations;
existing entries and pre-existing duplicate keys are unchanged. The public beta
invite returned HTTP 200. Apple's App Store endpoint rate-limited the automated
check with HTTP 429; its URL matches the existing website destination. Cloud iOS
compilation and device checks remain pending, including sheet scrolling at large
text sizes, dismissal, and opening both stores. No app build ran on the workstation.

**Rollout:** UI only, with no API, native API model, database, or supported-client
contract changes. No PR, merge, cloud CI run, TestFlight upload, or live deployment
was made. Merging code does not synchronize user data between the databases; the
existing [data transfer](../scripts/data-transfer/README.md) is a separate,
explicitly authorized maintenance operation.

## Stronger slide haptics: prepared 17 Sep 2026

**Code:** The existing 20 slide presets now cover soft starts, early builds, late
surges, and accelerating pulses, with strength displayed on a 0-100 scale. Every
preset reaches its maximum intensity at the existing 85% confirmation threshold.
Saved recipe IDs and the on-device selection are preserved. Continuous patterns
use neutral base parameters so the starting intensity no longer caps their
output, following [Apple's dynamic parameter semantics](https://developer.apple.com/documentation/corehaptics/updating-continuous-and-transient-haptic-parameters-in-real-time).
Timed pulses also respond immediately to track movement. Confirmation uses the
final finger position and plays a full-strength heavy impact only when the action
succeeds.

The lab also has a **Custom** editor with a test slider pinned below its controls.
It exposes rumble strength/crispness endpoints and separate ramp powers; ticks
with texture or five system impact styles; track counts or clock frequency
endpoints; extra movement ticks; tick strength/crispness endpoints and ramp power;
and the finishing hit's enablement, style, and strength. Confirmation distance is
adjustable from 50-100% of the track, and its haptic ramp reaches the selected end
values there. Changing a recipe resets any active test.

Every control edit immediately saves the full custom configuration in this
phone's app preferences, including settings hidden by disabled controls. The
custom draft survives switching presets, closing the lab, and app relaunch.
**Use custom on Slide to start** persists the selection; the New fight slider
observes the saved configuration, including its confirmation point and finishing
hit. Saved values are range-checked when restored. Save errors keep the previous
record and appear in the editor. Localized 1.1.1 release notes cover both changes.

**Checks:** The regression harness compiles the production recipes, engine, and
gesture/confirmation methods against recording hardware/UI boundaries. Cloud
Swift 6.2.4 in Swift 5 mode reproduced the old weak-output and missed-pulse
behavior; the final harness passed 182/182 checks for ramps, fast swipes,
reversal/cancellation, held pulses, recipe changes, repeated lab tests, accessible
confirmation, failed actions, disabled/busy controls, and the existing UIKit
fallback. Custom checks cover all persisted fields, immediate editor binding
saves, reopening preferences, retaining inactive settings, malformed saved data,
failed-save preservation, recipe edits with the same ID, and applying the saved
confirmation point and finishing hit to the production control. The harness is
included in hosted iOS CI. Localization, native API boundary, saved preset IDs,
and whitespace checks passed.

**Cloud iOS and live:** The [hosted iOS build and native checks](https://github.com/slooowshutter/FitFight/actions/runs/35166645031)
and [simulator screen export](https://github.com/slooowshutter/FitFight/actions/runs/35166645125)
passed for `04e5cc1`, before merging the newer `develop` changes. CI for the
combined revision and physical iPhone vibration verification are pending.
Recording boundaries verify hardware commands, not perceived strength or latency.
The haptics change adds no API contract, native API model, database, deployment
order, or supported-client requirement changes. No release-branch promotion,
TestFlight upload, or production deployment was performed.

## App Store descriptions: saved for the next release, 17 Sep 2026

**Latest decision:** Marc deferred the description update to the next normal app
release. Do not continue the standalone release promotion. Both descriptions stay
saved in the 1.1.2 App Store draft, and automatic publication after approval remains
the default. [Release PR #270](https://github.com/slooowshutter/FitFight/pull/270)
is closed. No preview/main merge, 1.1.2 upload, or review submission was performed
for this update. The next release still needs its own normal authorization.

Marc authorized the English/French description refresh, creation of the 1.1.2
App Store version, and publication. Both descriptions and the required localized
release notes in [App Store metadata](app-store/metadata.md) are saved in App Store
Connect under **1.1.2, Prepare for Submission**. The new version inherited the
English/French screenshots; its promotional-text fields are blank.

Apple's Add for Review validation now reports only **You must choose a build**.
No 1.1.2 build is available, so nothing was submitted or published. The current
App Store version is **1.1.1 (202), Ready for Distribution**. A compatible 1.1.2
production build and Apple review are still required.

Marc also requested automatic publication after every approved App Store review.
The workspace prepares native/CI version 1.1.2, an English/French release note,
and Fastlane/release-tool defaults for `AFTER_APPROVAL`. The release tool targets
`FITFIGHT_RELEASE_VERSION` and verifies Apple's saved release mode. Local release
regressions passed (20 tests, 92 assertions), as did localization, Ruby syntax,
project-file syntax, and whitespace checks. The release workflow YAML and all
native/CI version values also passed validation.

[Cloud configuration](https://github.com/slooowshutter/FitFight/actions/runs/35168925860)
confirmed 1.1.2 has `releaseType: AFTER_APPROVAL`, state `PREPARE_FOR_SUBMISSION`,
and no selected build. A separate [cloud readback](https://github.com/slooowshutter/FitFight/actions/runs/35169051669)
confirmed automatic publication and exact English/French description and release
note matches (434 and 529 description characters). The one-time configuration
trigger was removed; the release-tools workflow is back to its original audit-only
branch trigger. The setting is saved at Apple.

[Release PR #268](https://github.com/slooowshutter/FitFight/pull/268) merged the
1.1.2 build files and automatic-release defaults into develop as `85d054f` before
the deferral. Standards and spec reviews found no actionable issues. All 20 release
tests passed. The final integrated revision passed the
[cloud simulator and native regressions](https://github.com/slooowshutter/FitFight/actions/runs/35170672471),
[English/French screenshot checks](https://github.com/slooowshutter/FitFight/actions/runs/35170672595),
and [disposable database compatibility checks](https://github.com/slooowshutter/FitFight/actions/runs/35170672460).
The closed release branch preserves preview's internal-only TestFlight lane from
[#257](https://github.com/slooowshutter/FitFight/pull/257); its 18 release tests also
passed (69 assertions). Production remains on 1.1.1 (202).

**Compatibility and order:** the metadata/version change adds no API or schema
change. The release also carries the previously merged compatible Feed, chart,
notification, and Activity work documented below. At 01:14 UTC on 17 Sep, staging
reported latest **1.1.1 (201)** with enforcement off; production reported latest
**1.1.1 (202)** with enforcement on. Both had null review/internal candidates and
healthy profile APIs. Staging's Supabase integration and Vercel deployment at
`511f400` succeeded. The three additive migrations retain existing client grants
and `/api/v1` contracts; preserved build 113 fixtures and 201/202 native contracts
remain in the cloud checks. Verify those checks before promotion. Production's
migration and backend deployment must succeed after the authorized main merge,
before submitting the production candidate. Physical-device checks remain
separate from the cloud evidence.

## Companion customization: prepared 17 Sep 2026

**Code:** You has Make it yours, which opens the companion picker at the expanded
description, and Change animal, which opens the animal grid. The former Custom
button is now Make it yours. The description explains that any animal can be
chosen and keeps guidance for species, breed or race, accessories, colors, and
other details. Change animal within the form returns to the grid without clearing
the draft. Save companion keeps the existing account save, blank-input validation,
and 1,000-character limit; save errors appear beside the form. English/French copy
and a 1.1.1 release note are included. Custom image generation is still not built.

**Checks:** localization, native API-boundary, and whitespace checks passed.
Cloud iOS compilation and device interaction checks remain pending. Verify both
entry buttons, scrolling to and from the description, editing a saved description,
Save and failed-save feedback, and English/French layouts at larger text sizes.

**Live deployment:** not deployed. No API contract, native API model, or database
change. No PR, merge, TestFlight upload, or production deployment was made.

## Admin feedback deletion: prepared 17 Sep 2026

**Code:** admins can open a Feedback request, tap its ellipsis menu, and choose
Delete request. Confirmation removes the request from the board and returns to
the list. The server checks the existing admin handle/email allowlist for every
deletion; regular accounts cannot delete feedback, including their own requests.
The shared admin reader now accepts only the stored profile handle and confirmed
Auth account email. User-editable metadata and identity email copies cannot grant
admin access. English/French copy and a 1.1.1 release note are included.
The review fix records deleted request IDs so stale list/detail responses cannot
restore them. Finishing a deletion preserves another request's pending load,
comments, admin actions, and errors when the user has already navigated away.

**Contract:** additive `DELETE /api/v1/feedback/{postID}` and `can_delete` on the
existing detail response. Older native decoders ignore the new key; the new app
defaults to false when an older backend omits it. Existing request fields and
response fields retain their shape. No database migration or permission change;
existing foreign keys cascade comments, votes, reports, and attachment links.

**Checks:** TypeScript, all 277 backend tests, localization, native API-boundary,
and whitespace checks passed. Regression coverage includes missing authentication,
admin handle/case/confirmed-email access, regular accounts, spoofed metadata,
unconfirmed email, deleted accounts, missing requests, and legacy detail responses.
Database calls were mocked; no cloud deletion or cascade integration test was run.
Native ordering regressions are added to the existing cloud state-test runner for
both detail/deletion completion orders, stale list/detail responses, and failed
deletion. Review-fix checks passed for localization, native API-boundary, whitespace,
and regression-source assembly. The native regressions have not been executed in
this local workspace, following the cloud-only build rule.
Cloud iOS compilation and signed-in device checks of confirmation, cancellation,
failure handling, and list refresh remain pending.

**Supported builds and rollout:** read-only release checks on 17 Sep returned
staging latest 1.1.1 (201), enforcement off, and production latest 1.1.1 (202),
enforcement on; both had null review/internal candidates. Legacy staging users
remain supported. Source inspection at `d97145a` (201) and `e2783be` (202) confirms
the feedback decoder reads only its named keys; no installed binary was tested.
Deploy the compatible backend before the native app. No PR,
push, merge, live deployment, TestFlight upload, or hosted data write was performed.

## Interrupted comment requests, prepared 17 Sep 2026

**Code:** a comment refresh queued behind a failed read now runs after that failure.
Failures without queued work still surface their error without another request.
Live updates retain the requested page count for More comments while refreshing
the loaded thread. Changing the sort still starts at the first page. The 1.1.1
release note includes English and French copy.

**Checks:** the new regressions reproduced both defects in
[cloud native checks](https://github.com/slooowshutter/FitFight/actions/runs/35166089672)
with `python3 scripts/test_native_state.py`. Localization and native API-boundary
checks pass in the workspace. At `0e4e631`, the
[cloud iOS build and native regressions](https://github.com/slooowshutter/FitFight/actions/runs/35166290185)
passed. The cases cover queued refreshes after failures, failures without queued
work, pagination interrupted by successful or failed reads, and sort changes
during pagination. [Backend checks](https://github.com/slooowshutter/FitFight/actions/runs/35166290196)
and [disposable database checks](https://github.com/slooowshutter/FitFight/actions/runs/35166290204)
also passed. Physical-device verification remains pending.

**Deployment:** native UI state only, with no API contract or schema changes.
No merge into develop, preview, or main, and no TestFlight or production upload.

## Feed review fixes, prepared 17 Sep 2026

**Code:** automatic thread refresh preserves all previously loaded comments,
including confirmed local comments below the first ranked page. It publishes the
refreshed pages together, removes deleted comments, and preserves the previous
thread and cursor if a later page fails. Changing the comment sort starts at its
first page. Feed events invalidate posts returned by an in-flight page, and
pagination reconciles visible stale cards when it supersedes an earlier live read.
App-wide post writes now send empty invalidations to every active profile's
existing private topic, including users with no shared Fight. The 1.1.1 release
note has English and French copy.

**Cloud checks:** at `b1efa8d`, the
[iOS simulator build and native regressions](https://github.com/slooowshutter/FitFight/actions/runs/35160730520)
passed on GitHub-hosted macOS. The regressions cover loaded comment pages,
confirmed lower-ranked comments, deleted comments, later-page failures, sort
changes, arriving-card invalidation, and both live read/pagination completion
orders. [TypeScript and all 270 backend tests](https://github.com/slooowshutter/FitFight/actions/runs/35160730532)
passed. [English/French screen rendering and screenshot asset checks](https://github.com/slooowshutter/FitFight/actions/runs/35160730592)
also passed. The [disposable database checks](https://github.com/slooowshutter/FitFight/actions/runs/35160730447)
passed all 21 transaction tests before and after the deferred client-permission
cutoff, pgTAP, the preserved build 113 fixture, and legacy migration replay. Real
WebSocket checks cover app-wide post creation, edits, comments, reactions, and
deletion, including a user with no shared Fight. Private Fight events still
exclude that user.

Before the fixes,
[native regression tests](https://github.com/slooowshutter/FitFight/actions/runs/35160578605)
reproduced the loaded-comment loss, arriving-page invalidation gap, and both live
read/pagination completion orders. The
[disposable database test](https://github.com/slooowshutter/FitFight/actions/runs/35160359036)
reproduced the missing app-wide invalidation.

**Compatibility and live evidence:** `/api/v1`, post/comment request and response
fields, private topic names, and existing client permissions are unchanged. This
adjusts the pending additive feed migration, with no new app-facing RPC. At 22:57
UTC on 16 September, staging `/api/app-release` listed latest **1.1.1 (201)**,
review/internal null, enforcement off. Production listed latest **1.1.1 (202)**,
review/internal null, enforcement on. Legacy clients remain supported in staging.

**Deployment:** code only. No hosted migration, backend promotion, TestFlight
upload, or production deployment. After authorized merges, deploy the additive
migration and compatible backend before the native app. Physical-device and
two-user live verification remain outstanding.

## Feed pagination and direct refresh, prepared 17 Sep 2026

**Code:** root Feed and each Fight's feed now request ten posts per page through
the existing `limit` parameter. A lazy list automatically appends the next page at
the bottom. Stable post IDs, reserved photo dimensions, and unchanged existing
rows preserve the reading position. Page requests deduplicate overlapping triggers;
failed pages keep their cursor and offer a retry at the bottom. Pagination does not
reload comments on earlier cards.

Pull-to-refresh fetches the latest ten posts and supersedes older page responses.
It awaits the feed request directly, without first waiting for HealthKit/Fight
sync. Server feed responses already use `Cache-Control: no-store`; this corrects
the refresh sequencing and stale thread state. Background events refresh displayed
cards in place and mark offscreen cards for refresh on reappearance, preserving
the reading order and pagination cursor. New posts appear on initial load or pull.

**Cloud checks:** [iOS build and native regression checks](https://github.com/slooowshutter/FitFight/actions/runs/35157007769)
passed on GitHub-hosted macOS. The actual API methods request ten posts and retain
opaque cursors. Suspended-request tests verify direct pull-to-refresh and its
indicator, one request per page, stable append order, no reload of earlier threads,
refresh/page races, error recovery, end-of-feed behavior, visible/offscreen live
updates, and account isolation.

The [hosted iOS simulator scroll check](https://github.com/slooowshutter/FitFight/actions/runs/35157007857)
also passed with the actual feed layout and an isolated 25-post fixture. Initial
load stopped at ten posts; scrolling requested exactly two more pages, reaching
20 and then 25 posts. The same visible card moved **0 points** on both appends.
The final page stopped pagination. This measures fixture layout on iOS 26.5;
physical-device and two-user live verification remain separate.

**Compatibility and deployment:** no additional API or schema changes. Older
clients retain the default 30-post page and existing response fields. The earlier
single-post endpoint and feed invalidation migration below still deploy before the
native app. No hosted promotion or TestFlight upload was performed.

## Feed refresh, notification targets and Activity, prepared 16 Sep 2026

**Code:** reproduced two defects in cloud regression checks: a loaded thread did
not refresh when its comment count changed from one positive number to another,
and social pushes carried only a Fight destination. Existing Realtime covered
standings, not feed content. The prepared change adds private `feed_changed`
invalidations, refreshes visible posts and threads, and retains post/comment
targets through foreground taps, cold starts and sign-in. A dedicated post read
resolves targets outside the feed's loaded pages. Equal-timestamp post/comment
pagination preserves microseconds and accepts existing opaque cursors.

You -> Activity lists currently accessible Fight posts, comments, reactions and
membership history, with timestamps and links. New membership transitions are
recorded privately. Existing acceptance times are backfilled; older invitations
display **Time not recorded**. This is available product activity, not a push
delivery log. Deleted/blocked content and inaccessible Fights are excluded.

**Cloud checks:** [iOS simulator build and native regressions](https://github.com/slooowshutter/FitFight/actions/runs/35153263762)
passed on GitHub-hosted macOS. Tests cover comment refresh during another read,
confirmed local writes, retained feed pages, independent live-update streams,
exact post/comment routes, account changes, and shared Swift/API fixtures.
[TypeScript and all 251 backend tests](https://github.com/slooowshutter/FitFight/actions/runs/35153836885)
passed. The [disposable database checks](https://github.com/slooowshutter/FitFight/actions/runs/35153836954)
passed before and after the deferred client-permission cutoff, including legacy
migration replay. They cover real WebSocket commit/rollback behavior, membership history, blocks,
withdrawals, deletion, private-table permissions, and pagination beyond 40
equal-timestamp comments. Compatibility includes the preserved build 113 SQL
fixture and the unchanged notification parsers from builds 201 and 202.

**Live evidence:** at 21:02 UTC on 16 September, staging `/api/app-release`
advertised latest **1.1.1 (201)**, no review/internal candidates, enforcement off.
Production advertised latest **1.1.1 (202)**, no review/internal candidates,
enforcement on. These reads supersede the older manifest observations below.
`/api/v1`, existing post/comment response fields, and direct-client permissions
remain unchanged. Notification URLs retain `/fights/{id}` and add query targets;
installed 201/202 clients still open the Fight.

**Deployment:** no hosted schema/backend promotion, TestFlight upload, production
deployment was performed. After authorized merges, apply the additive
`20260916210740_feed_activity_updates.sql` migration, deploy the compatible backend,
then distribute the native build through preview. Production needs its own
authorized rollout and checks. A two-device live comment/tap check remains.
The specific reported missing comment is not confirmed without both phones'
build/environment labels; staging and production use separate databases.

## Review fixes: prepared 17 Sep 2026

**Code:** reaction chips remain a swipeable horizontal carousel, as Marc requested.
A separate actions row provides like, comments, preset reactions, and an Other emoji
entry. The newer comment sorting and request sequencing are retained. Chart refresh
recreates only the progress fill, preserving the chart picker and selected day.
Pace keeps missing or stale participant history unavailable instead of showing zero.
Legacy cumulative uploads no longer become invented daily checkpoints; confirmed
totals still appear under So far when no daily history exists. Most comments uses
the same timestamp precision for sorting and pagination. Create, edit, invite, and
suggest commands deliver notifications after their successful HTTP response.

**Contract and supported builds:** `/api/v1` routes, request/response fields, scores,
and legacy `step_days` are unchanged. `step_checkpoints` was already nullable.
Read-only release checks on 17 Sep returned staging `latest` 1.1.1 (201), enforcement
off, and production `latest` 1.1.1 (202), enforcement on; both had null review/internal
candidates. The native decoders from build 201 (`d97145a`) and 202 (`e2783be`) accept
null/missing checkpoints. Existing API fixtures and build 113 SQL compatibility
checks are retained because staging still admits older clients. No migration or
client-permission change is required.

**Cloud checks:** the regressions first failed against the reviewed code on
GitHub-hosted runners: all four saved commands returned HTTP 500 on delivery failure,
Pace drew unavailable history as zero, comment pagination skipped roots, and sparse
legacy uploads with a downward correction fabricated checkpoints. At `d14671c`,
[web checks](https://github.com/slooowshutter/FitFight/actions/runs/35158343483)
passed typecheck and all 270 tests. The
[disposable database checks](https://github.com/slooowshutter/FitFight/actions/runs/35158343440)
passed migrations/RLS, build 113 compatibility, and all 21 integration tests both
before and after the deferred client-permission cutoff, with no skips. The
[iOS checks](https://github.com/slooowshutter/FitFight/actions/runs/35158343485)
passed chart/HealthKit, native state, API fixtures, localization, and the simulator
build on `macos-26`. The
[running simulator captures](https://github.com/slooowshutter/FitFight/actions/runs/35160392966)
show visible reaction chips, the emoji menu icon, and unclipped like/comment actions
in English and French, Night and Day. Static export omitted the scroll contents and
menu, so it was not used to verify those controls. Captures verify layout, not swipe
or menu interactions. Validation-only workflow triggers were confined to a temporary
branch; all 17 changed application and test files matched the passing revision
byte-for-byte before PR preparation integrated the newer `develop` changes.
PR CI will verify the combined branch. No app tests ran on the workstation.

**Rollout:** compatible backend fixes can land on staging through an authorized
`develop` merge before the native update. A later authorized `preview` merge ships
the native changes with a 1.1.1 release note. Production still requires its separate
authorized `preview` to `main` promotion. This work has not merged a release branch,
changed the hosted database, or uploaded a TestFlight build. Physical
device interaction and HealthKit verification remain separate from cloud checks.

## Website download destinations: prepared 17 Sep 2026

The homepage, fight/referral invite pages, and English/French support pages use
the configured backend environment to choose the download destination.
Production links to `https://apps.apple.com/app/id6804230516`. Staging keeps the
Friends Beta TestFlight link and installation instructions. Invite pages retain
their five-second iOS redirect and original-link reopening instructions. The
App Store destination returned HTTP 200. A 1.1.1 release note is included.

Workspace checks passed: TypeScript, all 266 existing tests, optimized builds for
both environments, and HTTP-rendered link/copy checks for all five affected routes
in each environment. Browser redirect execution and native compilation were not
run. No API contract or database change, cloud CI run, PR, merge, or live deployment
was performed. The live sites still need the normal authorized promotions.

## Post and comment translation prepared, 16 Sep 2026

**Code:** Feed and fight-thread posts, comments, and replies have an A speech-bubble
translation icon at the top right, immediately left of the ellipsis. Apple's
[`NLLanguageRecognizer`](https://developer.apple.com/documentation/naturallanguage/nllanguagerecognizer) detects the text's language on device before displaying the
icon. It appears only when the detected language differs from the first language
in `Locale.preferredLanguages`; regional variants count as the same language.
Empty text, text without letters, and unrecognized languages have no icon.
Detection is best-effort for short or mixed-language text. Tapping opens Apple's system translation sheet,
which chooses a target from the reader's language preferences and lets them change
it. Original content stays intact. The control uses the existing theme, a 44-point
tap target, an English/French accessibility label, and a `1.1.1` release note. It is
available on iOS 17.4+ and hidden on earlier supported iOS versions, matching
[Apple's translation API](https://developer.apple.com/documentation/swiftui/view/translationpresentation(ispresented:text:attachmentanchor:arrowedge:replacementaction:)).
The English simulator preview keeps Bertille's first post in French so the icon
can be inspected alongside English posts where it stays hidden.

**Checks:** localization, native API-boundary, Xcode project-file syntax, and
whitespace checks passed. Cloud iOS compilation and physical-device translation
checks are pending. Verify icon visibility for same/different languages and regional
variants, both English/French translation directions, target-language changes, and
dismissal back to the unchanged post or comment on a device.

**Live deployment:** not deployed. No API contract, native API model, or database
schema changed. No merge, TestFlight upload, or production deployment was made.

## Marc broadcast posts, 16 Sep 2026

**Contract:** `POST /api/v1/feed/posts` accepts `{ "type": "broadcast" }` as a
lone destination. Only username `marc` (same You → Developer gate) can create
it. The row is `audience=main`, `app_wide=true`, no fight channels. `GET /api/v1/feed`
with no scope now also returns those rows to every signed-in caller. Old
`main` / `fight` requests and response shapes stay the same. No lock-screen
intent is queued; existing `feed_post` alerts still cover fight-channel posts
only.

**Checks:** workspace TypeScript and feed unit tests. Migration is additive.
No hosted `db push`. Not on TestFlight until an authorized `preview` merge.

## PGG7 app-wide invite: prepared 16 Sep 2026

**Contract:** `POST /api/v1/fights/refresh` and `POST /api/v1/fights/snapshot` stay on `/api/v1`. Request and response shapes are unchanged except `alreadyMember` on joinable/suggested summaries is now true for pending invitees as well as accepted/deferred members. Older apps already treat `alreadyMember` as "open this fight," so a tap on New opens the existing Accept invitation. After auth, the backend invites the caller to `PGG7` and every currently suggested fight when they have no membership row. Marking a series suggested invites every active profile the same way.

**Choice:** join-by-code still requires an explicit Join. Auto-invite creates the same pending invite the username-invite path already shows on Fights. Suggested fights were already listed on New from `GET /api/v1/fights/suggested`.

**Notifications:** invite pushes did not exist (feed post/reaction kinds did). Additive migration `20260916210000_fight_invite_notifications.sql` allows `fight_invite` outbox rows with a personalized `alert_body` that names the person and fight and includes no scores. Existing clients already open `/fights/{id}` from the payload. No new preference toggle.

**Supported builds checked:** read-only `https://staging.fitfight.app/api/app-release` on 16 Sep 2026 returned `latest` 1.1.1 (201) with `enforced: false` (`review`/`internal` null). Staging still has installed users on older binaries while enforcement is off. Those clients already render `invited` rows and suggested New rows. No required request field.

**Staging evidence:** series `PGG7` exists as `EVERYBODY ON THE APP`, `joinable`, recurring, suggested, current fight `live`. Production was not queried from this change. If that code is absent in an environment, the lookup is a no-op and no fight is invented.

**Deployment order:** apply the additive invite-notification migration and this backend to staging with `develop` first. Existing TestFlight builds pick up invites and the New-tab tap behavior on the next open/sync. The 1.1.1 changelog row ships only when this native change later reaches `preview`. No production deploy, `preview` merge, hosted `db push`, or TestFlight upload from this work.

**Cloud checks vs live:** unit tests cover missing/closed/already-member/new-invite/suggested-everyone paths and invite copy against mocks. No hosted write, disposable migrated-database check, or signed-in device verification was run here.

## Profiles, Friends, and Rivalry implementation, 17 Sep 2026

**Review fixes and saved time zones, 17 Sep:** prepared on this branch, not deployed.
You waits for Health upload completion before reloading statistics on first load,
foregrounding, pull to refresh, and Health actions. Feedback usernames open Profile;
comment counts open the discussion. Shared activity and statistics use one saved
personal date boundary, including audience previews, so a seven-day grant cannot
expose an eighth date after travel.

The existing `profiles.time_zone` column is now exposed as optional `/api/v1/me`
`time_zone` and an optional PATCH input. Existing values are preserved; accounts
without a stored zone use fixed UTC until they choose one. New username
onboarding saves the phone's zone, and Edit profile can change it. Daily Health
aggregates and new Fight durations use the saved zone. Custom Fight date pickers
and review use a selectable Fight zone; changing it preserves the entered local
times and recalculates their UTC instants. The zone can be edited before a Fight
starts and is locked afterward. Snapshot Fight rows gain optional `time_zone`.
Old fixtures still omit these fields. No database migration is needed for these
fixes, and no finalized daily totals are relabeled.

**Cloud checks:** the new regression commit `c07ad09` reproduced both defects:
[iOS refresh](https://github.com/slooowshutter/FitFight/actions/runs/35239173445)
failed all three upload-order checks, and the
[database test](https://github.com/slooowshutter/FitFight/actions/runs/35239173174)
returned eight dates for a seven-day grant. Both regressions pass with the fixes.

- [Web API, `613b388`](https://github.com/slooowshutter/FitFight/actions/runs/35241578740): strict typecheck, all 268 unit/contract tests, API contract parsing, and privacy-page rendering passed. Coverage includes valid/invalid zones, unset legacy accounts, and rejecting a zone edit once the Fight's start instant has passed.
- [Database, `613b388`](https://github.com/slooowshutter/FitFight/actions/runs/35241578761): all 32 transaction/HTTP tests passed both before and after the deferred client-permission cutoff. The mixed-zone sharing regression returns exactly seven dates; owner statistics and previews use the same saved zone. Authenticated `/me` requests cover build headers 113, 190, 200, 201, 202, and 203, including legacy PATCH requests that omit and preserve the zone. The 211 pgTAP checks, 18 cutoff checks, and historical backfill/deletion rehearsal also passed.
- [iOS simulator, `733f642`](https://github.com/slooowshutter/FitFight/actions/runs/35241180293): full app compilation on GitHub-hosted `macos-26`, Health upload/refresh ordering, saved-zone travel, daylight-saving custom/preset windows and rematches, old/new optional-field decoding, and English/French localizations passed. Native source and fixtures are unchanged in `613b388`.

These are disposable cloud database and simulated native checks. They do not
replace installed-device verification or prove live deployment.

**Live and rollout:** read-only `/api/app-release` checks at **17 Sep 15:41:31 UTC**
show staging latest 1.1.1 (201), review/internal 1.1.2 (203), enforcement off;
production latest 1.1.1 (202), review/internal null, enforcement on. Those live
candidates do not contain this branch. Deploy the compatible backend after the
branch's existing Profile expansion migration, then distribute the native app.
No merge, deployment, TestFlight upload, or change to the live database was made.
Installed-device verification remains outstanding.

**Steps statistics extension, 17 Sep:** prepared on this branch. You and Profile
sheets now show best recorded day, average per recorded day, weekly average and
total, and day distributions/current/longest recorded streaks across five activity
levels. Levels use the companion's existing 2k/4k/6k/8k thresholds. The owner's
avatar opens their Profile. Only finalized days with known time zones count,
through yesterday; missing days are unknown. Exact-category streaks cannot bridge
unknown days. Weekly summaries disclose their recorded-day denominator and use
the person's saved Profile time zone. Travel does not change that setting; existing
recorded days retain their original zone and finalized value.

Owners see available recorded history. Other viewers and previews receive only
statistics within their explicit activity audience and 7/30-day period. Earlier
records and streak lengths remain private. The existing v1 Profile response gains
optional `step_statistics`; existing daily-history and legacy `/me` contracts stay
intact. No new schema or HealthKit collection is added by this extension.

**Cloud checks for the statistics extension:**

- [Web API, `9513ee6`](https://github.com/slooowshutter/FitFight/actions/runs/35172085761): strict typecheck, all 265 unit/contract tests, API contract parsing, and the existing Privacy-page rendering checks. Eight new calculation tests cover thresholds, exact-category streaks, gaps, partial days, observed weekly denominators, sharing windows, empty history, DST, leap days, and year boundaries.
- [Database, `9513ee6`](https://github.com/slooowshutter/FitFight/actions/runs/35172085773): all 31 transaction/HTTP tests pass before and after the separately deferred grant cutoff, alongside 211 pgTAP checks, build 113 compatibility, and the historical backfill/deletion rehearsal. New checks prove older personal records remain owner-only, shared streaks clip to 7/30 days, previews use the same limits, sharing revocation/friend removal/blocking take effect, and recorded time zones govern the date boundary. Existing authenticated `/me` compatibility covers build headers 113, 190, 200, 201, and 202.
- [iOS simulator, `2ab9359`](https://github.com/slooowshutter/FitFight/actions/runs/35171964316): app compilation on GitHub-hosted `macos-26`, new statistics response decoding, old optional-field compatibility, stale-response/revocation/account-switch tests, and English/French localizations. The later review-fix checks above cover the current native source and fixtures.

The checks use disposable cloud data and simulated native responses, not installed
versions of every supported build. No live deployment or app distribution has
occurred. Read-only manifests at **17 Sep 01:45:27 UTC** still list staging 1.1.1
(201), enforcement off, and production 1.1.1 (202), enforcement on, with null
review/internal in both. Backend support precedes native distribution, after the
already-required Profile expansion rollout. Installed-device verification remains
outstanding.

**Code prepared on `profiles-friends-and-stats`, not deployed.** The
[implementation plan](design/profiles-friends-implementation-plan.md) now has
native Profile sheets and editing, mutually accepted Friends and request lists,
Competitive/Public controls, explicit 7/30-day Steps sharing, records, shared
history, 1v1 rivalry summaries, and composer-based challenges/rematches. Avatars
and usernames open Profiles from standings, participants, Feed, comments,
reactions, Feedback, and Friends. Defaults are Private, Casual, and no daily
Steps sharing. Identity-only lookup never returns referral codes, companion
prompts, a friends roster, or private Fight titles/actions.

**Suggested Fights:** the existing New/discovery and invitation surfaces and an
optional final onboarding step use the eligible server list. No automatic joining
or sharing change occurs. New administrative capability depends only on
`FITFIGHT_ADMIN_USER_ID`, an immutable Auth UUID configured on the server. It is
disabled when absent. Admin visibility, recurrence, suggestion, and stop controls
serialize with joins and recurring rounds; stopped/private series lose Suggested.
No new global leaderboard or recurring-league scoring system was added.

**Records and privacy:** the additive migration captures participation and
freezes category/result evidence without changing Fight scoring. Anonymous field
and tie counts preserve surviving Users' results when a participant deletes their
account. Existing account deletion still removes the deleting owner's own Fights.
Historical category/departure facts remain unknown when evidence is missing;
there is no invented lifetime completeness date. Backfill locks existing Fight
writes until its snapshot and triggers commit. Old backend departures remain
unclassified; full-fidelity capture begins only after the new mutation paths are
live and old instances drain. That has not happened in either live environment.
The new friendship store never trusts legacy client-created accepted rows.

**Review fixes:** history row IDs and pagination cursors are now random,
participant-specific UUIDs. Authorized navigation still uses `fight_id`; a
shared identifier no longer links private participants across Profiles. The
backfill preserves reliable membership evidence for accepted future rounds, so
their later completed results count. Historical Profile links keep the selected
round through navigation and refresh. Rematches use a custom schedule whenever
a preset would change the prior elapsed duration, including daylight-saving
transitions. Each defect was reproduced in cloud CI before its fix.

**Measurement:** authenticated display events deduplicate replay, qualify at most
once per rolling 30 minutes per direction, and expire after 30 days through the
existing daily maintenance route. Friend actions and actual participation
transactions record seven-day last-visit attribution. Anonymous aggregate counts
remain after raw events expire. Reports are operator-only. Measurement defaults
off (`FITFIGHT_PROFILE_MEASUREMENT_ENABLED=false`), pending publication of the
prepared English/French Privacy disclosure.

**Held parts of the plan:** artwork has private storage metadata only; there is
no provider request, runner, paid generation, delivery route, or loading card.
Artwork opt-in is rejected until implemented. Marc still needs to supply the
provider/model, credentials through secret storage, budget, and approved companion
input policy. Terms pages and native sign-in/settings Terms links remain unbuilt
until the actual operator/address, jurisdiction, and minimum-age facts are supplied.
No placeholder legal page or extra Terms acceptance flow was introduced.

**Cloud checks passed:**

- [Web API, `712fd22`](https://github.com/slooowshutter/FitFight/actions/runs/35167142686): strict typecheck, all 257 unit/contract tests, API contract parsing, and cloud Chrome rendering of both signed-out Privacy pages at 393 by 852. Web source has not changed since this run.
- [Database, `90b9211`](https://github.com/slooowshutter/FitFight/actions/runs/35170544134): additive migration, schema lint, 211 pgTAP checks, build 113 compatibility, and all 30 transaction/HTTP tests before and after the separately deferred client-permission cutoff. The new privacy regression proves independent stable history IDs, scoped pagination, and preserved authorized Fight navigation. The backfill rehearsal starts with an accepted future round before migration and proves its completed result counts afterward while uncertain historical results stay excluded. Existing account-deletion, friendship, concurrency, attribution, and retention checks still pass.
- [iOS simulator, `90b9211`](https://github.com/slooowshutter/FitFight/actions/runs/35170544151): app compilation on GitHub-hosted `macos-26`, exact historical-round navigation through destination/detail resolution and refresh, normal Feed navigation, custom and daylight-saving rematch durations, and ordinary duration presets. Profile DTO/redaction, response ordering/revocation/account-switch checks, existing native regressions, English/French localizations, API boundary, and design tokens also pass.

These checks use disposable cloud data and simulated network responses for native
state tests. They do not establish a live deployment, real image generation, or
installed-device verification. No workstation Xcode or local database tests were
used.

**Compatibility and rollout:** API stays `/api/v1`; existing `/me`, Fight and
media payloads and build 113 fixtures remain intact. The new Profile history
contract keeps UUID-shaped IDs/cursors and its existing fixtures; `fight_id`
remains nullable and available only to authorized viewers. These Profile routes
and the expansion migration have not been deployed, so the migration itself
includes both review corrections. Feedback comment `author_id` is additive and
optional in native decoding. Cloud authenticated `/me` requests
cover version/build headers 113, 190, 200, 201, and 202; this is contract evidence,
not installed-device testing of each build. The separately deferred direct-client
grant cutoff is rehearsed in CI only, not activated by this migration.
Read-only live checks at **17 Sep 01:27:12 UTC** returned staging latest 1.1.1 (201),
null review/internal, enforcement off; production latest 1.1.1 (202), null
review/internal, enforcement on. No live schema, backend, release manifest, or
app distribution changed in this work. Feature-branch Vercel deployment is
explicitly disabled while cloud checks run.

Before release: recheck both manifests, apply the additive schema then compatible
backend, publish the accurate legal disclosures, configure the admin UUID, and
verify with two installed staging clients before distributing the native build.
Keep measurement/artwork disabled until their respective dependencies are met.
Physical-device VoiceOver, Dynamic Type, Night/Day, onboarding, Apple sign-in and
HealthKit verification remains outstanding. Marketing version stays `1.1.1`, with
a 17 September release note prepared. No PR, branch merge, TestFlight upload,
production deployment, or App Store action was performed for this feature.

## Marc broadcast posts, 16 Sep 2026

**Contract:** `POST /api/v1/feed/posts` accepts `{ "type": "broadcast" }` as a
lone destination. Only username `marc` (same You → Developer gate) can create
it. The row is `audience=main`, `app_wide=true`, no fight channels. `GET /api/v1/feed`
with no scope now also returns those rows to every signed-in caller. Old
`main` / `fight` requests and response shapes stay the same. No lock-screen
intent is queued; existing `feed_post` alerts still cover fight-channel posts
only.

**Checks:** workspace TypeScript and feed unit tests. Migration is additive.
No hosted `db push`. Not on TestFlight until an authorized `preview` merge.

## PGG7 app-wide invite: prepared 16 Sep 2026

**Contract:** `POST /api/v1/fights/refresh` and `POST /api/v1/fights/snapshot` stay on `/api/v1`. Request and response shapes are unchanged except `alreadyMember` on joinable/suggested summaries is now true for pending invitees as well as accepted/deferred members. Older apps already treat `alreadyMember` as "open this fight," so a tap on New opens the existing Accept invitation. After auth, the backend invites the caller to `PGG7` and every currently suggested fight when they have no membership row. Marking a series suggested invites every active profile the same way.

**Choice:** join-by-code still requires an explicit Join. Auto-invite creates the same pending invite the username-invite path already shows on Fights. Suggested fights were already listed on New from `GET /api/v1/fights/suggested`.

**Notifications:** invite pushes did not exist (feed post/reaction kinds did). Additive migration `20260916210000_fight_invite_notifications.sql` allows `fight_invite` outbox rows with a personalized `alert_body` that names the person and fight and includes no scores. Existing clients already open `/fights/{id}` from the payload. No new preference toggle.

**Supported builds checked:** read-only `https://staging.fitfight.app/api/app-release` on 16 Sep 2026 returned `latest` 1.1.1 (201) with `enforced: false` (`review`/`internal` null). Staging still has installed users on older binaries while enforcement is off. Those clients already render `invited` rows and suggested New rows. No required request field.

**Staging evidence:** series `PGG7` exists as `EVERYBODY ON THE APP`, `joinable`, recurring, suggested, current fight `live`. Production was not queried from this change. If that code is absent in an environment, the lookup is a no-op and no fight is invented.

**Deployment order:** apply the additive invite-notification migration and this backend to staging with `develop` first. Existing TestFlight builds pick up invites and the New-tab tap behavior on the next open/sync. The 1.1.1 changelog row ships only when this native change later reaches `preview`. No production deploy, `preview` merge, hosted `db push`, or TestFlight upload from this work.

**Cloud checks vs live:** unit tests cover missing/closed/already-member/new-invite/suggested-everyone paths and invite copy against mocks. No hosted write, disposable migrated-database check, or signed-in device verification was run here.

## Production rollout and App Store submission, 16 Sep 2026

This section supersedes the earlier held-rollout and screenshot-upload notes below.
Marc authorized the complete production rollout and App Store submission.
[#245](https://github.com/slooowshutter/FitFight/pull/245) integrated release tools,
[#246](https://github.com/slooowshutter/FitFight/pull/246) promoted them to preview,
and [#247](https://github.com/slooowshutter/FitFight/pull/247) merged preview into
main at 23:30 UTC on 15 September, commit `e2783be`.

**Live backend:** all 40 production migrations are applied. The Supabase deployment
completed while the operator migration command was running; that command stopped
during media-policy creation. A fresh migration listing matches all 40
repository versions and another `migration up` applied nothing. Production health
returns `ok: true`, `backend: prod`, `schema: ready`, and `profile_api: true`.
English and French Privacy and Support pages return 200. The old build 113 SQL
request and forbidden-write checks passed on production with the fixture rolled
back. `/api/v1/me` reaches authentication and returns 401 without credentials for
build headers 113, 190, 200, 201, and 202. No API version changed. Production still
advertises public 1.0.0 (113), with update enforcement off.

**Live data:** a fresh cloud copy of production was created and verified before
the rollout. The real import combined 23 beta accounts and 3 production accounts,
matching 2 shared Apple identities, into 24 accounts, 36 Fights, and 88 memberships.
Beta profile details win; production IDs, referral codes, and unrelated history
remain. All 52 ready media files passed source/destination checksum and size checks;
2 unfinished uploads were excluded. Two downloads initially failed; after the
temporary worker was restarted, both passed the same byte checks. No account rows
were committed until every media file passed.

The production rehearsal verified the planned result then rolled back to the exact
original digest. The committed import matched the planned digest; all foreign keys,
24 Auth account/Apple-identity reads, and 50 account/role visibility checks passed.
Repeating the import reported `already_applied: true`, with no duplicate rows.
Checkpoint: `6b482e49-29d7-4442-b87c-871ac4c776cc`. Verified row digest:
`c0d5a6c2b3ef0c6e30788e51c0bf74ecf6f7ef1f760d4c2b6b13ec8d3e7844db`.
Data and media moved only between cloud services. Both temporary transfer functions,
all three temporary secrets on both projects, and the local token file were removed.
The private checkpoint and pre-rollout backup are retained for the final catch-up.

**Production archive:** [App Store candidate CI](https://github.com/slooowshutter/FitFight/actions/runs/35036003664)
uploaded 1.1.1 (202) at 23:37 UTC. The signed IPA passed production URL/key checks,
HealthKit background-delivery entitlement verification, and bundled privacy-manifest
validation. Database, backend, simulator, and native regression checks passed.
The twelve English/French screenshots are uploaded and processed. The 12-category
App Privacy disclosure is published, and the age questionnaire reflects Health or
Wellness Topics, Messaging and Chat, and Social Media. The production OpenRouter
key was removed, so AI daily statuses and recaps are disabled for this release.
The existing availability and legal/account settings were preserved.

**Review submission:** [submission CI](https://github.com/slooowshutter/FitFight/actions/runs/35036799296)
selected production 1.1.1 (202) and submitted it at 23:42 UTC on 15 September,
01:42 Paris time on 16 September. Both Apple's API and App Store Connect display
`WAITING_FOR_REVIEW`; release type is `MANUAL`. The production release manifest
admits review build 202 while public build 113 remains supported. The release-tools
workflow now defaults to a read-only audit, so another push cannot resubmit the app.
Beta stays usable during review; repeat the catch-up
from the retained checkpoint immediately before the manual public release. No
physical-device Apple sign-in or HealthKit test of build 202 has been performed;
Auth reads and cloud checks do not replace that installed-app verification.

## Data transfer implementation and cloud rehearsal, 16 Sep 2026

**Code:** the [one-time transfer tool](../scripts/data-transfer/README.md) is
implemented. It matches Apple identities, preserves production IDs and referral
codes, copies 33 allowlisted tables and actual media bytes, and records private
cloud checkpoints. Conflicts and deletions stop the operation. Later runs compare
source changes against their prior import and current production values. The
environment allowlist accepts only the disposable rehearsal project, never live
production. No app API, native model, or application schema changed in this work.

**Cloud checks:** the restored production copy has all 40 migrations. The frozen
beta source contained 23 accounts, with 2 identities shared by the 3 production
accounts. The import produced 24 accounts, 36 Fights, and 88 memberships while
preserving the original production history. All 52 ready media files passed
source and destination SHA-256/size checks; 2 unfinished uploads were excluded.
The default import rolled back to its exact original row digest. The committed
import matched the complete planned digest, all foreign keys passed, and repeating
the run created no duplicates. A subsequent catch-up transferred 86 changed rows,
including later Health activity and its score, with no new accounts or Fights.
That catch-up also passed rollback, commit, full-digest, and Auth checks.

Supabase Auth successfully read all 24 users and their Apple identities. A fresh
synthetic account was inserted through the corrected importer, read through Auth,
and removed; the existing dataset's digest remained unchanged. The rehearsal
caught and fixed SQL-driver JSON double encoding and Auth's required zero instance
ID/empty token fields. No passwords, sessions, devices, or Apple refresh credentials
were copied. The 50 account/role visibility checks passed for the 24 users plus an
unrelated identity, using both `authenticated` and `fitfight_backend_reader`.
The released build 113 SQL read/write fixture and forbidden-write checks passed
after import and rolled back. TypeScript, Deno checking, and all 247 backend tests
passed, including 10 transfer tests.

Initial applied checkpoint: `61c40c23-34ab-44b0-b45d-6582c68d5ec3`. Catch-up:
`29d24695-87bc-4361-a5e8-727b6d7e7f41`. Final row digest:
`b40a21dc8c809c42c6adc2348e99dc8a1faad8c3f27c2f48c357666217c01800`.
Snapshots and media stayed inside Supabase; workstation evidence contains only
aggregate results. Existing completed production backups were verified. A fresh
backup is still required immediately before any live import.
All five temporary audit/transfer/test functions were deleted, all three temporary
secrets were removed from both projects, and the local token file was deleted.
The disposable branch is paused with its private checkpoints retained for the
release follow-up.

**Live deployment:** main and production data remain untouched. At 22:57 UTC on
15 September, staging health returns 200 and its release endpoint advertises
latest 190, review 200, internal 201, with enforcement off. Production health
returns 200 without `profile_api`; its release endpoint still returns 404. The
public build 113 remains supported. No physical-device Apple sign-in or candidate
HTTP smoke test against the imported copy was performed.

Marc chose **beta always** for the shared profiles. Beta usernames, names, avatars,
and companions win on both the initial import and catch-ups. Production account
IDs, referral codes, and unrelated history stay intact. The operator's production-
profile option is removed; existing beta checkpoints remain readable.

Before production: Marc must authorize the held main/live rollout and agree the
final beta cutoff.
Apply compatible production schema/backend first, preserve a fresh recoverable
backup, repeat the verified transfer, then check installed-client login and the
production API. The completed cloud rehearsal used the now-approved beta details.
The fixed preference and profile catch-up precedence were checked with TypeScript,
Deno, and the 247 backend tests; no new cloud import was run for this policy change.

## Release workspace reconciliation, 15 Sep 2026 evening

Release preparation is merged into develop at `25f8ac8` through [#241](https://github.com/slooowshutter/FitFight/pull/241).
The 1.1.1 app, 237 backend unit tests, build 113 Auth/PostgREST compatibility,
migration/RLS and transaction tests, native build, and English/French cloud
screenshots passed. Fresh gallery captures use that native source, with the 1.1.1
version label on You only. The App Store Connect 1.1.1 draft has saved English and
French listing text and updated review instructions; production build selection,
privacy answers, final screenshots, and submission remain pending.

The direct develop-to-preview PR conflicted with prior snapshot history.
[#243](https://github.com/slooowshutter/FitFight/pull/243) resolves both histories
to the exact tested develop tree, `8f49dc4a3e3d5548e2c2b0c055a99d85d35d2f6e`.
It replaced #242 and merged to preview as `d97145a` at 22:05 UTC on 15 September.
The [TestFlight upload](https://github.com/slooowshutter/FitFight/actions/runs/35029178930)
succeeded, including processing and assignment to both tester groups. Database,
Web API, and simulator checks on the preview merge also passed. Main and the
production data transfer remain on hold.

At 22:17 UTC, the published release manifest contains internal build 201, while
the live staging endpoint still returns internal build 200 with enforcement off.
The endpoint's refresh remains to be observed; this does not prevent build 201
from using staging. No physical-device login or HealthKit check was performed.
Safari's screenshot picker stopped responding to Computer Use. The twelve new
gallery images are verified, but none is uploaded to the 1.1.1 draft yet; its
English 6.9-inch screenshot set is empty pending replacement. Saved listing text
was verified before the picker failure. Privacy answers and submission are pending.

Staging now has the three previously missing migrations: notification preferences
and social outbox kinds, Fight Realtime invalidations, and chart checkpoints.
Their tables, columns, function, and four triggers were verified live. Six older
migration timestamps were corrected only after the recorded SQL matched repository
SQL apart from whitespace. All 40 migration versions now match; a subsequent
`migration up` applied nothing. Staging health returns 200 with `profile_api: true`.

The earlier disposable production-copy rehearsal applied 28 pending migrations
and preserved 3 accounts, 14 Fights, and 14 memberships. Legacy SQL request and
permission checks passed. The completed 40-migration/data-transfer rehearsal
above supersedes this earlier evidence. The production rollout remains on hold.

Read-only live check at 21:38 UTC: staging advertises public 1.0.0 (190) and
review/internal 1.1.0 (200), with enforcement off. Production still returns 404
for `/api/app-release`; its health response lacks `profile_api`. These live results
take precedence over older availability descriptions below. Preview was at
`025f55c` at that check; the new upload is tracked by #243.

## Multiple-objective Fight rules: specified 16 Sep 2026

The [Fight rules](fight-rules.md#multiple-objectives-all-are-required),
[engine design](system-design.md#multiple-objective-goals-engine-design), and
domain glossary now define goals requiring **every Objective** to pass. Each
Objective retains its own progress, unit, source completeness, and explanation;
extra progress cannot compensate for a missed Objective. Independent Objectives
may share a Measure or use different approved Measures in the common window.

**Implementation:** documentation only. The isolated Zod draft already represents
this through named conditions and `all`; it does not evaluate activity. Runtime
scoring, APIs, database schema, and the native app are unchanged. No cloud checks
or deployment were performed. Shipping still requires approved presets, evidence
for every Metric, engine tests, and the normal compatibility rollout.

## Release workspace reconciliation, 15 Sep 2026 evening

Latest merged application code is 1.1.1 at `685507d`. The release workspace now
includes those fixes plus the English/French screenshot package and the legacy
App Store build 113 database compatibility repair. Earlier screenshot labels and
the 1.1.0 App Store draft need to be refreshed for 1.1.1.

The earlier disposable production-copy rehearsal applied 28 pending migrations
and preserved 3 accounts, 14 Fights, and 14 memberships. Legacy SQL request and
permission checks passed. That rehearsal predates the latest 1.1.1 migrations;
those still require validation. No beta history/media import or production
rollout has been performed by this workspace.

Read-only live check at 21:38 UTC: staging advertises public 1.0.0 (190) and
review/internal 1.1.0 (200), with enforcement off. Production still returns 404
for `/api/app-release`; its health response lacks `profile_api`. These live results
take precedence over older availability descriptions below. Preview is still at
`025f55c`; the newest develop fixes have not been uploaded to TestFlight yet.

## Fight chart views from stored scores: prepared 16 Sep 2026

**Code:** Oval already plots `fight_members` scores. Bars, line, histogram, and
pace now use that same stored revision: HealthKit `step_checkpoints` when the
latest snapshot has them, otherwise one point per Fight day from
`private.fight_score_snapshots.value`. Calendar `step_days` stay unused. Native
`dayCards` charts whoever already matches and leaves a gap for everyone else.
If no daily history is attached, those views plot the same totals as Oval.
A HealthKit last-day stamp uses the current Fight day, not `cutoff - 1ms`.

**Compatibility:** `/api/v1` remains. `members[].step_checkpoints` stays nullable
and additive. Older clients ignore extra populated history. Required fields,
legacy uploads, and client permissions are unchanged. No schema migration.

**Checks:** native chart regressions cover mixed/legacy peers, stale history,
totals fallback, and a cutoff 1ms after Fight-day midnight. Backend snapshot
tests cover preferring real checkpoints, synthesizing score-only days, and
leaving `step_days` unused. Cloud CI on this branch is the remaining evidence.
No hosted database mutation or TestFlight upload.

**Deployment:** prepare only. Deploy the compatible backend, then distribute
the app through the authorized `preview` flow. Do not infer production
readiness from staging.

## Fight charts and standings: prepared 15 Sep 2026

**Code:** all Fight charts now use the same confirmed score revision as standings.
Apple Health collection reads cumulative checkpoints from the Fight start to each
Fight-day boundary and the server cutoff, using the Fight's time zone. The final
query supplies both the last checkpoint and total. The backend validates and saves
them together. Daily bars are differences between those checkpoints; cumulative
curves end at the ranked total. Oval always uses the confirmed standings values.
No calendar-day total is substituted, scaled, or added to a Fight score.

Late syncs refresh the whole provisional history. Final history freezes with its
score. Missing daily data is a gap rather than a zero; cumulative views retain the
last confirmed total. Older uploads without matching history show an explicit
empty state while confirmed totals remain visible. The old native cache is not
reused, and preview fixtures now have internally consistent daily sums.

**Compatibility:** `/api/v1` remains. Upload checkpoints and context `time_zone`
are additive, as is nullable member `step_checkpoints` in snapshot responses. Existing
`step_days`, required fields, older upload behavior, and client permissions remain.
Live staging checks still admit public **1.0.0 (190)** and review/internal
**1.1.0 (200)**. Their unchanged native snapshot decoders both passed the old fixture
and new checkpoint fixture in the cloud. A new app talking to an older backend
without the context addition omits checkpoint fields. Old apps keep their original
chart behavior until upgraded; the backend cannot change their native rendering.

**Checks:** the original noon-start disagreement was reproduced in the cloud before
the fix. Production chart and collection regressions now pass for matching totals,
legacy/mismatched history, missing days, corrections, final rank ordering, DST,
midnight, and upload encoding. The
[web run](https://github.com/slooowshutter/FitFight/actions/runs/35020170623)
passed strict typecheck and **226 unit tests** on the final backend source. The
[disposable-database run](https://github.com/slooowshutter/FitFight/actions/runs/35018467286)
passed all migrations, schema lint, **204 pgTAP assertions**, **19 transaction/API
tests** before and after the later permission cutoff, and the legacy migration
replay. These cover roster privacy, canonical Fight-day boundaries, corrections,
replayed uploads, old requests without checkpoints, and final-history immutability.
Migration and query code are unchanged from that tested snapshot.
The final [hosted iOS run](https://github.com/slooowshutter/FitFight/actions/runs/35019580941)
passed at `ecbc58a`, including the complete Simulator build, native state and
API regressions, chart/cache/collection regressions, and localization checks.
Real HealthKit sample allocation, sync duration, and two signed-in phones remain
device checks; cloud collection tests use deterministic query boundaries. Collection
now performs a cumulative query per elapsed Fight day to refresh its history.

**Deployment:** prepared only. Apply `20260915200338_fight_step_checkpoints.sql`,
deploy the compatible backend, then distribute **1.1.1** through the authorized
`preview` flow. There is no trustworthy backfill for old exact daily history from
unrelated calendar totals; active Fights acquire it on new-version sync, and old
finished Fights retain their saved total without invented history. The temporary
CI branch was removed after validation; it also caused Vercel to create an automatic
branch Preview. No PR,
environment merge, hosted database mutation, staging/production deployment, or
TestFlight upload was performed. Production requires its own authorized rollout
and verification.

## Live standings: prepared 15 Sep 2026

**Code:** foreground apps listen on one private per-user Realtime topic. Committed
membership, score, rank, and Fight changes trigger an authenticated read through
`POST /api/v1/fights/snapshot`. This returns the existing snapshot contract without
maintenance or HealthKit work. The app rereads on subscription, reconnect, and
replication readiness, coalesces bursts, and rejects superseded or previous-account
responses. Local unconfirmed HealthKit totals no longer edit standings. A failed
peer refresh does not become a local HealthKit sync error.

**Compatibility:** read-only release checks on 15 Sep returned staging `latest`
**1.0.0 (190)** and `review`/`internal` **1.1.0 (200)** with enforcement on.
Production `/api/app-release` still returned **404**. Existing `/fights/refresh`,
HealthKit upload requests, snapshot fields, tables, and client grants remain
compatible. The additive migration only adds trigger-driven notifications and a
private Realtime receive policy. No `/api/v2` or permission cutoff ships here.

**Cloud database and web:** the [disposable database run](https://github.com/slooowshutter/FitFight/actions/runs/35015708589)
passed at `cfb29b1`: all migrations, 204 pgTAP assertions, 18 transaction/API tests
before and after the deferred permission cutoff, and the legacy migration replay.
The live-notification test uses ordinary local Auth sessions and actual WebSockets.
It verifies private receive permissions, denied client publication, no rollback
message, committed publication to both participants, identical confirmed members,
reconnect reconciliation, removals, unchanged writes, and sync freshness. It also
executes the existing refresh requests labelled as builds 190 and 200 and the new
read-only route. This is disposable cloud evidence, not a hosted environment test.
[Web CI](https://github.com/slooowshutter/FitFight/actions/runs/35015708541) passed
strict typecheck and all 223 unit tests.

**Native verification:** cloud Swift 6.2.4 regressions execute the production
listener and snapshot-loading methods with suspended network/platform boundaries.
They cover bursts, an event during a fetch, reconnect, replication readiness,
rapid background/foreground changes, account switching, sign-out, old responses,
and offline behavior. The original snapshot decoders from build 190 (`96b1921`)
and build 200 (`025f55c`) also decoded the preserved snapshot fixture in the cloud.
The build 200 replay only shims Linux's unavailable string-localization initializer;
its decoding logic is unchanged. The final [hosted macOS simulator build](https://github.com/slooowshutter/FitFight/actions/runs/35016144257)
passed at `97751cb`, including the live-listener/snapshot regressions, native API
fixtures, session/state checks, localization, and complete iOS compilation.

**Deployment:** prepared only. The temporary hosted-CI validation branch was removed.
No PR, environment merge, hosted database mutation, deployment, or TestFlight
upload was performed. Apply `20260915193015_broadcast_fight_changes.sql` and deploy
the compatible backend before distributing the native app through the authorized
`preview` flow. Verify two signed-in phones, with one uploading and the other
remaining on the Fight screen, plus background/reconnect and expired-session cases.
Production needs its own authorized migration, API, and release-policy verification.

Shared standings refresh is separate from the chart discrepancy. The subsequent
[chart fix](#fight-charts-and-standings-prepared-15-sep-2026) is now prepared too.

## Release review fixes: prepared 15 Sep 2026

The [release review](reviews/2026-09-15-release-review.md) records reproduced bugs,
prepared fixes, and remaining submission checks initially reviewed from `fc6d971`
on `develop`. At Marc's request, this workspace now includes `develop` at `5420653`,
including PRs #236 (release publishing), #237 (photo/caption taps), and #238
(version label on You only).
Marc requested **1.1.1** for this candidate. Release settings, the new release note,
and current shipping instructions use that version; the last upload remains **1.1.0 (200)**.
Changes are in the workspace only. No PR, push, deployment, TestFlight upload,
hosted database mutation, or new cloud CI run was performed.

- Reactions update immediately, roll back on failure, and preserve concurrent
  comments/edits. Feed writes no longer return an error just because notification
  delivery fails after the write was saved. This failure was reproduced locally;
  no live signed-in error log was available to attribute all reported errors.
- Pull refresh uses one spinner, overlapping refreshes wait for the same work,
  and the three forced 480 ms phase delays are removed. Session restoration shows
  neutral loading until Auth restores a session or confirms signed-out state.
- Suggested/Join prefetch at launch and foreground, share a 60-second account
  memory cache, retain cached rows on failure, and load independently. The normal
  joinable list uses one database request instead of `1 + 4N` requests for `N` rows.
- Fixed cancelled photo loads, unbounded outer image retries, hidden-parent
  comment display, stale comment descendants after deletion, push registration
  after sign-out, and account deletion losing media references on Storage failure.
  Daily-status generation now checks preference and device eligibility first.
- Added missing privacy-manifest declarations and corrected privacy/submission
  drafts. AI-sharing consent and external feedback/crash-copy retention remain
  unresolved; documentation changes do not implement those decisions.

**Startup review follow-up:** the loading gate now also accepts a valid session
from `tokenRefreshed`, which Supabase can emit before `initialSession` on cold
launch. A cached signed-in session is usable while the profile request runs.
Added a regression that queues both events and suspends profile loading; native
execution remains pending in the existing GitHub-hosted session/push suite.
Localization, native API-boundary, and whitespace checks passed. No API or
database contract changes are involved.

**Code checks before develop integration:** web typecheck, 217/217 unit tests and production build passed.
Remaining-time and API contract checks passed; normal signed-out launch and fixture
navigation were exercised. Web code was preserved byte-for-byte during integration.

**After develop integration:** the user-authorized iOS Simulator build passed and
its bundled marketing version is **1.1.1**. Native async-state checks passed 38/38;
discovery, session/push, image, update-gate, API boundary and localization checks
passed. Fastlane passed 20 tests / 92 assertions. The overlapping photo, refresh,
reaction, and startup changes received an independent integration review. These
checks do not authenticate a real account, deliver APNs, or exercise HealthKit on a phone.

**Compatibility:** read-only checks on 15 Sep still admit public **1.0.0 (190)**
and review/internal **1.1.0 (200)** on staging, with enforcement on. Their source
request/response contracts were inspected, and their actual native decoders passed
the affected reaction, discovery, and old/new comment-creation/deletion fixtures. Existing
`/api/v1` fields remain intact. Device revocation is an additive authenticated
`DELETE /api/v1/device-installations`; comment creation/deletion add `comment_count`
alongside the existing response fields, with optional native decoding for the older server.
There is no database migration or permission cutoff in this change.

**Cloud/live:** staging `/api/health` returned ready with `profile_api: true`.
Production `/api/app-release` still returned **404**, and its ready health response
still omitted `profile_api`. The new joinable-list integration test is wired to the
existing disposable cloud database suite but has not run without its credentials.
No cloud or production readiness is inferred from the local or staging results.

**Order and remaining checks:** deploy the compatible backend via an authorized
`develop` promotion before distributing the native update via `preview`. Run
cloud database/CI checks and the exact candidate with signed-in accounts on
devices. Production needs its own authorized rollout, release-policy/profile-API
verification, and the existing migration checks. The candidate version is **1.1.1**;
CI will allocate its build number at archive time.

## Feedback navigation simplification: prepared 15 Sep 2026

Feedback now opens on one ranked **Top** board, with the compact **Features** and
**Bugs** filters beside it. The large Bugs / Top / Report row and embedded Report
pane are removed. Both **+** and **New request** open the request form directly;
the Feedback plus menu no longer offers a feed post. The Feed plus still opens
its post composer. The You shortcut and Feedback reselect return to Top.
A **1.1.1** release note and French translation are included.

**Checks:** the Debug build passed and was relaunched in the requested iPhone 17
Simulator. Top showed the combined board; Features and Bugs filtered it correctly.
Tapping plus opened New request directly, Close returned to the board, and the
request sheet had no version label. Localization, native API-boundary, and whitespace
checks passed. These UI checks used sample data and did not submit a request.

This is native navigation only. Existing vote ordering, request creation, API
contracts, and database schema are unchanged. No deployment or TestFlight upload
was performed.

## Feed comment order: prepared 16 Sep 2026

Feed post comment threads now show an on-thread **Most comments** / **Most recent**
control. Default is **Most comments**. This is not a new tab and does not change
Feedback comments or the Feed post list.

**Contract:** additive optional `sort=comments|recent` on
`GET /api/v1/posts/{postID}/comments`. Omitted `sort` keeps the installed oldest-first
page. Response shape is unchanged. No database migration. No app-facing RPC.

**Live rollout check:** staging `/api/app-release` on 16 Sep 2026 returned
`latest` **1.1.1 (201)**, `review`/`internal` null, `enforced: false`. Preserve that
omitted-sort contract for admitted clients. Production readiness is recorded in the
production rollout section above. This change is not deployed yet.

## Post reactions and expanded comments: prepared 15 Sep 2026

Feed and fight posts now offer **View reactions**, listing usernames, display names,
and emoji with pagination. Existing comments expand and load when the post appears;
the first comments added to an empty post also open after its count refreshes.
English/French copy and a **1.1.1** release note are included.

**Contract:** additive authenticated `GET /api/v1/posts/{postID}/reactions`, returning
`people` and `next_cursor`. Access uses the existing post-membership check; the query
omits deleted profiles and people the viewer has hidden, including a hidden post author.
The existing reaction `POST`, feed summaries, and comment responses are unchanged.
No database migration is required. The read-only staging release-policy recheck still
admits public **1.0.0 (190)** and review/internal **1.1.0 (200)**, with enforcement on.
Production `/api/app-release` still returns **404**.

**Checks:** web typecheck and **220/220 unit tests** passed, including the unchanged
reaction write fixture and new list-pagination/access/query-validation cases.
Localization and native API-boundary checks passed when this change was prepared.
At Marc's subsequent simulator-preview request, the Debug Simulator build, shared
native-decoding fixtures, and 38 native async-state checks passed. The preview now
supplies sample reaction names without authentication and was launched on iPhone 17
with iOS 26.5 using `./scripts/run-companion-preview.sh`.
Disposable-database membership/block/deletion tests are wired into existing cloud CI
but remain unrun without its credentials. Signed-in UI verification remains pending.

**Rollout:** workspace changes only. Deploy the compatible backend through an authorized
`develop` promotion before distributing the native change via `preview`. No PR, push,
deployment, TestFlight upload, or hosted database write was performed for this change.

## Cancellable TestFlight updates: prepared 15 Sep 2026

Marc requested a way to keep using FitFight when TestFlight has nothing to install.
The prepared **1.1.1** app replaces TestFlight's Check again button with **Cancel**.
It only offers a newer public `latest`, never an internal/review-only release or an
older build from stale metadata. Cancel remembers the dismissed release across
foreground/minute checks and relaunches, including a check already in flight.
Failed checks clear the notice, and legacy saved locks or stale `426` responses
cannot block TestFlight app/API use. Production retains its existing mandatory gate.

**Backend and compatibility:** staging always returns `enforced: false`, including
when the raw publisher manifest says true. Authenticated commands no longer reject
TestFlight versions/builds; account authentication remains required. The
`/api/app-release` JSON fields and `/api/v1` request/response shapes stay intact.
Regression requests include public **1.0.0 (190)**, review/internal **1.1.0 (200)**,
older builds **189/199**, and an unregistered newer **1.1.1 (201)**. No database
migration or permission change is included. Optional updates cannot authorize
retiring older clients' API contracts.

**Workspace checks:** the release regression first failed with `Update FitFight to
continue` and then passed after the backend fix. All **222 backend tests** passed,
including **14 release tests**, authentication/account checks, and the existing
contract coverage. English/French localization and native API-boundary checks passed.
Full web typecheck was blocked by the separate in-progress `fights_snapshot` argument
in `web/app/api/v1/fights/snapshot/route.ts`, which is outside this update change.
Native cancellation/availability tests are added to the existing GitHub-hosted
macOS check, but were not compiled or executed in this turn. No local Xcode build
or new cloud CI run was performed.

**Live evidence:** read-only checks on 15 Sep still returned staging public
**1.0.0 (190)**, review/internal **1.1.0 (200)**, and `enforced: true`. A request to
`GET /api/v1/me` with **1.1.0 (199)** and an intentionally invalid audit bearer
returned **426 update_required** before authentication. Production's release
endpoint returned **404**. These observations describe the existing deployment;
the fix is in the workspace only.

**Rollout:** deploy the compatible backend via an authorized `develop` promotion
first, verify staging `enforced: false` and that old-version requests reach normal
authentication, then distribute the native update via `preview`. Older installed
binaries ignore `enforced` in their overlay logic, so the backend alone cannot add
Cancel or clear every old native lock. They must install this new build once.
Cloud iOS checks and device verification of Cancel/returning from TestFlight remain
pending. No PR, push, deployment, TestFlight upload, or hosted database write was
performed for this change.

## API and update rollout (verified 13 Sep 2026)

Read-only checks on **13 Sep 2026 (UTC)** supersede the earlier blanket "prepared, not deployed"
description for staging. Recheck these endpoints before any rollout; build numbers
and availability are observations, not permanent configuration.

| Part                           | Observed status                                                                                                                                                                                                                                                                                                                                                                                           |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Native/API separation          | Current source calls `/api/v1`, sends app version/build headers, and routes application database access through `FitFightAPI`. The full update overlay checks release eligibility at launch/foreground and every minute while active, and only replaces the app when the installed build is known to be outdated. A failed or offline check leaves the app usable. No `/api/v2` is needed or implemented. |
| Staging release policy         | [`/api/app-release`](https://staging.fitfight.app/api/app-release) returned 200: `latest` 184, `review`/`internal` 189, all `1.0.0`, `enforced: true`.                                                                                                                                                                                                                                                    |
| Staging backend enforcement    | A read-only `GET /api/v1/me` with build 183 and an intentionally invalid audit bearer returned `426 update_required` before authentication. No real user session or data was used.                                                                                                                                                                                                                        |
| Staging profile readiness      | [`/api/health`](https://staging.fitfight.app/api/health) returned `schema: ready`, `profile_api: true`. This readiness check includes the additive profile migration and backend reader role.                                                                                                                                                                                                             |
| Production                     | [`/api/app-release`](https://fitfight.app/api/app-release) returned 404. `/api/health` returned 200 with `schema: ready` but no `profile_api` marker. The public release manifest had no production latest/review/internal build and `enforced: false`. Production rollout of these protections is incomplete.                                                                                            |
| Automatic availability refresh | `.github/workflows/app-releases.yml` is absent from default branch `main`, so its 15-minute schedule is not active. Uploads and matching `develop` pushes refresh the manifest; background discovery of later Apple availability still needs normal authorized promotion.                                                                                                                                 |

Cloud evidence: the [preview simulator run](https://github.com/slooowshutter/FitFight/actions/runs/34764089855)
passed native update tests, API fixtures, release-selection tests, and compilation at
`2b03b13`. The latest checked `develop` commit `c819fd2` passed
[web typecheck/tests](https://github.com/slooowshutter/FitFight/actions/runs/34766054191)
and [database/RLS/permission-cutoff tests](https://github.com/slooowshutter/FitFight/actions/runs/34766054167).
These runs test repository code in disposable environments; they are not a production
deployment or proof of every historical client's compatibility.

Still needed: signed-in device verification of the public/internal builds, production
migration/backend/release-policy rollout, the scheduled updater on `main`, and a
separately authorized direct-client permission cutoff. This audit did not inspect
hosted database grants or perform App Store/device testing. Future changes follow
[the mandatory API compatibility procedure](shipping.md#api-compatibility-for-every-change).

## Companion and custom schedule PR: prepared 13 Sep 2026

The live staging policy still admits public build **184** and review/internal **189**, all `1.0.0`, with enforcement on (read-only recheck before PR preparation). This change keeps the existing `/api/v1/fights` request/response shape: old requests still default to `start: now`, while explicit scheduled requests retain their exact timestamps and enter the existing `scheduled` state even with invitees. Regression tests cover both creation paths; shared native decoding fixtures remain unchanged. No database migration or direct-access cutoff is included. Deploy the compatible backend from `develop` before distributing the native change via `preview`; no hosted deployment or individual released-binary/device test was performed here.

## Backend-only database access: staging ready, production pending

Native profile loading, username selection, and Apple display-name saving now use
`GET/PATCH /api/v1/me`; all application database traffic goes through the backend.
Supabase Auth stays direct. The Fight snapshot uses a restricted backend read role
with the existing row-visibility rules. Staging readiness and cloud checks passed as
recorded above; production must verify/apply the additive migration and deploy the backend
before distributing its app. The separate direct-client permission cutoff remains outside
automatic migrations, as described in [backend.md](backend.md#application-database-boundary).
Signed-in staging-device verification was not performed by this audit.

## Prepared, not deployed: Notion Product Backlog (9 Sep)

New Bugs & requests posts create a **P0 Inbox** row in Blend HQ → Product Backlog
(Product FitFight, Source App feedback, Type Bug or Feature). Add `NOTION_TOKEN`
to Vercel Preview and Production and share Product Backlog with that integration.
A missing token leaves the in-app post working and skips Notion.

## GitHub vs Supabase (the two pairs)

There are two **hosted databases**. Git uses a promotion train.

|             | Integration                                              | TestFlight                                                                                  | Real users / App Store                            |
| ----------- | -------------------------------------------------------- | ------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| GitHub      | `develop`                                                | `preview`                                                                                   | `main`                                            |
| TestFlight  | no upload                                                | push/merge to `preview` (optional manual `workflow_dispatch` on that branch; no daily cron) | never; `main` does not upload to TestFlight       |
| Supabase    | develop project (`zstzbf…`, version line says `staging`) | same staging backend                                                                        | production (`pvqn…`, version line says `prod`)    |
| What you do | Merge PRs **into `develop`**.                            | Merge `develop` → `preview` for a TestFlight.                                               | Merge `preview` → `main` only when Marc says ship |

A feature PR is another git branch. Merge it **into `develop`**. That updates the **staging** database (new SQL) and is the home for later chats. It does **not** upload TestFlight.

Once configured, Vercel accepts small authenticated Apple Health aggregate requests and receives account-deletion commands. The phone sends Apple's merged Steps total for each exact Fight window, plus merged daily buckets only for the relevant Fight chart days. The same request may also send private merged activity totals and workout summaries. Those extras are stored for later challenge types and do not score Steps fights. Create, join, and leave go through the API. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Before this branch ships

The mandatory-update manifest and `GET /api/app-release` are live on staging; production still needs the endpoint before its native build, and the scheduled publisher must reach `main`. The existing server `NEXT_PUBLIC_SUPABASE_URL` selects the staging/production release channel. The deployed native app still uses the blocking overlay. The [prepared cancellation fix](#cancellable-testflight-updates-prepared-15-sep-2026) makes TestFlight updates optional and stops staging API version blocks. No database migration is part of the update check itself. See [update policy and database rollout](shipping.md#mandatory-updates-and-database-rollout).

The 7 Sep referral changes require the referral migration, `POST /api/v1/referrals`,
and updated Universal Link association before the native build. You → Settings →
Refer a friend shares `/r/{profile-referral-code}`; fight links include `?ref={code}`.
Uninstalled iPhone users go to TestFlight after five seconds. They must reopen the
original message link after installing; sign-in and username setup then resume the
referral and challenge. Workspace checks do not replace cloud CI or two-phone testing.

The 5 Sep performance changes require the timing-history migration and the backend's new `POST /api/v1/fights/refresh` before the native build. Fights now load through one API request; aggregate uploads and finalization batch their database writes. Private timing attempts distinguish HealthKit, authentication, upload and final refresh time. Workspace checks are not a deployed TestFlight build; cloud iOS/PostgreSQL validation and staging measurement remain required.

Apple Health synchronization requires `FITFIGHT_API_URL=https://staging.fitfight.app` plus Vercel's server-only Supabase URL/secret and pooled `DATABASE_URL`. Fresh Apple sign-in and automatic revocation also require the Vercel Sign in with Apple Team/key/private-key/client-ID values and stable token-encryption key. Configure those first; otherwise sign-in fails visibly. Do not expose schema `private`.

After the backend is configured, merge the feature PR into **`develop`**, not `main`. The staging migration must land before merging `develop` → `preview` for the TestFlight build.

The 9 Sep Feed destinations change needs `20260909233000_feed_destinations_and_engagement.sql` plus the feed/posts, people, comments, and reactions APIs deployed before the native build. Old `GET /api/v1/feed` still returns only fight-audience posts so installed builds keep decoding. The 12 Sep one-feed list uses `GET /api/v1/feed?scope=all` (Main and fight posts). Current Feed uses `GET /api/v1/feed` with no scope (fight posts from membership only), plus Marc `app_wide` broadcasts after `20260916204500_feed_app_wide_broadcast.sql`.

Verify the minimal product alongside Apple Health synchronization:

1. After the 1.1.1 candidate is uploaded and available, TestFlight → **Update**. Look for `1.1.1 · build N · staging` at the top of You.
2. Check Fights, a Fight detail, New, You, and Feedback in both Night and Day. There are four tabs: Fights, New, You, Feedback. Feedback opens on the same fight posts Feed; Bugs, Top, and Report sit beside Feed. Each post identifies its channel with plain text beneath the author. A fight opens on Stats, with Feed and Share beside it.
3. New starts on Create, Join, or Post. Create still guides Steps, duration, private by default (or public), optional usernames, repeat on by default, optional title and action, and review. Every fight has a code and a share link; people join with that code or invite link. Join is that code plus a live public list with no scores. Private fights stay off the list. Suggested fights that Marc flags show under those choices. Earlier create steps use **Next**. Review uses **Slide to start**.
4. Confirm sign-in, username, Apple Health Steps, Fight invitations, standings with last-sync times, Privacy, Support, Bugs & requests, Versions, sign out, and Delete account.
5. Confirm the old Requests tab, friend requests/lists, money, other Metrics, and dead settings are absent.
6. If sign-in fails: hosted **develop** Supabase → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

The native Fight path uses the API to create and join; Apple Health synchronization and account deletion also require Vercel.

---

## What this build does

| Surface                 | Status                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Welcome + Apple sign-in | Works                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Languages               | English and French follow the iPhone's per-app language. Usernames, Fight names, and loser actions remain exactly as entered.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Username onboarding     | Works. Required once after sign-in. Optional profile photo on the same screen; then Connect Apple Health; then challenge reminders (pre-prompt before iPhone’s sheet); then a last screen that the Feedback tab can take a feature or a bug. Existing accounts keep You → Apple Health.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Version line            | The next prepared release-candidate TestFlight says `1.1.1 · build N · staging` at the top of You only; the App Store build says `prod`                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| Create Steps challenge  | Follow a guided flow: Create, Join, or Post, then Steps × highest total, 3 / 7 / 14 / 30 days or Custom with exact future start and end dates/times, private by default (or public), optional usernames, repeat on by default, optional title and loser action, and review. Public and private fights may start with the owner alone. Every fight gets a code and a share link; people join with that code or invite link. Suggested fights that Marc flags appear on New. The person who created a live or upcoming fight can Edit it from the same last-step summary as create: Change opens that create page, then back. The owner also gets Delete at the bottom, which cancels the fight (final stays frozen) and pauses a repeating series. Finished fights stay frozen.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                    |
| Accept / Join           | Invites still accept in the fight. Anyone can open the same Accept/Join screen from a code or a shared link. Public fights also appear on the live Join list with no scores. Private fights do not. Joins go through the server. If a repeating fight is past its start day, joiners choose this round (steps count from that start date) or the next round. Same-day joins, even hours later, still count as this round. People waiting for the next round are visible on the fight and do not count in this round. Leave a public, private, or repeating fight from the fight itself so the next window does not copy you in.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Invite participants     | Exact username in New is optional on public and private fights. They must have signed in and chosen a username. There is no friendship or friend-request layer.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Apple Health            | Installs background delivery at launch, keeps one interrupted opportunity for foreground reconciliation, and shows private capability/sync status under You → Apple Health → More settings. It sends Apple's merged cumulative Steps total for each exact active/ending Fight window in one small authenticated request. The same request may also send private active and resting energy, distance, exercise, stand, flights, and workout summaries including each workout's active minutes. Extra activity is stored separately so a workout-details failure cannot roll back Steps. You shows the real server or network error on the Apple Health row instead of only "Sync failed", and a failed sync is Retry, not Connected. Extra activity is not a Fight option yet.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     |
| Daily totals            | Sends Apple's merged daily buckets only for days relevant to active Fight charts. They are display data, not the source of the Fight score.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Fights list             | Every row is titled by the fight name. If there is no title, the loser action is used; older fights still stored as `Steps Fight` show the action the same way. The right-hand number is your gap to the person you are racing, moss when ahead and ember when behind; remaining time sits under the title as months, weeks, days, hours, and minutes, with days and hours when under two days, and without the calendar end date. There is no moss hero: live Fights are all the same size. Pull to refresh on Fights, a fight, Feedback, and You stays open with the current sync sentence; opening the app shows the same while Steps are read, uploaded, and standings refresh.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Standings               | Live scoring uses exact Fight-window HealthKit aggregates, not overlapping whole-day totals. Both phones read the same serving rows. Each standing shows relative sync freshness; ended Fights distinguish exact final-window coverage from the last available Steps.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             |
| Fight end               | Exact `ends_at` is the final cutoff. The fight screen and finished list show that date and time. The live list shows remaining months, weeks, days, hours, and minutes instead of the stop date; under two days it shows days and hours. Opening the app closes due fights; the protected Vercel cron runs daily if nobody opens it. After finalization, later Steps cannot change the result. **Fix in PR (not on TestFlight yet):** Finished shows **P** during `awaiting_final_sync`. After 24h, people who did not submit forfeit; both miss is a draw.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Tabs                    | Fights, New, You, Feedback. Feedback holds the same fight posts Feed, Bugs & requests, Top ranking, and a Report form. The old Requests tab and Design are removed.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| Look                    | Night/Day, Nunito, fixed Moss/Ember/Gold semantics; no accent picker or public design-system showcase.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                            |
| Versions                | Works under You → Settings (the public changelog). The version label is only on You. Do not put it on Fights, New, Feed, or Feedback. Tapping it opens the admin/debug menu only for signed-in username `marc`.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| Bugs & requests         | Works on the Feedback tab (Bugs, Top, and Report), with a shortcut still on You above Settings. Signed-in people can post a bug or a feature request, attach a photo, a video, or any file, browse the board, upvote, and comment with their username. Device/debug metadata is stored when someone posts or comments, omitted from the board API, and attached again when Marc taps Send to Cursor (original snapshot plus the phone that sent it, plus attachment links). After `NOTION_TOKEN` is on Vercel, each new post also lands as a P0 Inbox row in the Product Backlog. After `CURSOR_API_KEY` is on Vercel, Marc sees **Send to Cursor** on a post and can start a cloud agent with the post, comments, those device snapshots, and attachment URLs. A successful send moves the matching Notion Product Backlog row to Building; when that agent finishes and opens a PR, FitFight marks the same row Done.                                                                                                                                                                                                                                                                                                                                                                           |
| Privacy / Support       | Pages are implemented and linked under You → Settings. Staging uses `staging.fitfight.app`; production uses `fitfight.app`. Each route must be deployed before that build is tested or submitted.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                 |
| Fight posts / Feed      | Marc (username `marc`, You → Developer) can post one Broadcast that every signed-in user sees on the Feed tab; it is a normal post, not copied into each Fight, and it does not send a new lock-screen alert. Accepted and waiting-next-round members can post a short note, up to four photos, or one short video. Root Feedback → Feed is the same fight posts list as before (not a Recent/Top ranking of loaded posts). Root + chooses a new post or a new request. Media can take a photo with the camera or pick photos and video from the library. Posting to several fights keeps one post and shows those fight names; All fights shows Public. A fight’s Feed tab starts on that fight and can add other channels. There is no Main destination or tag-people picker. Each card puts its plain channel label, then the relative time, beneath the author, with actions at the top right. Posts support emoji reactions, nested comments, editing/deleting your own post, reporting another post and hiding its author. Other members of that fight can get a push when you post in that fight’s Feed; the post author can get comments and reactions; a reply notifies the parent commenter, not sibling commenters. You → Settings → Notifications turns each of those on or off, plus challenge reminders and daily status. Fight detail opens on Stats, with Feed, Share and recurring History alongside it. Recurring fights retain earlier posts; invited-only people gain access after joining. |
| Companion               | Saved on the account. Change animal opens the animal grid. Make it yours opens a description to edit and save (species, breed or race, accessories, colors, and other details). You can change animals anytime. That text is stored for later image generation; generation is not built. Other people see the stock animal, or initials until a custom image exists. People who have not chosen an animal are asked the next time they open a build that includes this. Pose and generation controls are not shown.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
| Account deletion        | Permanently deletes the profile, photos, username, authentication, Health/Steps data, relationships, invitations, memberships, scores, owned Fights, fight posts, and bugs/requests the User posted; removes participation from other Fights; clears local Health sync state; and revokes a stored Apple credential when available.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                               |
| WHOOP / Strava          | Not built                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         |
| Removed scope           | No persistent friends, Requests tab, money/payouts, bragging-rights option, other Metrics, goals, or dead settings/actions.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                       |

---

## Honest limits

- The server accepts a signed-in User's device upload as their own activity. Fine for two friends; not anti-cheat yet.
- FitFight trusts Apple's current merged aggregate from the signed-in User's device. It does not retain the underlying raw samples or source/device provenance, so this is not an anti-cheat or audit trail.
- Apple may revise its merged total after a Watch sync, edit, or deletion. Live snapshots can change until the exact Fight-end value is finalized; chart buckets never overwrite that exact-window score.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` owns Apple Health aggregate ingestion and account deletion. There are no app-facing Postgres RPCs.
- Companion sport scenes are not generated. Custom descriptions are stored on the account for a later job. Hiking goat still has five distinct images on You and fights for a stock goat.

---

## Next product work

Honest pending result after a fight ends (P, not W) while someone still has not submitted final steps. Then 24h forfeit + server-owned final-sync reminders. Plans: [`research/pending-final-sync-plan.md`](research/pending-final-sync-plan.md), [`research/apns-remote-push-plan.md`](research/apns-remote-push-plan.md).

Two phones: invite by exact username, accept, run a 3-day Steps challenge, verify the title or action and matching standings, and confirm the Fight finishes at the cutoff. Also smoke-test creation for 7 / 14 / 30 days. Then App Store when Marc says.

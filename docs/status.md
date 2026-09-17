# FitFight status: what works, what’s fake, what’s next

Read this before building. Last updated **16 Sep 2026**. Production candidate: **1.1.1 (202)**.

Do **not** restore removed surfaces. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, or a broader marketing site unless the [Notion Product Backlog](https://app.notion.com/p/3d38907c7ecf816facdff36cb59f463e) says so. Fight posts, the Feedback tab, challenge-reminder pushes, and feed social notifications are in this build. Only the public privacy and support pages exist on the web.

---

**Last TestFlight:** 15 Sep 2026 at 22:16 UTC. **1.1.1 (201)** from [#243](https://github.com/slooowshutter/FitFight/pull/243). Apple processing is `VALID`. Internal Tester receives it; Friends Beta is assigned the same IPA and waits for Apple beta review (`WAITING_FOR_BETA_REVIEW`). The published release manifest lists `latest` 190, `review` 200, and `internal` 201.

## App Store description draft: saved 17 Sep 2026

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
project-file syntax, and whitespace checks. Cloud configuration of the live
release setting is pending. No PR, merge, review submission, or build upload has
been performed for this update.

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
| Companion               | Saved on the account. Pick from a grid of animals, or Custom with one description (species, breed, accessories, colors). That text is stored for later image generation; generation is not built. Other people see the stock animal, or initials until a custom image exists. People who have not chosen an animal are asked the next time they open a build that includes this. Pose and generation controls are not shown.                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      |
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

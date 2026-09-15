# Release review, 15 September 2026

## Outcome

Reviewed the current native app, API, media/deletion paths, notification lifecycle,
and release configuration initially from `fc6d971` on `origin/develop`. Prepared
fixes in the workspace. At Marc's request, integrated `develop` at `5420653`,
including PRs #236 (release publishing), #237 (photo/caption taps), and #238
(version label on You only). No PR, push, deployment, TestFlight upload, or hosted
database mutation was performed for these review changes.

Marc requested **1.1.1** for the next candidate. Xcode/Fastlane/workflow settings,
the new release note, and current shipping instructions now agree on that version.
The last uploaded TestFlight remains **1.1.0 (200)**; no 1.1.1 build was uploaded.

This review found and reproduced several defects. It is not a guarantee that the
production candidate is ready: the production rollout and signed-in device checks
below remain necessary.

## Product behavior

| Finding | Prepared change | Evidence |
| --- | --- | --- |
| A saved reaction could return `500 Internal error` when the subsequent notification worker failed. | Feed writes retain durable notification enqueueing, then schedule delivery after the response. | Failure injection reproduces the old 500; the changed path returns the existing success response. This matches a possible cause of the reported symptom, but no signed-in live error log was available to attribute every reported error. |
| Reactions waited for the server and late responses could overwrite comments or another account's state. | Immediate count/selection changes, rollback on failure, one pending reaction per post, current-post merging, and account ownership checks. | Suspended HTTP regressions cover add, remove, switch, failure, reload, edits, and account changes. |
| Pull refresh showed multiple spinners and overlapping callers could return before refresh finished. | Keep one native pull indicator with sync text, await active refreshes, share overlapping foreground work, and reload a fight's Feed when refreshing its detail. | Async-state regressions and native build. Sustained signed-in pull behavior still needs a device check. |
| Every sync phase waited at least 480 ms even when its work had finished. | Remove the three forced waits. | The old empty-phase harness took about 0.488 seconds; the regression now requires under 0.2 seconds. This removes approximately 1.44 seconds of deliberate delay per complete refresh. |
| Launch briefly showed Apple sign-in before the saved session was restored. | Show neutral loading until Auth restores a session or confirms signed-out state. A valid `tokenRefreshed` event also ends loading before any profile request. | Existing tests cover unresolved, restored, signed-out, and fixture sessions using the production listener. A follow-up regression queues `tokenRefreshed` before `initialSession` and suspends profile loading; its native execution is pending cloud CI. |
| Suggested and Join were fetched again when their view was recreated. | Prefetch at launch/foreground, fetch both lists concurrently, retain a user-scoped memory cache for 60 seconds, and invalidate freshness after membership/fight edits. | Cache tests cover concurrent calls, warm visits, independent endpoint failures, offline retention, account switching, and a mutation invalidating an in-flight request. No persistent discovery cache or database schema change is introduced. |
| Listing public fights made one series request plus four requests per row. | Fetch ordinary list summaries in one bounded request, preserving the existing expired recurring-round path. | Request-count regression: eight rows previously needed 33 requests, and 50 rows implied 201. Both ordinary cases now require one request. Real PostgREST integration is pending cloud CI; this is not a live latency measurement. |
| Missing photos retried indefinitely; cancelled old loads could replace newer images. | Remove the outer retry loop, use the existing bounded loader, clear changed images, and ignore cancelled completions. | Both defects reproduced against the actual image task and passed after the fix. |
| Feed data and pending mutations survived account changes. | Clear account-owned state and reject late loads/save completions from the previous account. | Native regressions include failed loading after an account switch and stale create/edit/delete/comment completions. Comment creation returns the authoritative count so a concurrent reload does not double-count it. |
| A visible reply disappeared when its parent was hidden; deleting a parent left its replies and an incorrect count onscreen. | Promote replies with missing parents to root rows, group children in one pass, and remove loaded descendants after deletion. The server returns the visible comment count. | Hidden-parent and nested-deletion regressions; both legacy and additive deletion response fixtures decode. |
| Signing out left the device eligible for private push notifications. | Unregister locally immediately, clear delivered notifications, and revoke only that account's matching device token after any in-flight registration. Register again after login. | Production-source harness covers registration/revocation ordering, account switching, and offline sign-out. Backend tests preserve other devices and require authentication. |
| Account deletion erased media references before attempting Storage cleanup and swallowed cleanup failures. | Remove stored media before committing account deletion, retain the account on cleanup failure, and batch Storage deletion at 1,000 objects. | Failure-injection and 2,001-object batch regressions. Storage and PostgreSQL cannot commit atomically: if Storage succeeds and the database later fails, retrying account deletion remains necessary. |
| Daily-status wording was generated for accounts that disabled it or had no eligible device. | Filter the daily-status preference and authorized, unrevoked device registration before calling the model provider. | The original daily-status tests and a new generation eligibility regression pass. |
| The privacy manifest omitted uploaded photos/videos and the push device identifier; policy and submission drafts omitted current processors. | Add the missing data declarations and correct the English/French policy and submission drafts to describe the implemented behavior. | Plist validation and both local privacy routes pass. AI-sharing consent and external-copy retention remain owner decisions below. |

## Standards

- Removed confirmed unused media/deletion code and the redundant photo retry loop;
  retained preview fixtures and historical compatibility paths that still have callers.
- Kept Supabase queries in `web/lib/supabase/queries/`, new runtime schemas under
  `web/lib/types/`, `/api/v1` contracts, strict TypeScript, existing design tokens,
  and the version label at the top of You only.
- Added native regression runners to the existing GitHub macOS workflow. They
  compile production methods with controlled Auth/HTTP/HealthKit boundaries. They
  test state transitions without adding production-only test hooks or an XCTest target.
- Corrected technical privacy/submission drafts separately from application behavior.
  Those drafts still need the owner's review of legal choices and processor retention.

## Compatibility and deployment order

Read-only staging release checks on 15 September returned public **1.0.0 (190)**
and review/internal **1.1.0 (200)**, with enforcement on. Build 190 comes from
[`96b1921`](https://github.com/slooowshutter/FitFight/commit/96b1921), verified in
[its upload run](https://github.com/slooowshutter/FitFight/actions/runs/34775895095).
Build 200 comes from
[`025f55c`](https://github.com/slooowshutter/FitFight/commit/025f55ce8a5badad78958fc25dc6d2780533da53).
The affected older native reaction/comment request methods, response models, and
joinable model were inspected against the supported release sources. The actual
build 190 and 200 native decoders both passed the reaction, discovery, and legacy/
additive comment-creation/deletion fixtures. This is source-level compatibility evidence,
not a test of the distributed binaries against a deployed backend.

Existing reaction, comment, post, discovery, account deletion, and registration
request/response fields remain intact. `DELETE /api/v1/device-installations` is an
additive authenticated operation; old clients continue using the same registration
body. Comment creation/deletion retain their existing response fields and add
`comment_count`; the new native count is optional for compatibility with the
previous backend. No schema
migration, app-facing RPC, API version bump, or client permission
cutoff is part of this change.

Deploy the compatible backend before distributing the native update. Staging
deployment still requires the normal authorized promotion to `develop`, then
`preview` for TestFlight. Production requires its own authorized rollout and checks.

## Verification

### Workspace checks

The user explicitly authorized local iOS Simulator testing for this review.
- After develop integration, iOS Simulator Debug compilation passed and the
  built app's `CFBundleShortVersionString` was verified as `1.1.1`.
- Native async-state checks: 38 passed. Discovery cache, push/session, remote
  image, and update-gate suites passed again after integration. Remaining-time
  and API decoding checks passed before integration and their source was unchanged.
- The update-gate suite was run from a temporary copy with its GitHub-only runner
  precondition removed. This was a local test, not GitHub-hosted evidence.
- Native API boundary and English/French localization validation passed.
- Fastlane release tests after integration: 20 tests, 92 assertions, no failures. Only test doubles
  contacted the lane; no Apple action was performed.
- Web typecheck, 217/217 unit tests, and production build passed before integration.
  All web files were preserved byte-for-byte during integration.
- Final whitespace, workflow wiring, and added-line typography checks passed.
- An independent integration review confirmed photo presentation, refresh,
  reactions, image loading, startup restoration, and You-only version placement.
- Simulator UI checks covered normal signed-out startup and fixture navigation
  through Fights, fight detail/Feed, New/Suggested/Join, Feed, and Feedback.
  The fixture path does not authenticate or perform hosted writes. The UI control
  tool lost the simulator window before You could be checked.

### Cloud and live checks

No new cloud CI run was triggered for these workspace changes. The new disposable
database integration test must run in the existing GitHub-hosted database workflow.

| Endpoint | Read-only result on 15 September |
| --- | --- |
| `https://staging.fitfight.app/api/app-release` | 200, public 190, review/internal 200, enforced |
| `https://staging.fitfight.app/api/health` | 200, staging, schema ready, `profile_api: true` |
| `https://fitfight.app/api/app-release` | 404 |
| `https://fitfight.app/api/health` | 200, production, schema ready; no `profile_api` marker |

These observations do not prove the production profile/API migration rollout is
complete. Staging success cannot substitute for production evidence.

## Before App Store submission

1. **Production readiness:** deploy and verify the release-policy endpoint, profile
   API, compatible backend and required existing migrations. The current 404 is an
   actual rollout gap.
2. **Device verification:** run the exact candidate with signed-in accounts through
   reaction success/failure, pull refresh, cold launch, create/join/leave, two-person
   HealthKit scoring/final sync, notification sign-out, and account deletion.
   Simulator fixtures and boundary doubles cannot prove those integrations.
3. **Cloud database verification:** run the new embedded discovery/count regression
   against disposable migrated Supabase, with both client permission states.
4. **Privacy decisions:** verify AI-sharing disclosure/permission and retention of
   feedback/crash copies in external processors. The current deletion path does not
   implement deletion APIs for Notion, Cursor, or PostHog. Technical drafts must not
   be mistaken for completed processor-retention or App Store account settings.

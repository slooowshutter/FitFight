# App Store refresh: 15 September 2026

[Open the gallery](index.html).

## Prepared assets

- Six English screenshots in `en-US/` and six French screenshots in `fr-FR/`.
- Each screenshot is a 1320 x 2868 JPEG from the running iPhone 17 Pro Max simulator.
- The screens are Fights, a live fight, creation, an invitation, You, and the feed.
- `AppIcon.png` is a byte-for-byte copy of `FitFight/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, the current beige FF on green icon. The source asset already contained this icon.

The captures use the native views and existing Companion sample data at workspace
commit `6a28a33`, plus the capture-only launch changes in this workspace. These are
sample accounts and fights. Live sign-in, HealthKit synchronization, and production
compatibility were not tested by these captures.

The top label reflects the local capture build, `1.0.0`, build `1`, with production
display configuration. It does not identify the released App Store binary. Capture
again with the final release version/build before submission if those labels change.

## Capture setup and verification

Marc explicitly authorized his Mac and the iOS simulator for this capture session.
Safari was used for App Store Connect and gallery review. Release archives and
uploads continue to use GitHub-hosted macOS under the normal shipping workflow.

The Debug simulator build passed with code signing disabled. The screenshot launch
selector only operates in the existing Debug simulator Companion preview:

| Environment variable | Value |
| --- | --- |
| `SIMCTL_CHILD_FF_COMPANION_PREVIEW` | `1` |
| `SIMCTL_CHILD_FF_SHOOT` | `1` |
| `SIMCTL_CHILD_FF_SHOT` | `fights`, `fight`, `new`, `invitation`, `you`, or `feed` |

Launch with `-AppleLanguages '(en)' -AppleLocale en_US` for English, and
`-AppleLanguages '(fr)' -AppleLocale fr_FR` for French. After the screen settles,
capture with `xcrun simctl io <device-id> screenshot --type=jpeg <output.jpg>`.
The simulator status bar was set to 9:41 with full battery and signal.

Checks passed for all twelve files: dimensions, no alpha channel, version label and
clock present at the top, and no Companion preview controls or preview-only label.
The icon copy matches the bundled PNG. No product UI or marketing version changed.

## Live release evidence

Read-only checks on 15 September 2026:

- App Store Connect shows iOS version `1.0`, Ready for Distribution, selecting build
  `113` of `1.0.0`. Its screenshot controls are disabled in this released version.
- Staging `/api/app-release` admits public/Friends build `190` and review/internal
  build `198`, all `1.0.0`, with enforcement enabled.
- Production `/api/app-release` returns 404. Production `/api/health` returns 200
  with `schema: ready` but without the current `profile_api` readiness marker.
- Staging health includes `profile_api: true`. Privacy and support return 200 in both
  environments. HTTP checks do not prove signed-in flows or every client's contract.
- Supabase confirms persistent `develop` is a separate project from production.
  Branch metadata reports `MIGRATIONS_FAILED` for `develop`, with an old 27 August
  timestamp, despite its healthy project and API responses. Reconcile the migration
  ledger and integration logs before promotion; this metadata alone does not prove
  a current database outage. Hosted row counts and account conflicts were not audited.

## Recommended next release

Use `1.1.0` for the accumulated feature update. Continue increasing build numbers
while testing that version. Each subsequent public binary update needs another
App Store version and review, for example `1.1.1` for fixes and `1.2.0` for features.
An icon change after publication also requires a new uploaded version and review.
English and French screenshots belong in their respective listing localizations.
See Apple's [version rules](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version/),
[icon rules](https://developer.apple.com/help/app-store-connect/manage-app-information/add-an-app-icon/),
and [localized screenshot rules](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/).

Prepare the release in this order:

1. Compare the release scope with public build 113 and staging builds 190/198. Preserve
   their API contracts and any legacy direct access until a separately verified cutoff.
2. Audit both databases, identity collisions, schema history, and uploaded files;
   take restorable backups and rehearse the transfer in a disposable cloud database.
3. Prepare compatible schema/backend changes and the release version, matching
   changelog, and CI `FITFIGHT_RELEASE_VERSION`. Git promotion follows the normal
   explicitly authorized `develop` -> `preview` -> `main` sequence. Deploy additive
   production schema support and the compatible backend before distributing the app.
4. Transfer real beta identities and their linked profiles, fights, memberships,
   scores, posts, feedback, and media with verified identity mapping. Preserve
   existing production accounts and records. Treat encrypted Apple credentials,
   notification tokens, sessions, and queued jobs individually; do not blindly
   restore staging operational state into production. Plan a final write cutoff or
   reconciliation so ongoing beta activity is not lost after the initial copy.
5. Verify production sign-in, existing and new-client contracts, Health sync,
   standings, media, account deletion, notifications, and privacy/support. The
   production release endpoint must admit the candidate before Apple reviews it.
6. Build the production candidate in CI, attach the final English/French screenshots
   and updated review information, select that production build, and submit to Apple.

Code promotion does not transfer user data. Supabase supports
[Auth user migration](https://supabase.com/docs/guides/troubleshooting/migrating-auth-users-between-projects),
but cross-project identity mapping and a fresh sign-in must be tested for FitFight.
[Storage files need a separate transfer](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore).
No live database, deployment, listing assets, or release configuration changed in
this session, and no new version was submitted.

## Accounts afterward

Keep production as the permanent home for real users and history. Keep staging for
development and testing. Under the current configuration, the same Apple ID signs
into separate Supabase accounts in the App Store app and staging TestFlight.
Migrating once does not keep those environments synchronized.

For convenient everyday use, Marc and friends can use the production App Store app;
use staging TestFlight for testing. A future production-connected TestFlight
candidate can share production accounts, but this would be a deliberate change to
the current rule that every TestFlight uses staging, and its actions would affect
real production data. It has not been configured here.

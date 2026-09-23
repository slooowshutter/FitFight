# Backend

Production scoring Metric is **Steps**. The native app sends Apple's merged
Fight-window totals and checkpoints through the existing `/api/v1/healthkit/steps`
contract. The prepared activity pipeline also accepts merged daily totals,
workout summaries, and explicit workout deletion IDs through
`/api/v1/healthkit/activity`. Individual HealthKit samples stay on the phone.
The backend saves incoming records, resolves current measurements, and publishes
Fight standings and compatible older-client mirrors. There are no app-facing
Postgres RPCs.

[`system-design.md`](system-design.md) is the golden guide. This folder is the first slice of it, not the whole thing. Do not add Active Minutes, Workout Count, WHOOP, Strava, payments, or a website until the backlog says so. Fight posts and photo uploads go through the API below.

Hosted production (no secrets): https://pvqntpteehdvhqyctwum.supabase.co  
Hosted staging / git `develop` (no secrets): https://zstzbfocunthczzubggz.supabase.co

## Activity pipeline (prepared 23 Sep 2026)

This branch adds `private.activity_raw` for durable received totals, workout
summaries, and deletion events, then `private.activity_metrics` for current
measurements with scope, value, unit, interval, source, input IDs, and resolver
version. Neither table is exposed to mobile database clients. Exact retries reuse
one raw row; new readings replace current metrics. A workout tombstone wins over
a stale replay. Workout counts, duration, and walk/run workout distance are
derived from effective workout records and never added to Apple-merged daily
Steps, energy, or distance.

The existing Steps endpoint keeps its request and decoded response shape for
installed clients. It now validates and stores Fight readings, merged days, and
any older-client activity extras as raw rows. The new activity endpoint accepts
at most 1,000 daily totals, 200 workout summaries, and 500 deletion UUIDs per
page. Its `received` count acknowledges durable intake; `processing` reports
`processed` or `pending`. Each request attempts bounded resolution. The
close-fights worker resumes pending, failed, or expired-lease rows. Profile
statistics read correctable `activity_metrics` day rows. Fight charts and
standings use the published Fight revision; finalized outcomes remain frozen.
`metric_days` and `step_days` remain as legacy mirrors. Account deletion removes
both new stores.

Rollout order after authorization: apply the additive migration and backfill,
deploy the compatible backend, then distribute the native build. Old backend
instances may keep writing legacy daily rows during rollout; those reach the new
profile projection on the next user sync. Keep `/api/v1`, old tables, and client
permissions through the supported-build overlap. This branch has no live deploy.

## Application database boundary

**13 Sep 2026:** staging reports `profile_api: true`; cloud native/API/database checks
passed. Production's health response lacks that marker and its release-policy endpoint
returns 404. The direct-client permission cutoff remains a separate rollout, and this
audit did not verify hosted grants or signed-in devices. See the
[dated deployment evidence](status.md#api-and-update-rollout-verified-13-sep-2026).
Every API/schema edit must follow [API compatibility](shipping.md#api-compatibility-for-every-change).

The native app uses Supabase directly for Auth and private Realtime invalidations. All application database reads
and writes use the authenticated FitFight API. `GET /api/v1/me` returns
`user_id`, `handle`, `display_name`, nullable `handle_set_at`, `referral_code`,
and nullable `avatar` (the shared media object).
`PATCH /api/v1/me` accepts a handle, display name, `avatar_media_id`, or any mix;
omitted fields stay unchanged. `POST /api/v1/media` mints a private signed upload
for a photo or short video; `POST /api/v1/media/{id}/commit` verifies size and checksum.
`GET /api/v1/feed` lists fight-audience posts from fights the caller is in. `GET /api/v1/feed?scope=all`
is the older one Feed (Main and fight posts). `GET /api/v1/feed?scope=main`
is Main-only. `POST /api/v1/feed/posts` creates one copy per selected destination
(Main still accepted for old clients; current compose sends fights only) and applies tags only where that person can already see the copy.
`GET /api/v1/feed/people` lists tag candidates. `GET/POST /api/v1/fights/{id}/posts`
remain the single-fight list and the old one-fight compose. Comments, reactions,
delete, and report for any post use `/api/v1/posts/{id}/...`.
Listing a fight includes posts from other windows in the same recurring series.
Roster members (`accepted` or `deferred`) can read and post. Invited-only
members cannot. Delete own posts; report or hide another author.
`GET/PATCH /api/v1/notifications/preferences` reads and updates per-type
toggles (fight posts, comments, replies, reactions, challenge reminders, daily
status). Missing rows default on. Creating a fight post notifies other members
of that fight; a comment notifies the post author; a reply notifies the parent
commenter, not sibling commenters; a reaction notifies the post author. The closer
still drains APNs. Lock-screen copy names the person and does not include Steps.
The verified session owns the operation. TypeScript normalizes and validates handles,
sets their timestamp, and translates uniqueness conflicts to `409 handle_taken`.
Missing/deleted profiles return `401 profile_missing`; account deletion remains `DELETE`.

The Fight snapshot assumes `fitfight_backend_reader`, a restricted no-login role with
no RLS bypass or client write privileges. Only the server's `postgres` connection can
assume it. Verified user claims and the existing SELECT policies preserve row visibility.
Self-profile operations use explicit fields and owner filters through the server admin
client. Response schemas and shared Swift/TypeScript fixtures define the API independently
of table layout; extra database columns never automatically become API fields.

First apply `20260909132922_backend_profile_reads.sql`, then deploy the backend and verify
`/api/health` reports `profile_api: true`, then distribute the native build. Both
distribution workflows require this readiness marker. Existing client grants remain
through this stage. The separate cutoff in [`supabase/deferred-migrations`](../supabase/deferred-migrations/README.md)
must stay outside automatic migrations until the compatible build is installable and
required, all admitted review builds are compatible, and old backend instances have drained.
The cutoff includes column grants and global/per-schema future-object defaults. Keep the
server Data API and Auth/signup working; do not globally disable the Data API.

Internal database changes can ship independently of Apple when the supported API and
running backend versions remain compatible. Dropping or renaming a column requires a
safe backend migration, not automatically an iOS release. Removing information or API
behavior an admitted app still requires waits for that app to be retired. Destructive
SQL and hosted deployment still follow Marc's authorization rules.

## Standard row columns

The prepared `20260919131732_standard_row_columns.sql` migration adds missing
`id`, `created_at`, and `updated_at` columns to all 60 FitFight-owned tables in
`public` and `private`. Auth, Storage, Realtime, and extension-owned tables are
outside this convention. New tables must follow it; the schema test checks it.

`profiles.id` is an indexed, stored generated copy of the unique `user_id`.
Profile queries read/filter/join on `id`; v1 still serializes
`user_id`, including identities embedded in Fight, Feed, and shared-profile
responses. Native models, request paths, and response fixtures do not change.
Legacy signup, old backend instances, RLS, foreign keys, and direct Supabase
clients continue using `user_id`. Its removal is deferred to a separate rollout.
The other existing single-row UUID identities also receive generated aliases;
tables with compound identities receive a generated UUID default. Existing
primary, foreign, and uniqueness constraints remain unchanged, including the
keys used by `ON CONFLICT`. Generated aliases use non-unique lookup indexes:
their source keys already guarantee uniqueness, and redundant unique indexes
can break concurrent legacy `ON CONFLICT` writes. No new API version or native
release is required.

New timestamps default to `now()`. Existing timestamps keep their semantics.
The update trigger fills `updated_at` when a writer leaves it unchanged and
preserves explicitly changed timestamps from existing writers. It does not
replace domain dates such as `occurred_at`, `received_at`, or `finalized_at`.
Ordinary updates and upserts retain `created_at` unless an existing writer
explicitly changes it, as report refreshes already do.

For historical rows, the migration uses recorded signup, connection, receipt,
join, send, and capture timestamps where available. Sync rows use their last
recorded successful sync for both new timestamps. Otherwise it initializes
`created_at` from the old `updated_at`, or migration time when neither exists.
Those values are estimates or initialization times, not recovered creation
history. Missing `updated_at` uses a recorded last receipt/sync when available,
otherwise migration time. Each new timestamp column documents its expression.
Existing timestamp values are never overwritten by the backfill.

The migration suppresses user-trigger side effects only within its own
transaction, preventing metadata backfills from creating activity, recapturing
companions, or sending Realtime invalidations. Constraints, grants, and RLS stay
in place. A five-second lock timeout aborts the transaction if it cannot acquire
the required table locks. The backfill and new indexes still require a deployment
window appropriate to the environment's row counts.

Apply this additive migration before deploying the changed backend. The new
backend readiness check requires its migration record and profile columns.
Keep the old backend usable during the migration and rollback window. Validate
staging separately from production; the normal authorized branch promotions
still apply. Do not include removal of legacy identifiers or direct-client
permissions in this migration batch.

## Saved companion descriptions (prepared 17 Sep 2026)

`GET /api/v1/me/companions` returns the authenticated user's saved descriptions as
a JSON string array, most recently used first. Apply
`20260917010915_saved_companion_prompts.sql` before deploying this endpoint.
The private library is backfilled from existing custom prompts. An internal capture
trigger keeps it current even when an older backend writes the profile. It is not
an app-facing RPC. The existing `GET/PATCH /api/v1/me` contract remains unchanged,
including a null active prompt for stock animals. Reusing a description still uses
the existing custom-companion PATCH. Libraries are isolated by user and cascade
away when the account is deleted. This stores descriptions, not generated artwork.

## Fight chart consistency (prepared 15 Sep 2026)

Apply `20260915200338_fight_step_checkpoints.sql` before deploying this backend.
`GET /api/v1/provider-uploads/context` adds the Fight's `time_zone`. New native
uploads attach optional `step_checkpoints` to each `fight_aggregates` item. Each
point is Apple's cumulative query from the same Fight start, through that Fight
day's end or the current cutoff. The final query supplies both the last point
and the scored total. The server validates complete day coverage, increasing
cutoffs and counts, and an identical final cutoff and total.

Checkpoints live on `private.fight_score_snapshots` with their score revision.
The existing upload transaction saves the score and history together. Snapshot
responses add nullable member `step_checkpoints` from the latest selected-source
revision, only when its value matches the member score. Final history freezes
with the final snapshot. The backend reader has limited SELECT columns and the
existing roster-membership policy; client roles gain no private-table access.

Older requests still work and may produce a latest revision without checkpoints.
New clients then show confirmed totals and an unavailable-history message; they
never fill the gap from legacy `step_days`. Existing daily rows and client grants
are retained for installed builds. An older backend without context `time_zone`
receives the original upload fields from the new app. Distribute the new native
build after the migration and compatible backend deployment. See
[status](status.md#fight-charts-and-standings-prepared-15-sep-2026) for verification.

## Account preferences (prepared 17 Sep 2026)

`GET/PATCH /api/v1/me/preferences` reads and saves the signed-in account's
`language` (`system`, `en`, `fr`) and `appearance` (`system`, `light`, `dark`).
Missing rows follow the iPhone for both settings. PATCH accepts either setting
independently; concurrent changes to different fields are preserved. The
authenticated caller owns the row. Unknown fields and client-supplied account
IDs are rejected.

Apply `20260917024606_account_preferences.sql`, then deploy the backend, then
distribute the native app. Storage is in `private.account_preferences`, with
RLS enabled, no direct client grants, and account-deletion cascading. Existing
profile and notification preference contracts, public tables, and legacy
permissions remain unchanged. No backfill or client permission cutoff is needed.

The app caches confirmed values per account and environment for offline launch,
refreshes on foreground and when opening Preferences, and reports failed saves
without applying them. Language selection uses an explicit localization bundle
for Foundation strings and the SwiftUI locale. Apple documents that the
[Foundation locale parameter](https://developer.apple.com/documentation/swift/string/init(localized:table:bundle:locale:comment:))
formats interpolated values without selecting the translation bundle.
Installation source is read from
StoreKit separately from the configured account environment; it is device
information, not an account preference. Beta and App Store databases do not sync
preferences automatically.

## Friend referrals (pending deployment)

Profiles carry a stable, read-only `referral_code`; there is no link-generation endpoint.
Authenticated `POST /api/v1/referrals` accepts `{ code }` and records the first referrer
in `private.referrals`. Self-referrals and duplicates do nothing. Relationships use
account IDs and cascade on deletion of either account. This counts attributed accounts,
including existing accounts, not clicks or installs. Deploy the referral migration and
backend before the native build. See the install handoff in [`status.md`](status.md).

## Loop

A cloud agent writes SQL in `supabase/migrations` and tests in `supabase/tests`, then opens a PR **into `develop` only when Marc explicitly asks for a PR**. Marc merges that. The persistent Supabase branch `develop` picks it up. TestFlight is a later merge to `preview`. Production only changes when Marc merges `preview` → `main`. Agents do not get the database password or `sb_secret_...` key, and they do not merge unless Marc asked.

GitHub-hosted **Ubuntu** starts disposable Supabase Postgres, Auth, Realtime, and the Data API, lints the schema, runs pgTAP and TypeScript transaction tests, and rejects `DROP TABLE` / `TRUNCATE` / `DROP COLUMN` unless the **first line** of the file is exactly `-- allow-destructive`. The same backend tests run again after applying the deferred client-permission cutoff, including real signed-in Data API denials and signup. Agents do not run this stack on Marc's Mac or a hosted project.

iOS TestFlight is unchanged and still ignores this folder. iOS simulator and screenshot jobs skip when the PR does not touch the app.

## GitHub Integration fields

In the project: **Project Settings → Integrations → GitHub**.

| Field                 | Value                                                         |
| --------------------- | ------------------------------------------------------------- |
| GitHub repository     | `marclelamy/FitFight` (same repo as `slooowshutter/FitFight`) |
| Working directory     | `.`                                                           |
| Deploy to production  | On                                                            |
| Production branch     | `main`                                                        |
| Automatic branching   | On                                                            |
| Branch limit          | `3` (preview branches cost extra; do not raise this)          |
| Supabase changes only | On                                                            |

Then **Enable integration**. Do not paste a secret key, `service_role` key, or database password into GitHub. Those are legacy for this loop. Deploys go through the GitHub app, not a key in Actions.

GitHub branches:

| GitHub branch        | Meaning                    | Hosted database                                |
| -------------------- | -------------------------- | ---------------------------------------------- |
| Feature (`cursor/…`) | One piece of work          | Preview (only if `supabase/` changed, max 3)   |
| `develop`            | Integration / staging site | Persistent Supabase branch named **`develop`** |
| `preview`            | TestFlight cut             | Same persistent `develop` project              |
| `main`               | Production                 | The main project                               |

In **Branching**, create one long-lived branch named **`develop`** (not `staging`). It tracks the GitHub `develop` branch. Feature PRs merge into `develop`. GitHub `preview` only cuts TestFlight binaries; it must not become an extra hosted database. When Marc wants a TestFlight, he merges `develop` → `preview`. When he wants production, he merges `preview` into `main`.

## So an agent cannot nuke production

- Production changes only by merging `preview` into `main`. Agents open PRs into `develop` only when Marc explicitly asks. They do not merge unless Marc said so in that chat.
- CI refuses destructive SQL (`DROP TABLE`, `DROP SCHEMA`, `TRUNCATE`, `DROP COLUMN`) unless Marc approved it and the **first line** of the migration is exactly `-- allow-destructive`.
- Agents never receive `sb_secret_...`, the old `service_role` JWT, or the database password. Never put those in git, chat, or iOS.
- Never run `supabase db reset`, `supabase db push`, or `DROP DATABASE` against the hosted project.
- Prefer additive migrations (expand → migrate → contract).
- Keep the preview branch limit at 3.

Marc’s extra lock (GitHub ruleset **Protect main**): target **`main`, `develop`, and `preview`** → require a pull request, required approvals **0**, require status check **Migrations and RLS**, block force pushes. That stops a push onto those branches without the database check. You still tap merge. You cannot approve your own PR, which is why approvals stay at 0. If the ruleset still lists only `main` and `develop`, add `preview`.

## Commands (disposable cloud CI)

```bash
python3 scripts/forbid-destructive-sql.py
npx supabase@2.115.0 start -x studio,meta,analytics,vector,imgproxy,storage,edge-runtime
npx supabase@2.115.0 db lint --local --schema public,private --fail-on error
npx supabase@2.115.0 test db --local
```

Pin the CLI to **2.115.0** until you mean to bump it (`config.toml` was generated with that version).

The iOS publishable key (`sb_publishable_...`) production fallback lives in `FitFight/SupabaseConfig.swift`. The secret key is not.

Vercel holds `DATABASE_URL`, using Supavisor transaction mode on port `6543`, separately for develop and production. It is a server-only database password and never belongs in GitHub, chat, or iOS. `private` stays absent from the Data API's exposed schemas.

Vercel also holds the server-only Supabase URL and secret used to authenticate requests and perform reviewed admin operations. Neither value belongs in iOS or chat.

`POST /api/v1/feedback` still writes the Bugs & requests post first. Optional
`media_ids` attach up to eight already-uploaded photos, videos, or files (`purpose:
feedback`). Older clients omit the field. After that it
creates a P0 Inbox row in the Blend HQ Product Backlog (Product FitFight, Source
App feedback). Vercel holds `NOTION_TOKEN`. A missing token or a Notion failure
does not fail the in-app post. The token never belongs in iOS, git, or chat.

`GET /api/v1/feedback` accepts optional `kind=feature|bug`, `status=open|archived`,
and `sort=votes|newest|oldest`. Defaults include both types, exclude archived posts,
and sort by votes descending. Date sorting uses creation time. Filters and sorting
apply before the existing 100-post limit. The response includes `can_archive`.
Posts include additive `archived` and nullable `archive_reason` fields.

`GET /api/v1/feedback/{postID}` includes `can_launch_fix`, `can_delete`, and
`can_archive` for the signed-in viewer. Authors can delete their own posts.
The launch and archive flags require the existing FitFight admin allowlist:
confirmed account email `marc@marclamy.com`, username `marc`, or extras in
`FITFIGHT_ADMIN_EMAILS` / `FITFIGHT_ADMIN_HANDLES`. User-editable metadata and
identity email copies never grant admin access.

Author-or-admin `DELETE /api/v1/feedback/{postID}` returns `{ deleted: true }`
and removes the post, comments, votes, reports, and attachment links through
existing foreign keys. An unrelated member receives 403; a missing post returns
404. The app confirms deletion in the existing ellipsis menu on a card or detail.
Older backends omit capabilities, which native decoders default to false.

Admin-only `PATCH /api/v1/feedback/{postID}` accepts `{ archived: boolean,
reason?: string }`, with a trimmed public reason up to 280 characters. It returns
`{ archived, archive_reason }`. Archive retains content, media, votes, and discussion;
reopen clears the reason and permits voting/comments again. Archived vote and comment
commands return the existing `409 conflict` response. Both commands lock the post
in their transaction so they cannot race an archive into accepting a late write.
The migration adds two columns and an index; client grants and RLS remain unchanged.
Apply the migration, deploy and drain the old backend, then distribute the native
archive controls. Existing `/api/v1` paths and legacy response fields remain supported.

Stored media bytes and external Notion copies are
outside this deletion, matching existing post deletion behavior. List, detail,
create, and comment responses keep a `metadata` object for older clients and always
send `{}` so the board never shows device details. List, detail, and create include
`media` with signed URLs. Posts and comments still store the
client snapshot. Admin-only `POST /api/v1/feedback/{postID}/fix-agent` starts a Cursor
cloud agent on `develop` with the post, comments, stored snapshots, attachment URLs, and optional
request `metadata` (plus `X-FitFight-Version` / `X-FitFight-Build` when the body omits
them) via `https://api.cursor.com/v1/agents` and returns `{ agent_id, agent_url }`.
Old clients may still POST `{}`. After a successful start it best-effort moves
the matching Product Backlog row (Notes contain `feedback_post: {id}`) to
Building. When Cursor reports `FINISHED` with a PR URL, the webhook moves the same
row to Done and appends the PR URL. An `ERROR` or a finish without a PR leaves Building.
Vercel holds `CURSOR_API_KEY` and reuses it to sign the webhook when the key is
at least 32 characters. A missing key returns `503 config` to the admin and does
not affect other people. The key never belongs in iOS, git, or chat.

Native Sign in with Apple sends its short-lived authorization code to authenticated
`POST /api/v1/auth/apple`. The server exchanges it with Apple, checks the returned Apple
subject against the User's Supabase Apple identity, encrypts the refresh token, and stores
it in `private.apple_sign_in_tokens`. Vercel holds the Sign in with Apple Team ID, key ID,
private `.p8`, client ID, and a separate 32-byte encryption key. `DELETE /api/v1/me`
loads any revocation token, removes pending private Storage objects, deletes Fights owned by
the User, removes the User from other Fights, and hard-deletes the full auth account before
making a bounded Apple revocation request. Apple cannot block FitFight deletion. Legacy
accounts without a stored Apple token still delete; the app gives the manual Apple Settings
disconnect path.

`GET /api/v1/provider-uploads/context` temporarily remains the context route and returns the server time plus exact live/awaiting-final-sync Fight windows. `POST /api/v1/healthkit/steps` accepts one strict JSON document with `complete_through`, the User's `time_zone`, `merged_days`, and `fight_aggregates`. `fight_aggregates` are Apple's merged cumulative totals from each server-authoritative `starts_at...cutoff_at` interval and are the only input to standings. `merged_days` are limited to relevant active Fight days and serve charts only. The request contains no raw sample, deletion, per-source statistic, device/source metadata, anchor, NDJSON, object path, or upload capability.

`POST /api/v1/healthkit/diagnostics` retains the latest private operational snapshot and accepts an optional batch of completed timing attempts. Old native payloads that omit empty timestamp/error fields remain accepted. Attempts contain a random trace ID, trigger, outcome, elapsed stage timings, app version/build, optional counts/encoded payload size, and optional stage errors with a fixed kind and numeric system code or HTTP status. They contain no Steps values, Fight IDs, device identifier, free-form errors, or raw HealthKit data. `private.healthkit_sync_attempts` is inaccessible to app clients and Fight peers and cascades on account deletion. Reports keep at most the newest 100 attempts per User; that User's rows older than seven days are pruned on their next report. An inactive account's older rows can remain until then or account deletion.

Fight peers can read only `fight_members.final_steps_complete`, which indicates an available snapshot from that member's selected source at the exact Fight end. A source-wide watermark alone cannot establish this. It describes query coverage, not a guarantee that Apple has received all delayed device data.

The older one-object archive migrations, `private.provider_uploads` / `private.provider_events` tables, `provider-inbox` bucket, archive contract, and provider-upload create/status/process routes remain legacy infrastructure during the additive rollout so older builds and migration history are not rewritten. The aggregate-only sync does not create new archive rows or Storage objects and does not use TUS. Remove that legacy surface separately only after incompatible TestFlight builds no longer need it.

Every TestFlight binary talks to the develop project. The workflow runs on push to `preview`, or manual `workflow_dispatch` on that branch, and rejects `main` and `develop`. CI writes `FitFight/Generated/BuildEnv.swift` before archive. GitHub variables `SUPABASE_STAGING_*` override if set; otherwise the known develop URL and publishable key are compiled in. Production configuration belongs only to the future App Store flow. See [`shipping.md`](shipping.md). What is live on the phone: [`status.md`](status.md).

## Security and finalization boundary (5 Sep 2026)

`POST /api/v1/fights/{fightID}/decline` requires an invited membership belonging to
the signed-in User. It locks the Fight and membership, declines it, and revokes its
invitations in one transaction. Repeating a successful decline is harmless.

`PATCH /api/v1/fights/{fightID}` is owner-only. It can change title, loser action,
private/public, whether the series repeats, the end time (and the start only while the
fight is still `scheduled`), extra usernames, and kicking anyone except the owner.
`draft`, `inviting`, `scheduled`, and `live` fights can be edited; `awaiting_final_sync`,
`final`, and `cancelled` stay frozen. Old apps never call this route.

`POST /api/v1/fights/{fightID}/cancel` is owner-only. The app’s Edit summary Delete
uses it. It pauses the series first, then marks the fight `cancelled`, so a repeating
fight does not mint the next window. A failed pause leaves the fight live so the owner
can retry from Edit. A retry on an already-cancelled fight still pauses. `final` fights
stay frozen. Old apps never called this from the Edit screen.

Recalculation locks the Fight, then accepted memberships, before reading the latest
selected-source exact-window snapshots. It freezes scores, completeness, selected
snapshots (`is_final`), and Fight state in the same transaction. It never substitutes
raw observations or daily chart totals. The existing policy remains: finalize when
every accepted participant has an end-cutoff snapshot, or after the 24-hour grace
period with missing data marked incomplete. The choice of a full 24-hour provisional
period remains a product decision; Apple provides no historical immutability deadline.

The snapshot fingerprint includes the read's `complete_through` timestamp. Replaying
the same reading is idempotent, but a later reading that returns to an earlier total
creates a new snapshot and can become the latest correction at the same Fight end.

## Feed activity and notification destinations (prepared 16 Sep 2026)

`GET /api/v1/posts/{postID}` resolves a single post with the existing `{ post }`
contract, independently of feed pagination. It checks current membership, recurring
series/channel access, blocks in either direction, and author deletion. Social
pushes keep `/fights/{fightID}` as their path and add `?post={postID}`, plus
`&comment={commentID}` for comments and replies. Released clients that discard the
query still open the Fight. The new client persists the query across a cold launch,
handles taps while already foregrounded, and opens a dedicated post screen. Targeted
comments load through their page before the screen scrolls to them.

`GET /api/v1/feed/activity` supplies You -> Activity. It returns `{ events,
next_cursor }`, with a default page size of 40 and maximum of 80. The cursor preserves
microsecond timestamps and an event ID; unknown historical timestamps sort last.
Post and comment pagination also preserves microseconds so equal timestamps do
not repeat or skip rows while resolving a notification. Existing opaque cursors
remain accepted, using the anchor row's exact timestamp when it still exists.
Events include available posts, comments, replies, reactions, and membership state
history in the viewer's current Fights. An invited viewer sees only their own
membership history until joining. Current access, deleted authors, and blocks are
rechecked on every page. This is product activity, independent of push permissions
and delivery; deleting a post also removes its comments/reactions from this list.

The additive `20260916210740_feed_activity_updates.sql` migration records membership
state transitions in a private, RLS-protected audit table. Clients have no table or
function access. The internal trigger records state transitions, never scores or
HealthKit data, and does not implement membership decisions. Existing acceptance
times are backfilled from `accepted_at`. Historical invitations have no recorded
timestamp and display **Time not recorded**. Future transitions use the committed
write's timestamp. Account/Fight deletion cascades to this history.

The same migration broadcasts empty `feed_changed` invalidations on the existing
private per-user topic for posts, comments, reactions, channels, membership events,
and blocks. App-wide posts invalidate every active profile's private topic,
including viewers with no shared Fight. Post edits, comments, reactions, and
deletions use the same recipients. These commit with the write. The native listener
handles this event separately from standings, coalesces bursts, and reconciles on subscription,
reconnection and foreground entry. Visible root/Fight feeds, post detail, and
Activity refetch through the API. Loaded threads refresh even after their first
comment, and queue another read when an event arrives during a request. A completed
local write cannot be overwritten by an older comment response. An automatic
refresh reads through the previously loaded comment IDs, including confirmed
local comments outside the first ranked page, before replacing the thread.
Deleted comments disappear after that read; a failed later page retains the
complete previous thread and cursor. Changing the sort starts a new first page.

The native root feed and Fight feed request `limit=10` using the existing page
contract. Initial load and pull-to-refresh fetch one page. Pull-to-refresh directly
awaits the feed request; it no longer waits for a HealthKit/Fight sync first.
The API already returns `Cache-Control: no-store`. A lazy list loads the next page
when its footer approaches the viewport, appending unique IDs without reordering
existing cards or refreshing their threads. Pagination failures retain the cursor
and show a retry at the bottom.

Live events refresh currently displayed cards through the single-post endpoint,
preserving their order and the older-page cursor. Offscreen cards are marked stale
and refreshed when they reappear. New posts enter on initial load or pull-to-refresh.
Events received during a page request also invalidate cards in the arriving page.
Pagination queues reconciliation for any visible stale cards, including a live
read that began before pagination. A manual refresh supersedes older page
responses. Older clients still use the existing server default of 30; no response
fields or API versions change for pagination.

Deploy the additive migration and compatible backend before distributing the
native build. `/api/v1`, old response fields, direct-client grants, and existing
notification preferences are unchanged. Cloud checks and live rollout status are
recorded separately in [status.md](status.md).

## Live standings (prepared 15 Sep 2026)

A foreground, signed-in app subscribes to one private topic,
`fitfight:fights:<user UUID>`, for `fights_changed` broadcasts with no app payload.
Supabase adds its own random message ID. The topic's
receive policy requires that exact authenticated User. Clients have no publish
policy. Statement triggers on Fight memberships and Fight updates notify the
current roster, owner, and changed members, including removals. No scores,
HealthKit records, or Fight IDs travel over the socket. The API rechecks current
access whenever a notification arrives.

`POST /api/v1/fights/snapshot` takes the same `{ "time_zone": "Europe/Paris" }`
request and returns the same `{ fights, members, profiles, series, step_days }`
contract as `/fights/refresh`, with no maintenance or HealthKit work. It uses the
same authenticated, read-only query and sends `Cache-Control: no-store`. Existing
`/fights/refresh` clients keep their maintenance and response contract.

Trigger inserts into `realtime.messages` commit with the score transaction; rolled
back changes publish nothing. `realtime.send` can warn and skip publication on an
internal failure, so this is best-effort invalidation. The app also refetches on
subscription/reconnection, replication readiness, and foreground entry. It coalesces bursts, queues an
extra read for events received during a fetch, and rejects superseded requests or
responses from a previous account. Backgrounding and sign-out remove the channel.
SDK Auth refresh continues to update the channel's credentials. The readiness
refresh follows the [Realtime system-event protocol](https://supabase.com/docs/guides/realtime/protocol).

Standings are replaced together from confirmed API snapshots. Reading fresh local
HealthKit totals no longer edits the viewer's score or rank before the upload is
accepted. Failed reads retain the previous confirmed snapshot.

Roll out the additive `20260915193015_broadcast_fight_changes.sql` migration and
read-only backend endpoint before distributing the native build. No old columns,
API fields, or direct-client grants are removed. Live deployment and device
verification are recorded separately in [status.md](status.md).

## Request performance and timing (5 Sep 2026)

`POST /api/v1/fights/refresh` accepts `{ "time_zone": "Europe/Paris" }`, performs the User's due maintenance, and returns `{ fights, members, profiles, series, step_days }` together. The snapshot uses one data query inside a read-only transaction with `SET LOCAL ROLE fitfight_backend_reader` and transaction-local claims for the verified User. Existing RLS governs every returned row, including invited/declined membership limits and day-specific peer Steps access. Role and claims reset on commit or rollback before the pooled connection is reused. Maintenance checks the User's memberships and due recurring series in one query; ordinary refreshes no longer scan every account's series through REST. Separate due Fights are still finalized sequentially, and recurring creation retains its existing roster-copy logic.

An aggregate upload uses at most eight SQL statements, excluding BEGIN/COMMIT, independent of Fight/member count. Finalizing one Fight uses at most six. TypeScript still owns scoring; batched writes preserve the existing transaction and lock boundaries. Snapshot inserts remain separate from reads of the latest snapshot, preserving corrections that return to an earlier total.

Each foreground/manual refresh and observer opportunity owns a trace. Native `ContinuousClock` measures permission prompts separately, today's HealthKit read, context retrieval, merged-day and each exact-window HealthKit query, upload, and final Fights refresh. The total ends after the final requested app work and mapping/cache updates. Observers omit the screen refresh they do not perform; expiry records a cancelled attempt once. Routine token retrieval uses the SDK's valid session accessor; account deletion still explicitly renews its session.

The native API sends `X-FitFight-Trace-ID` for context, upload, and Fights refresh. Their responses include `Server-Timing` for `auth`, `db`, optional `maintenance`, and `total`, including failures. Structured `fitfight_request` Vercel logs contain the same trace ID, fixed operation name, status and durations only. Server `db` includes pool acquisition, locks, and the whole database operation; it is not an isolated query execution time. Server `total` starts at handler entry and excludes earlier cold-start time. Compare each stage's client duration with its server timing; never subtract phone and server wall-clock timestamps.

One immutable completed attempt is logged locally under OSLog category `HealthKitPerformance` and sent through the existing diagnostics endpoint after product work completes. Reporting is best effort and is excluded from the attempt's own duration, avoiding recursive timing reports. Network loss, suspension, or termination can prevent server delivery; there is no background retry queue. The underlying HealthKit callback may still finish after observer expiry, but cancellation prevents a subsequent upload from that expired attempt.

Failed stages preserve HealthKit/URL/Cocoa numeric errors, HTTP status, decoding/configuration failures, and the app's unavailable/invalid Steps errors. Unknown error domains are reduced to `unknown`; messages, URLs, query predicates and `NSError.userInfo` are never logged. The existing `stages` JSON stores these details without another migration. After authentication and validation, the diagnostics route emits `fitfight_healthkit_failure` to Vercel logs before database persistence, with trace ID, app version/build, trigger, outcome and failed stages. Legacy reports such as build 153 emit their coarse error only; discarded device errors cannot be recovered retroactively.

You → Apple Health retains a per-account error reference containing the trace ID's first eight characters, stage and safe error code, including when diagnostic delivery fails. Match that prefix against `fitfight_healthkit_failure` and the full trace ID against `fitfight_request`. Delivery failures also log locally under `HealthKitDiagnostics`; the next successful Steps sync clears the phone's reference. Deploy this expanded diagnostics schema before distributing the native build.

Apply `20260905090813_healthkit_sync_timing_history.sql`, deploy the backend, then distribute the native build. The new app requires the refresh endpoint. Legacy diagnostics remain compatible after migration/backend deployment. This change has not been deployed from the workspace.

An absent HealthKit sum is unavailable, not a measured zero. The current native batch
stops without overwriting saved data if any Fight window has no accessible sum. Daily
buckets without a quantity are omitted. A future per-Fight availability contract can
allow unaffected windows to progress without manufacturing complete zero results.

Deploy the API (including Decline) before the server-owned-write migration, and use
the new TestFlight build. Older builds that directly accept or decline through
Supabase will receive a permission error after the migration. Feature-branch pushes
alone do not apply the hosted migration. No existing finalized scores or hosted
previously-deleted accounts are rewritten by this change.

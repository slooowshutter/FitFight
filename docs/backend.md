# Backend

Production scoring Metric is **Steps**. The native app sends Apple's merged
Fight-window totals and checkpoints through the existing `/api/v1/healthkit/steps`
contract. The prepared activity pipeline also accepts merged daily totals,
workout summaries, and explicit workout deletion IDs through
`/api/v1/healthkit/activity`. Individual HealthKit samples enter the private raw store.
The backend saves incoming records, resolves current measurements, and publishes
Fight standings and compatible older-client mirrors. There are no app-facing
Postgres RPCs.

[`system-design.md`](system-design.md) is the golden guide. This folder is the first slice of it, not the whole thing. Do not add Active Minutes, Workout Count, Strava, payments, or a website until the backlog says so. The WHOOP connection (raw data pull, see [WHOOP connection](#whoop-connection-prepared-18-oct-2026)) was approved on 18 Oct 2026; WHOOP-based Fights and other WHOOP UI still wait for the backlog. Fight posts and photo uploads go through the API below.

Hosted production (no secrets): https://pvqntpteehdvhqyctwum.supabase.co  
Hosted staging / git `develop` (no secrets): https://zstzbfocunthczzubggz.supabase.co

## Environment and Beta bar (prepared 29 Sep 2026)

Public `GET /api/v1/environment` returns `{ "environment": "beta" }` or
`{ "environment": "production" }` from `private.environments`. The table has one
row per Supabase project: `zstzbfocunthczzubggz` (develop) is `beta` and
`pvqntpteehdvhqyctwum` (production) is `production`. The migration writes both
rows into every database, and the route reads the row for the project in
`NEXT_PUBLIC_SUPABASE_URL`, so develop and main answer differently without a
dashboard step. A project with no row returns `503 config`; a new Supabase
project needs its row added by migration.

The app shows its environment strip only from this answer, never from its build
settings: everyone sees it on `beta`, and the admin also sees it on `production`.
It caches the last answer per API address and keeps it when the call fails.

## Admin dashboard (prepared 29 Sep 2026)

`GET /api/v1/admin/dashboard?section=<section>&days=<1-3650>[&bucket=day|week|month]` feeds the Admin tab
in Profile -> Dashboard. Sections: `overview`, `retention`, `churn`, `users`, `engagement`,
`steps`, `fights`, `social`, `app`. Everything is plain SQL on Postgres, computed on each
request; there is no warehouse, rollup table or cron. Each card and chart is one
query in `web/lib/supabase/queries/admin-dashboard-supabase-query.ts`: add a
chart by adding one definition, delete one by removing it. Every payload also
lists the sections (`sections`: id and title in chip order) and the app draws its
chips from that list, so section, card and chart changes need no app release
(builds from 30 Sep 2026 on; earlier builds have a fixed chip list). A failing
query only marks its own tile with `Query failed: ...`.

- **Windows (10 Oct 2026):** cards have fixed spans named in their titles, so the
  app's period never changes them. "Weekly" is the last 7 days against the 7
  before, "Monthly" the last 30 against the 30 before (rolling for events,
  complete Paris days for Steps); a card without either word is now against 7
  days ago. `days` sets only the charts over time (`x_kind` date): Paris days from
  the later of today minus `days` and the first signup, at least 7 days, in whole
  days (up to 62), weeks (up to 366) or months, with no previous-period overlay.
  `bucket` (the app's Day, Week or Month choice) overrides that bucket. Each metric
  is computed per bucket: counts add up, people count once per bucket, averages
  and shares use every person-day in it, and DAU is the daily average. Activity
  charts leave out buckets that start before 2 Oct 2026 (see App opens). Every
  other chart names its own span ("last 30 days", "all time", "now").
- **Chart pages (10 Oct 2026):** every chart carries a `definition` (what it
  measures) and an `example` sentence that reads one current number off it: the
  newest complete day, week or month, or now for totals and states. Both are built
  on the server in English, so their wording changes need no app build.
- **Card pages (11 Oct 2026):** every card also carries a `definition` (what it
  measures and what it compares with) and an `example` sentence that reads its
  number and the previous one. A card without a value has no example. The app
  shows only the name, number and change on a card, and the rest on its page. A
  null `previous` (no history for the earlier span) shows no change and no
  Previous line; a `previous` of 0 shows the change as "+3 from 0". Cards round
  down with one decimal under 10 (2.68 shows 2.6), whole numbers to 999, then
  1.5K; app builds from 15 Oct 2026.
- **App opens (15 Oct 2026):** `private.healthkit_sync_attempts` rows with
  trigger `foreground` that read Apple Health: a stage other than `session`,
  `fights_refresh`, `healthkit_activity` and `activity_upload`, or that only
  refreshed Fights (people without Apple Health); `manual` pulls to refresh
  also count as activity. Not opens: the activity import a sync
  starts (activity stages only; it copies the sync's trigger), the Fights
  refresh after a background `observer` sync (refresh stages only, within 60
  seconds after it), and background relaunches that builds without the launch
  guard (1.1.2 (210) and the 1.1.3 in review) record as `foreground`: today's
  total failed with HealthKit error 6 (phone locked), or the trace starts 59.5
  to 66 minutes after the person's previous Health sync (hourly background
  delivery, which iOS can deliver late but not early). In the week to 15 Oct
  that drops about 550 relaunches and about 25 real opens; about 150 later
  relaunches a week still count, so opens from those builds read slightly high.
  Delete the hour rule once every installed build has the launch guard. An open
  while a background sync runs counts; before 15 Oct it was dropped with the
  post-sync refresh. The refresh after an action in the app, such as create,
  join, edit or leave a Fight, sends `manual` since the 12 Oct 2026 change;
  older builds send it as `foreground` with refresh stages only, so it counts
  when no background sync came just before. App opens are complete from 2 Oct
  2026: production deleted sync reports past 7 days or 100 per person until 1
  Oct, and builds before 1.1.1 (202) sent none. Activity comparisons whose
  previous period starts earlier stay empty, activity chart buckets that start
  earlier are left out (WAU starts on 8 Oct and MAU on 31 Oct), and stickiness
  and active days read the complete Paris days since 2 Oct until 1 Nov.
- **App syncs (15 Oct 2026):** the App tab counts a Steps sync only when its
  trace read Steps (a `local_state` or `today_total` stage). Build 210 reports
  every HealthKit observer wake, and most only join a sync already running and
  record no stage (65,542 of 71,510 background rows in the week to 15 Oct); the
  other-activity import and Fights-only refreshes write their own traces. The
  rule reads stages, so it holds for every build and for history. Sync errors by
  code shows failed syncs only, with Other activity as its own bars. Sync time
  leaves out cancelled syncs and syncs over 2 minutes, because `total_ms` is
  wall-clock time and includes iOS pausing the app. Steps sync failing now reads
  each person's latest Steps sync, not the diagnostics error, which the
  other-activity import also sets. Push tiles count registered devices: the app
  registers only after permission is granted and never reports a later denial.
  Server error tiles count the HTTP 5xx rows in `private.server_error_logs`,
  which receives rows only from the 15 Oct 2026 logging fix on; errors by route
  group by method and route template.
- **Churn (14 Oct 2026):** a person churned when they were active in the 7 (or
  30) complete Paris days before the latest 7 (or 30) and not active in the
  latest. Two meanings of active: an app open (as above), or a phone sync, which
  is a complete Apple Health step day as in Retention. Charts read the same
  windows at the end of each bucket. Churn by app opens reads only periods from
  2 Oct 2026, because production pruned sync reports until 1 Oct and kept the
  last reports of people who left; weekly numbers show from 16 Oct, monthly from
  1 Dec. A returning phone uploads the days it missed, so older sync churn drops
  when people come back.
- **Steps (15 Oct 2026):** complete Apple Health days only: a complete row beats
  a newer incomplete one (profile statistics take the newest row), then the
  newest row, `activity_metrics` over legacy `metric_days`, then the Fight
  fallback below, counted from each person's signup day. A day with no complete
  daily row falls back to the person's Fight uploads: the difference between two
  consecutive daily `step_checkpoints` of their newest
  `private.fight_score_snapshots` row per Fight, whole Fight days only, highest
  across Fights. That covers 1.1.2 (210) phones that connected Health before 16
  Sep 2026: their daily Steps upload fails with HealthKit error 5 (authorization
  not determined for activity types they were never asked for) while Fight
  totals still upload. The day follows the Fight's time zone, and checkpoints
  reflect when steps reached the server, so single days can differ from the
  phone's daily total (more than 10% on about a quarter of the days that have
  both, even in the same zone); over 834 days that have both, totals and 10K-day
  counts agree within 1%. In the week to 15 Oct the fallback supplied about 887K
  of the 2.78M weekly steps (13 people). 1.1.3 uploads Steps only and imports
  the missing days itself, and real rows win. The fallback is read-only: nothing
  is written to `activity_metrics`, which founder-Fight scores read. "Health
  history" cards include imported days before signup.
- **Steps comparisons (15 Oct 2026):** fight-day lift is the median person's own
  Fight days against their own other days (3+ of each, at least 5 people, else no
  number). A day is a Fight day from the person's acceptance, in a Fight with
  another accepted member, never the app-wide or suggested Fight; a founder
  Fight counts for its challenger only. Change after joining reads only people
  who signed up more than 4 weeks ago, with 20+ days on each side, and leaves the
  signup day out. Steps around signup follows the same people on both sides (7+
  days each) and hides days under 20 people. People by daily average needs 7+
  days in the 30.
- **Speed:** a tab's tiles take turns on the pool's connections (10 for the
  read-only production connection, 3 for the server's own database), and each
  note ends with that tile's own query time (`Took 1.2 s.`). The route reuses a
  running or under-5-minute-old result for the same environment, section and
  period on that server instance, so Refresh can show data up to 5 minutes old.
  A result with a failed tile is not reused.
- **Retention:** follows people whose phone has sent at least one day with Apple
  Health steps; iOS reports a denied Health read as an empty success, so a
  connection that never sent steps is not followed. Someone is retained in
  a week (or 30-day month) counted from their own signup day when their phone
  synced steps that week: background syncs run without an open until the app is
  deleted or Health is turned off. A person counts for a week only once it has
  passed. Charts draw one line per signup week (last 8) and month (last 6).
  Cards take the signups of the latest 28 days (weeks) or 30 days (months) that
  got past that week or month, against the span before. App opens are not used:
  they are complete only from 2 Oct 2026, after most cohorts' first weeks.
- **Social metrics** exclude the app-wide (`PGG7`) and suggested Fights, whose
  invitations are automatic, and founder fights (`fights.host_id`), which every
  new user may start against Marc. Tiles about a person's own progress (fight
  join rate, time to first fight, onboarding by signup, the funnels, users in a
  live fight, churn by fight, fight-day Steps) count a founder fight for its
  challenger but never for the founder. The Production view runs preview's code
  against production, so these filters read `to_jsonb(row) ->> 'host_id'`, which
  works before and after the founder-fight migration; use the column directly
  once production has it.
- **Fights (15 Oct 2026):** a Fight counts once someone besides its owner has
  accepted a round of it (`contests`). Fights nobody joined, such as the 14 solo
  test Fights of 26-28 Aug 2026, drafts and cancelled Fights are left out of
  Fights created, recurring share, fighters per fight, users in a live fight,
  durations, Most fights joined, loser actions and every "joined a fight" step
  (join rate, time to first fight, onboarding by signup, funnels). Users in a
  live fight also leaves out the app-wide and suggested Fights. Live fights and
  Rounds finished count rounds with two or more accepted fighters, the app-wide
  round included. A join is a person's first accepted round of someone else's
  Fight; copying the roster into each new round of a repeating Fight is not a
  join. A repeating Fight counts once in the funnels, Fight sizes, Most fights
  joined and Fights with the most posts. Posts are counted as a Fight's feed
  shows them: posts shared to any of its rounds plus Fight posts made in them.
  Recurring share dates a Fight by its first round, because a backfill stamped
  `fight_series.created_at` on 15 Sep 2026. Invite acceptance counts acceptance
  in any round, and invites have timestamps only from 26 Sep 2026. Cancel rate
  counts every cancelled round, joined or not, against cancelled rounds plus
  contests; so far every cancelled Fight is one nobody joined. Time to first
  fight is in minutes.
- **Users and small groups (15 Oct 2026):** "Connected Apple Health" in
  onboarding, funnels and retention means the phone has sent a day with steps.
  Nothing can see a Health disconnect, so the Overview and App Health cards count
  people whose phone completed a Steps sync in the last 7 days against the 7
  before (Fights-only refreshes and the activity import do not count). Referral
  tiles apply the 7-day new-account rule to rows written before it shipped and
  date each referral by the signup. Small groups are hidden rather than compared:
  retention cards need 10 people (the comparison needs both groups), churn chart
  points 10, onboarding and retention-by-signup points 5 signups, and user growth
  a base of 20 users. The time zone chart leaves out people without a saved zone.
- **Access:** only the FitFight admin (`isFitFightAdmin`: username `marc` or `rad`, or the
  admin email). The app always sends `X-FitFight-Auth-Project` with its own
  Supabase project ref. When it names the other FitFight project, the backend
  verifies the token with that project's public Auth endpoint and accepts it only
  if the same Apple or Google identity (`auth.identities` provider and subject)
  owns an admin profile here. The preview server therefore also accepts an App
  Store build's production login. This is a read-only exception to environment
  isolation; tokens are never exchanged or stored.
- **Production data:** both of the app's buttons call the preview server
  (`fit-fight-git-preview-blendai.vercel.app`) with `environment=production` or
  `staging`; without the parameter a server reads its own database. The preview
  server reads production through `PRODUCTION_ANALYTICS_DATABASE_URL`, a
  read-only `fitfight_analytics` user (SELECT only, BYPASSRLS, 20 s statement
  timeout, read-only transactions), scoped in Vercel to Preview on branch
  `preview`. A production read requires the admin check on the server's own
  project plus one more proof (`verifyProductionDashboardAdmin`): the account is
  this server's `FITFIGHT_ADMIN_USER_ID` (on Preview, Marc's staging account
  `87434630-dd64-4465-b79b-fd99e35368be`; his production account is
  `854ed9b9-5de9-4d85-b10e-e201deb999de`), or an admin profile in production has
  the same account ID or the same Apple ID in `private.apple_sign_in_tokens`.
  Supabase does not let the analytics user into the `auth` schema, so production
  reads use only `public` and `private`. `createProductionAnalyticsClient` refuses a
  `postgres.` user and any user outside the production project, and answers 503
  while the variable is missing. New charts reach production data with a
  `preview` merge; `main` is not needed.
- **Compatibility:** additive route; no existing contract, schema or migration
  changes. `admin-dashboard.integration.ts` runs every card and chart on the
  migrated disposable database.

## Recent syncs (prepared 12 Oct 2026)

`GET /api/v1/admin/recent-syncs` returns `{ "people": [...] }` with `user_id`,
`handle`, `display_name` and `last_synced_at` for every account whose Apple
Health upload reached this server's database in the last 7 days, newest first.
It reads `public.data_sources.last_success_at` (provider `apple_health`), which
every Steps and activity upload sets, and leaves out deleted accounts. Only the
FitFight admin (`isFitFightAdmin`) can read it; anyone else gets 403. The staging
app shows it to the admin on Fights, through the preview server, to find testers
who still sync to staging instead of using the App Store version.

## Activity pipeline (prepared 23 Sep 2026)

This branch adds `private.activity_raw` for durable received totals, individual
quantity/category samples, workout summaries, and deletion events, then
`private.activity_metrics` for current
measurements with scope, value, unit, interval, source, input IDs, and resolver
version. Neither table is exposed to mobile database clients. Exact retries reuse
one raw row; new readings replace current metrics. A workout or sample tombstone wins over
a stale replay. Each workout has separate duration, active-minutes, distance,
and active-energy measurements when those values exist. Effort remains in the
received record and duration details until its HealthKit unit is identified.
Workout counts, duration, and walk/run workout distance are derived from effective
workout records and never added to Apple-merged daily Steps, energy, or distance.

The existing Steps endpoint keeps its request and decoded response shape for
installed clients. It now validates and stores Fight readings, merged days, and
any older-client activity extras as raw rows. The new activity endpoint accepts
at most 1,000 daily totals, 200 workout summaries, 100 individual samples,
and 500 deletion UUIDs of each kind per page. Its `received` count acknowledges
durable intake; `processing` reports
`processed` or `pending`. A deleted sample's previously stored interval is
returned for merged-day refresh. Each request attempts bounded resolution. The
close-fights worker resumes pending, failed, or expired-lease rows. Profile
statistics read correctable `activity_metrics` day rows. Fight charts and
standings use the published Fight revision; finalized outcomes remain frozen.
`metric_days` and `step_days` remain as legacy mirrors. Account deletion removes
both new stores.

Rollout order after authorization: apply the additive migration and backfill,
deploy the compatible backend, then distribute the native build. Old backend
instances may keep writing legacy daily rows during rollout. The Profile reader
selects the newest row from both stores during this overlap; a later activity
measurement becomes authoritative without waiting for another user sync.
Keep `/api/v1`, old tables, and client permissions through the supported-build
overlap. This branch has no live deploy.

After the migration is deployed, this read-only query follows recent raw
records for handle `marc` to their current measurements. Replace the handle to
inspect another account. Raw rows without a linked measurement are still shown,
including superseded readings and deletions.

```sql
select
    raw.id as raw_id,
    raw.record_kind,
    raw.record_type,
    raw.record_key,
    raw.starts_at,
    raw.ends_at,
    raw.payload,
    metric.scope,
    metric.metric,
    metric.value,
    metric.unit,
    metric.input_ids
from private.activity_raw as raw
left join private.activity_metrics as metric
    on raw.id = any(metric.input_ids)
where raw.user_id = (
    select user_id from public.profiles where handle = 'marc'
)
order by raw.collected_at desc, raw.id, metric.metric
limit 100;
```

## WHOOP connection (prepared 18 Oct 2026)

Marc approved pulling all WHOOP API data on 18 Oct 2026. Fight Steps still come
only from Apple Health. Code only, not deployed: see [status](status.md#whoop-connection-prepared-18-oct-2026).

- **Routes:** `POST /api/v1/whoop/connect` (bearer, empty body) returns
  `{ "url" }`, the WHOOP sign-in page. `GET /api/v1/whoop/connection` returns
  `{ "connected", "last_synced_at", "history_synced_at" }`. `GET /api/whoop/callback`
  is the OAuth redirect: it only forwards WHOOP's code and state to the app at
  `fitfight://whoop?code=...&state=...` (or `?status=denied`). The app posts them with its
  own sign-in to `POST /api/v1/whoop/finish`, which accepts only a state that account
  started, so a sign-in link sent to someone else connects nothing.
  `POST /api/whoop/webhook` takes WHOOP v2 webhooks, HMAC-SHA256 signed with the
  client secret. `GET|POST /api/internal/whoop/sync` is the hourly cron, behind the
  cron secret.
- **Storage:** `private.whoop_connections` holds each account's encrypted WHOOP
  tokens (AES-256-GCM, `WHOOP_TOKEN_ENCRYPTION_KEY`) and sync times. Records are
  stored raw in `private.activity_raw` under a `data_sources` row with provider
  `whoop` and connection_route `oauth`, as `record_type` `whoop_cycle`,
  `whoop_recovery`, `whoop_sleep`, `whoop_workout`, or `whoop_body`. Nothing
  resolves them into `activity_metrics` yet.
- **Sync:** connecting pulls the full WHOOP history (`history_synced_at`). A
  verified webhook syncs that user's recent window from the WHOOP API, and the
  hourly cron syncs every connection. WHOOP rotates the refresh token on every
  refresh, so a refresh happens under a row lock on the connection; two
  concurrent refreshes would spend the same token and lose the connection.
- **Limits:** 100 requests per minute and 10,000 per day for the whole app, not
  per user. The sandbox tier allows up to 10 WHOOP members until WHOOP approves a
  higher tier.
- **WHOOP app:** one app for staging and production. Redirect URLs
  `https://staging.fitfight.app/api/whoop/callback` and
  `https://fitfight.app/api/whoop/callback`; v2 webhooks at `/api/whoop/webhook`
  on both hosts. The client ID is committed in `web/lib/whoop/whoop.ts`;
  `WHOOP_CLIENT_SECRET` and `WHOOP_TOKEN_ENCRYPTION_KEY` are Vercel secrets.
- **Admin:** the admin dashboard's **Metrics** tab lists raw records by source and
  type, cleaned metrics by source, and live WHOOP connections. Which source scores
  Fights is a constant in `admin-dashboard-supabase-query.ts` (Steps from Apple
  Health), never a setting on the page.
- **Retention:** WHOOP data is kept while the account exists, and account
  deletion removes it. A user can ask support to delete their WHOOP data. If
  WHOOP ends our API access, its terms require deleting WHOOP data.

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
`{ "type": "friends" }` sets `fight_posts.to_friends`: the author's accepted friends see the post on `GET /api/v1/feed`
(never in a fight's own list), next to any fight destinations. A friends-only post keeps the Main shape (no fight)
and skips the old shared-fight Main rule. Posts return `to_friends`.
`GET /api/v1/feed/people` lists tag candidates. `GET/POST /api/v1/fights/{id}/posts`
remain the single-fight list and the old one-fight compose. Comments, reactions,
delete, and report for any post use `/api/v1/posts/{id}/...`.
Listing a fight includes posts from other windows in the same recurring series.
Roster members (`accepted` or `deferred`) can read and post. Invited-only
members cannot. Delete own posts; report or hide another author.
`GET/PATCH /api/v1/notifications/preferences` reads and partially updates a master
switch and individual invitation, ending reminder, final-sync, result, daily,
post, comment, reply, reaction, and mention switches. New-account feed posts,
daily status, fight-ended alerts, and the optional one-week reminder default off.
Saved choices are preserved. Reactions and opted-in feed posts collect into one
evening summary; comments notify the post author, and replies notify the parent
commenter. The closer queues reminders and summaries and drains APNs. Lock-screen
copy uses @usernames, Fight names, deadlines, and post/comment excerpts; a
single-post alert may include its photo. See [notification behavior and rollout](notifications.md).
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

Never delete data (Marc's rule, 29 Sep 2026). New tables and writers keep every
row: no retention windows, TTLs, pruning, or rollups that replace raw rows. Only
a user's own account deletion removes data. No automatic cleanup is left in the
code (30 Sep 2026); see [retention](system-design.md#retention-classes).

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

## Character prompt check (prepared 16 Oct 2026)

Before buying, the app sends the description to Blend's FitFight Prompt Check
workflow through the existing runs API: `POST /api/v1/ai/runs` with
`{ "workflow": "prompt_check", "parameters": { "description", "language" } }`
and an `Idempotency-Key`, then `GET /api/v1/ai/runs/{request_id}` until it
completes. The result is `{ note, variations }`: an optional one-sentence
question or warning (real people, brands and existing characters get "we draw
original animals"; clothes get "everyone wears the FitFight kit"), and exactly
three rewrites. The owner buys with their own words or a rewrite.

- **Free, no character needed.** `creditPrice` is 0 and `resource_id` is null.
  The row stays in `private.ai_requests`, like every AI request.
- **Own limits.** Checks count separately from drawing: 3 a minute, 30 a day and
  2 running at once per person, and their own 20 running at once overall, so
  checking ideas never uses up drawings or their concurrency. Like name
  suggestions, a check neither waits for nor blocks the owner's other runs.
- **Slow.** A run takes about 45 to 60 seconds, sometimes 2 to 3 minutes when
  several run at once. Its first read waits 20 s, then one every 5 s. The app
  never blocks on it: "Your idea" opens at once with the owner's words, and the
  rewrites appear when the run ends.
- **Unreadable output** (not JSON, not exactly three rewrites) fails the run as
  `ai_invalid_result` and keeps Blend's raw response on the row.

See [Blend workflows](blend-workflows.md#configuration-and-rollout).

## Snake record (prepared 16 Oct 2026)

The Snake game shown while a custom character is drawn keeps every finished game
in `private.snake_scores` (`user_id`, `score` 0 to 222, `duration_ms`; a 15 by
15 board holds at most 222 points). `GET /api/v1/snake/scores` returns
`{ record }`, the highest score across all players; `POST /api/v1/snake/scores`
with `{ score, duration_ms }` saves a game and returns the record including it.
Both need a signed-in player. A basic guard, Marc's request: the snake moves at
most once every 80 ms, so a game needs at least 80 ms of play per point (API and
table check), and a player's next score waits at least that game's length and
5 s after their last one (429 `snake_too_soon`), under a per-player lock so two
posts at once cannot both pass. Scores still come from the app,
so a patient tampered client could reach 222 in about 18 s of claimed play.
Rows go only when their player deletes their account (`on delete cascade`).

## Companion names and lines (prepared 15 Oct 2026)

A custom character can have a name (1 to 24 characters) and a line (1 to 60),
trimmed and on one line, saved together in `private.custom_character_purchases`
(`name`, `line`). Typed text is not reviewed first, like usernames and Fight
names. Blend's Companion Lines workflow suggests four pairs per batch from the
chosen portrait and the description, in the owner's language (`fr` when the
newest installation is French, else `en`). See
[Blend workflows](blend-workflows.md#configuration-and-rollout).

- `GET /api/v1/me/custom-characters`: each character adds `suggestions` (every
  completed batch, first batch first), `suggestions_pending`,
  `more_suggestions_left` (0 to 3), and `name` and `line` (null until saved).
- `POST /api/v1/me/custom-characters/{purchase_id}/label`, `{ "name", "line" }`:
  owner only, not refunded. Returns the character, 200.
- `POST /api/v1/me/custom-characters/{purchase_id}/suggestions`,
  `{ "attempt_id": uuid }`: starts one more batch that avoids every earlier
  suggestion; the same `attempt_id` returns the same batch. 202 while it runs,
  `409 suggestions_limit` after three extra batches or six batches of any status,
  `409 ai_in_progress` while a
  batch runs, `404 not_found` before a portrait is chosen. A batch is extra only
  when an earlier batch had completed, so a failed first batch is retried free.
- `GET /api/v1/me` and `GET /api/v1/profiles/{user_id}` add optional
  `companion_name` and `companion_line` for an equipped custom character: the
  saved pair, else the first suggestion. Another viewer gets them only when the
  profile is shared with them. Stock companions and Specials send neither.
- `private.ai_requests.provider_response` (jsonb) keeps Blend's raw run response
  when a run fails, is cancelled, or returns unreadable output, for every
  workflow. It never reaches the app or the server error log.

The first batch starts once, when a portrait is chosen (`lines_action_key`); the
reconciler backfills existing characters one per run. A batch is first read 30
seconds after it starts, then every 10 seconds. Apply
`20261015120000_companion_labels.sql` before deploying the backend.

## Fight chart consistency (prepared 15 Sep 2026)

Apply `20260915200338_fight_step_checkpoints.sql` before deploying this backend.
`GET /api/v1/provider-uploads/context` adds the Fight's `time_zone`. New native
uploads attach optional `step_checkpoints` to each `fight_aggregates` item. Each
point is cumulative Steps from the Fight start, through that Fight day's end or
the current cutoff. Since 14 Oct 2026 the first day is an exact query from the
Fight start, later days add one shared daily read per Fight time zone, and no
point exceeds the score. The final query supplies both the last point and the
scored total. The server validates complete day coverage, increasing
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
in `private.referrals`. Self-referrals and duplicates do nothing. Only an account created at
most 7 days before the claim counts; an older one gets `account_not_new: true`.
Relationships use account IDs and cascade on deletion of either account. Deploy the
referral migration and backend before the native build. See the install handoff in
[`status.md`](status.md).

The friend usually claims on the website before installing: `/r/<code>` signs in with
Apple or Google through Supabase Auth and posts the claim at once. Google first calls
`POST /api/v1/auth/google`, the same rule as the app, so one email gives one account.
When the referred account's first Apple Health steps arrive (a `private.activity_metrics`
day total above 0 from an `apple_health` source), `grantReferralFreeCharacters` gives the
referrer a `referral` grant and the friend a `referred` grant, both keyed by the friend's
id, and the referrer gets one push. It runs after a referral claim, after each HealthKit
upload, and in the 15-minute `close-fights` sweep. See
[Blend workflows](blend-workflows.md#free-characters).

## Loop

A cloud agent writes SQL in `supabase/migrations` and tests in `supabase/tests`, then opens a PR **into `develop` only when Marc explicitly asks for a PR**. Marc merges that. The persistent Supabase branch `develop` picks it up. TestFlight is a later merge to `preview`. Production only changes when Marc merges `preview` → `main`. Agents do not get the database password or `sb_secret_...` key, and they do not merge unless Marc asked.

GitHub-hosted **Ubuntu** starts disposable Supabase Postgres, Auth, Realtime, and the Data API, lints the schema, runs pgTAP and TypeScript transaction tests, and rejects `DROP TABLE` / `TRUNCATE` / `DROP COLUMN` unless the **first line** of the file is exactly `-- allow-destructive`. The same backend tests run again after applying the deferred client-permission cutoff, including real signed-in Data API denials and signup. Agents never run it against a hosted project. On Marc's Mac, `scripts/run-simulator.sh local-db` runs one stack per workspace for Simulator testing (Marc approved this on 17 Oct 2026); see [shipping](shipping.md).

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
confirmed account email `marc@marclamy.com`, username `marc` or `rad`, or extras in
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

`POST /api/v1/healthkit/diagnostics` retains the latest private operational snapshot and accepts an optional batch of completed timing attempts. Old native payloads that omit empty timestamp/error fields remain accepted. Attempts contain a random trace ID, trigger, outcome, elapsed stage timings, app version/build, optional counts/encoded payload size, and optional stage errors with a fixed kind and numeric system code or HTTP status. They contain no Steps values, Fight IDs, device identifier, free-form errors, or raw HealthKit data. `private.healthkit_sync_attempts` is inaccessible to app clients and Fight peers and cascades on account deletion. Attempts are kept for the life of the account (never-delete rule, 29 Sep 2026) and removed only by account deletion. The admin dashboard counts app opens from `foreground` attempts.

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
`final`, and `cancelled` stay frozen. Old apps never call this route. An optional
`joinCode` (15 Oct 2026) renames the series code: 4 to 12 letters or digits, normalized
like a typed code (uppercase, spaces and dashes dropped), written before anything else.
Random codes stay 4 characters without lookalikes. A code another series holds returns
`409 join_code_taken` with nothing changed. `PGG7` keeps its code (`403`) and no other
fight can take it, since signup and the admin dashboard find the app-wide fight by it. The old code is freed and its links stop working.

`POST /api/v1/fights/{fightID}/cancel` is owner-only. The app’s Edit summary Delete
uses it. It pauses the series first, then marks the fight `cancelled`, so a repeating
fight does not mint the next window. A failed pause leaves the fight live so the owner
can retry from Edit. A retry on an already-cancelled fight still pauses. `final` fights
stay frozen. Old apps never called this from the Edit screen.

Recalculation locks the Fight, then accepted memberships, before reading the latest
selected-source exact-window snapshots. It freezes scores, completeness, selected
snapshots (`is_final`), and Fight state in the same transaction. It never substitutes
raw observations or daily chart totals. A member without an end-cutoff snapshot keeps
their last synced total and is ranked with it, marked incomplete (decided by Marc,
15 Oct 2026). Steps only go up, so the Fight finalizes as soon as no missing final
sync can change a rank: everyone has an end-cutoff snapshot, or the only member
without one is already strictly ahead of every other racer. Otherwise it waits.

The deadline is the per-fight setting `fights.closes_after_grace`: on, the Fight also
finalizes at `ends_at + final_sync_grace_seconds` (24 hours); off, it waits for
everyone. It starts on for the Everybody fight (`PGG7`), founder rounds and a round
when Marc suggests it, and off for fights people make and friend rounds (Marc,
16 Oct 2026). Every new round copies it. The owner, or either friend for a friend
round, changes it with `closesAfterGrace` on `PATCH /api/v1/fights/{id}` while the
fight is still editable; founder rounds, the Everybody fight and Suggested fights refuse `false` (`403`). The snapshot's
`grace_ends_at` and the final-sync push deadline are null when it is off. The
closer and app refresh recalculate an awaiting Fight only once it is settled or past
its deadline (`awaitingDueAt`, mirroring `recalculateFight`), so a Fight still
waiting for someone costs nothing per tick. A member who already sent final Steps stops
re-reading a still-awaiting Fight 7 days after its end (`SETTLED_FINAL_SYNC_DAYS`, also
for friend and founder rounds scored from daily Steps), so waiting rounds leave active
members' uploads. Profile results count every first place;
summaries frozen before this change keep their forfeits and all-missing draws.

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

`GET /api/v1/feed/activity` supplies Profile -> Activity. It returns `{ events,
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

Each foreground/manual refresh and each observer call that starts an upload owns a trace. One upload reads every HealthKit type, but every changed type calls its own observer. So an observer call answers HealthKit at once and records nothing while another upload runs, or for 15 minutes after a successful Steps upload (12 Oct 2026). Native `ContinuousClock` measures permission prompts separately, today's HealthKit read, context retrieval, merged-day and each exact-window HealthKit query, upload, and final Fights refresh. The total ends after the final requested app work and mapping/cache updates. Observers omit the screen refresh they do not perform; expiry records a cancelled attempt once. Routine token retrieval uses the SDK's valid session accessor; account deletion still explicitly renews its session.

The native API sends `X-FitFight-Trace-ID` for context, upload, and Fights refresh. Their responses include `Server-Timing` for `auth`, `db`, optional `maintenance`, and `total`, including failures. Structured `fitfight_request` Vercel logs contain the same trace ID, fixed operation name, status and durations only. Server `db` includes pool acquisition, locks, and the whole database operation; it is not an isolated query execution time. Server `total` starts at handler entry and excludes earlier cold-start time. Compare each stage's client duration with its server timing; never subtract phone and server wall-clock timestamps.

One immutable completed attempt is logged locally under OSLog category `HealthKitPerformance` and sent through the existing diagnostics endpoint after product work completes. Reporting is best effort and is excluded from the attempt's own duration, avoiding recursive timing reports. Network loss, suspension, or termination can prevent server delivery; there is no background retry queue. The underlying HealthKit callback may still finish after observer expiry, but cancellation prevents a subsequent upload from that expired attempt.

Time limits (12 Oct 2026): requests that carry a trace (context, upload, activity upload, Fights refresh) time out after 120 seconds without data. Slow data that still moves does not count, and the 10-second refresh limit and the 25-second background limit stop sooner. A foreground/manual refresh stops its network part after 10 seconds (30 until 14 Oct 2026), records a cancelled attempt, and shows Try again on Fights, a Fight, and Profile. The limit starts after the HealthKit read, because a permission sheet waits for the person. The refresh holds an iOS background task, so leaving the app lets it finish instead of freezing it until the next open. `ContinuousClock` keeps counting while iOS suspends the app, so a very long attempt usually means a suspension, not a slow request. HealthKit error 6 (database inaccessible while the phone is locked) records `protected_data_unavailable`. When a foreground refresh finds read types that the app never requested, such as types added after the person connected Apple Health, it shows the Health sheet again. iOS lists only the new types, which removes HealthKit error 5 from the activity sync.

Failed stages preserve HealthKit/URL/Cocoa numeric errors, HTTP status, decoding/configuration failures, and the app's unavailable/invalid Steps errors. Unknown error domains are reduced to `unknown`; messages, URLs, query predicates and `NSError.userInfo` are never logged. The existing `stages` JSON stores these details without another migration. After authentication and validation, the diagnostics route emits `fitfight_healthkit_failure` to Vercel logs before database persistence, with trace ID, app version/build, trigger, outcome and failed stages. Legacy reports such as build 153 emit their coarse error only; discarded device errors cannot be recovered retroactively.

Profile → Apple Health retains a per-account error reference containing the trace ID's first eight characters, stage and safe error code, including when diagnostic delivery fails. Match that prefix against `fitfight_healthkit_failure` and the full trace ID against `fitfight_request`. Delivery failures also log locally under `HealthKitDiagnostics`; the next successful Steps sync clears the phone's reference. Deploy this expanded diagnostics schema before distributing the native build.

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

## Specials: paid limited companions (updated 12 Oct 2026)

**Current model, 12 Oct 2026:** Specials are no longer one of a kind. Any account
may own any number of them. Each is one charge of the consumable
`com.fitfight.mvp.special`; `POST /api/v1/me/specials/purchases` verifies it
and records the chosen Special in `private.special_purchases` (one row per
transaction, `revoked_at` on refund). Ownership is a non-revoked purchase or an
edition owned under the old model. Holds, Taken and the one-per-account limit
are gone; `/checkout` refuses `reserve` with `410 special_update_required`. The
rest of this section describes the retired one-of-a-kind model, whose tables and
legacy products are kept for existing Sandbox purchases.

The 40 supplied animal photos have stable `limited-*` companion IDs and sell as
non-consumable StoreKit products at EUR 0.99. Each photo, including alternate
poses of one species, is a single edition. `private.special_editions` holds one
row per edition per Apple environment (`Sandbox`, `Production`), so each
deployment's inventory and App Review's Sandbox purchases stay separate.
`private.special_accounts` binds a FitFight user to one environment and supplies
the StoreKit `appAccountToken`. `private.special_transactions` records every
verified charge, including refunds and conflicts.

An account may hold or own one Special. Ownership is permanent and separate
from the equipped profile companion; switching animals never releases it. A
refund retires the edition and clears it from the profile; a reversal restores
ownership. `private.require_special_ownership` rejects equipping an unowned
Special from any writer, including older backends and direct clients, and
`PATCH /api/v1/me` maps it to `403 special_purchase_required`.

`POST /api/v1/me/specials/checkout` reserves an edition before the Apple sheet or
cancels the matching attempt. Unpaid holds lapse 30 minutes after they are made:
`readSpecialStore` releases them before reading, and a reserved row's
`updated_at` is its reservation time; resuming the same checkout restarts it.
Account deletion frees a hold at once. A charge that arrives later is owned if
the edition is still free and the account has no other Special; otherwise it is
recorded as a conflict and the app offers Apple's refund request. A refund only
retires an edition its purchase held or owned. On production, App Review signs in
with its own Apple Account and buys in Sandbox: a Special or character charge that
names Sandbox moves an account with no purchases to the Sandbox shelf, and the
charge is verified there. Production opens that shelf only while the release
registry lists a production build in review. App Store users only make
Production charges.

Deploy `20260920222056_paid_specials.sql`, then the backend, then distribute the
app. Let older backend instances drain first, because their schemas list only
the previous companion IDs. Existing API contracts are unchanged; the Specials
endpoints are additive. Older apps show their photo or initials fallback for
`limited-*` IDs they do not bundle. No app-facing RPC is introduced.

## In-app alerts (prepared 15 Oct 2026)

When the app opens, `GET /api/v1/alerts?language=en|fr` returns up to three alerts
for the signed-in account, highest priority first. The app shows them one at a
time in a dialog over the dimmed app; tapping outside closes it.
`POST /api/v1/alerts/{id}/responses` with
`{ "response": "shown" | "tapped" | "dismissed", "action"?: ... }` records what
the person did. An alert stops showing once it was tapped or closed; seeing it
does not count. Closing or "Not now" shows the next alert; a button that opens
something (update, character, new fight) leaves the rest for the next open. The
app sends its version in `X-FitFight-Version`, which the rules can read.

Alerts are code, not rows: `web/lib/alerts/in-app-alerts.ts`, reviewed in a PR.
Responses are rows in `private.alert_responses` (RLS on, no client grants),
removed only with the account. Builds without this code never call the endpoints
and keep only the update toast.

**Adding an alert (agents):**

1. Add an entry to `inAppAlerts` at its priority. The `id` is permanent:
   lowercase letters, digits, hyphens. Never reuse or rename one.
2. Write `who` with the facts in `AlertFacts`
   (`web/lib/types/alerts/in-app-alert.ts`): `appVersion`, `latestRelease`,
   `daysSinceSignup`, `fights`, `customCharacters`, `purchases`, `friends`,
   `stepsLast7Days`, `answered`. Compare versions with `versionAtLeast`, never
   with `<` on strings.
3. Write the title, body, and one or two buttons in English and French. The
   first button is the primary one. No en or em dashes; the test fails on them.
4. Button actions: `update` (the App Store, or TestFlight on staging; the alert
   waits while Apple's list is unavailable), `open_character`, `new_fight`,
   `dismiss`. A new action needs app code: gate its alert with
   `versionAtLeast(facts.appVersion, "<first build with it>")`. Older builds
   close the alert on an action they do not know.
5. Optional `image`: a file under `web/public`, e.g.
   `/landing/companion-alpaca-1.webp`.
6. Run `npm test` in `web/`. Merging to `develop` puts it on staging; it reaches
   App Store users with the normal promotion to `main`. No app build is needed.

A new fact goes in `readAlertFacts`, `alertFactsRowSchema`, and `AlertFacts`,
with a check in `alerts.integration.ts`.

An update pitch and its follow-up for a feature that ships in 1.3.0:

```ts
{
    id: "update-1-3-0-photos",
    who: (facts) =>
        !versionAtLeast(facts.appVersion, "1.3.0") &&
        facts.latestRelease !== null &&
        versionAtLeast(facts.latestRelease.version, "1.3.0"),
    // title, body, then buttons: action "update", then "dismiss"
},
{
    id: "new-in-1-3-0-photos",
    who: (facts) => versionAtLeast(facts.appVersion, "1.3.0"),
    // the same feature, with a button that opens it
},
```

The pitch turns on by itself once the App Store offers 1.3.0 and stops once the
person updates; the follow-up then shows. On production, `latestRelease` comes
from Apple's public App Store lookup (`itunes.apple.com/lookup`, no key, reused
for 5 minutes), so it changes when people can actually tap Update. Staging has
no public TestFlight lookup and reads `releases.json`, which the GitHub release
job rewrites every few hours.

Apply `20261016120000_alert_responses.sql`, then deploy the backend, then
distribute the app. Both endpoints are new; no existing contract changes. The
shared response fixture is `contracts/fixtures/in-app-alerts.json`.

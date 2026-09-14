# FitFight status: what works, what’s fake, what’s next

Read this before building. Last updated **15 Sep 2026**. App: **1.0.0**.

Do **not** restore removed surfaces. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, or a broader marketing site unless the [Notion Product Backlog](https://app.notion.com/p/3d38907c7ecf816facdff36cb59f463e) says so. Fight posts, the Feedback tab, challenge-reminder pushes, and feed social notifications are in this build. Only the public privacy and support pages exist on the web.

---

**Last TestFlight:** 15 Sep 2026. **1.0.0 (198)** from [#223](https://github.com/slooowshutter/FitFight/pull/223). Tester: Invited-tab count ([#222](https://github.com/slooowshutter/FitFight/pull/222)). Friends stay **190**.

## API and update rollout (verified 13 Sep 2026)

Read-only checks on **13 Sep 2026 (UTC)** supersede the earlier blanket "prepared, not deployed"
description for staging. Recheck these endpoints before any rollout; build numbers
and availability are observations, not permanent configuration.

| Part | Observed status |
| --- | --- |
| Native/API separation | Current source calls `/api/v1`, sends app version/build headers, and routes application database access through `FitFightAPI`. The full update overlay checks release eligibility at launch/foreground and every minute while active, and only replaces the app when the installed build is known to be outdated. A failed or offline check leaves the app usable. No `/api/v2` is needed or implemented. |
| Staging release policy | [`/api/app-release`](https://staging.fitfight.app/api/app-release) returned 200: `latest` 184, `review`/`internal` 189, all `1.0.0`, `enforced: true`. |
| Staging backend enforcement | A read-only `GET /api/v1/me` with build 183 and an intentionally invalid audit bearer returned `426 update_required` before authentication. No real user session or data was used. |
| Staging profile readiness | [`/api/health`](https://staging.fitfight.app/api/health) returned `schema: ready`, `profile_api: true`. This readiness check includes the additive profile migration and backend reader role. |
| Production | [`/api/app-release`](https://fitfight.app/api/app-release) returned 404. `/api/health` returned 200 with `schema: ready` but no `profile_api` marker. The public release manifest had no production latest/review/internal build and `enforced: false`. Production rollout of these protections is incomplete. |
| Automatic availability refresh | `.github/workflows/app-releases.yml` is absent from default branch `main`, so its 15-minute schedule is not active. Uploads and matching `develop` pushes refresh the manifest; background discovery of later Apple availability still needs normal authorized promotion. |

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

| | Integration | TestFlight | Real users / App Store |
|---|---|---|---|
| GitHub | `develop` | `preview` | `main` |
| TestFlight | no upload | push/merge to `preview` (optional manual `workflow_dispatch` on that branch; no daily cron) | never; `main` does not upload to TestFlight |
| Supabase | develop project (`zstzbf…`, version line says `staging`) | same staging backend | production (`pvqn…`, version line says `prod`) |
| What you do | Merge PRs **into `develop`**. | Merge `develop` → `preview` for a TestFlight. | Merge `preview` → `main` only when Marc says ship |

A feature PR is another git branch. Merge it **into `develop`**. That updates the **staging** database (new SQL) and is the home for later chats. It does **not** upload TestFlight.

Once configured, Vercel accepts small authenticated Apple Health aggregate requests and receives account-deletion commands. The phone sends Apple's merged Steps total for each exact Fight window, plus merged daily buckets only for the relevant Fight chart days. The same request may also send private merged activity totals and workout summaries. Those extras are stored for later challenge types and do not score Steps fights. Create, join, and leave go through the API. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Before this branch ships

The mandatory-update manifest and `GET /api/app-release` are live on staging; production still needs the endpoint before its native build, and the scheduled publisher must reach `main`. The existing server `NEXT_PUBLIC_SUPABASE_URL` selects the staging/production release channel. The native app replaces Fights with the full update overlay when the installed build is known to be outdated. A failed or offline check leaves the app usable. Known mismatches still survive relaunch. Internal-only builds do not become the Friends Beta requirement. No database migration is part of the update check itself. See [mandatory updates and database rollout](shipping.md#mandatory-updates-and-database-rollout).

The 7 Sep referral changes require the referral migration, `POST /api/v1/referrals`,
and updated Universal Link association before the native build. You → Settings →
Refer a friend shares `/r/{profile-referral-code}`; fight links include `?ref={code}`.
Uninstalled iPhone users go to TestFlight after five seconds. They must reopen the
original message link after installing; sign-in and username setup then resume the
referral and challenge. Workspace checks do not replace cloud CI or two-phone testing.

The 5 Sep performance changes require the timing-history migration and the backend's new `POST /api/v1/fights/refresh` before the native build. Fights now load through one API request; aggregate uploads and finalization batch their database writes. Private timing attempts distinguish HealthKit, authentication, upload and final refresh time. Workspace checks are not a deployed TestFlight build; cloud iOS/PostgreSQL validation and staging measurement remain required.

Apple Health synchronization requires `FITFIGHT_API_URL=https://staging.fitfight.app` plus Vercel's server-only Supabase URL/secret and pooled `DATABASE_URL`. Fresh Apple sign-in and automatic revocation also require the Vercel Sign in with Apple Team/key/private-key/client-ID values and stable token-encryption key. Configure those first; otherwise sign-in fails visibly. Do not expose schema `private`.

After the backend is configured, merge the feature PR into **`develop`**, not `main`. The staging migration must land before merging `develop` → `preview` for the TestFlight build.

The 9 Sep Feed destinations change needs `20260909233000_feed_destinations_and_engagement.sql` plus the feed/posts, people, comments, and reactions APIs deployed before the native build. Old `GET /api/v1/feed` still returns only fight-audience posts so installed builds keep decoding. The 12 Sep one-feed list uses `GET /api/v1/feed?scope=all` (Main and fight posts). Current Feed uses `GET /api/v1/feed` with no scope (fight posts from membership only).

Verify the minimal product alongside Apple Health synchronization:

1. TestFlight → **Update**. Look for `1.0.0 · build N · staging · 9 Sep` at the top.
2. Check Fights, a Fight detail, New, You, and Feedback in both Night and Day. There are four tabs: Fights, New, You, Feedback. Feedback opens on the same fight posts Feed; Bugs, Top, and Report sit beside Feed. Each post identifies its channel with plain text beneath the author. A fight opens on Stats, with Feed and Share beside it.
3. New starts on Create, Join, or Post. Create still guides Steps, duration, private by default (or public), optional usernames, repeat on by default, optional title and action, and review. Every fight has a code and a share link; people join with that code or invite link. Join is that code plus a live public list with no scores. Private fights stay off the list. Suggested fights that Marc flags show under those choices. Earlier create steps use **Next**. Review uses **Slide to start**.
4. Confirm sign-in, username, Apple Health Steps, Fight invitations, standings with last-sync times, Privacy, Support, Bugs & requests, Versions, sign out, and Delete account.
5. Confirm the old Requests tab, friend requests/lists, money, other Metrics, and dead settings are absent.
6. If sign-in fails: hosted **develop** Supabase → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

The native Fight path uses the API to create and join; Apple Health synchronization and account deletion also require Vercel.

---

## What this build does

| Surface | Status |
|---|---|
| Welcome + Apple sign-in | Works |
| Languages | English and French follow the iPhone's per-app language. Usernames, Fight names, and loser actions remain exactly as entered. |
| Username onboarding | Works. Required once after sign-in. Optional profile photo on the same screen; then Connect Apple Health; then challenge reminders (pre-prompt before iPhone’s sheet); then a last screen that the Feedback tab can take a feature or a bug. Existing accounts keep You → Apple Health. |
| Version line | Release-candidate TestFlight says `1.0.0 · build N · staging`; the App Store build says `prod` |
| Create Steps challenge | Follow a guided flow: Create, Join, or Post, then Steps × highest total, 3 / 7 / 14 / 30 days or Custom with exact future start and end dates/times, private by default (or public), optional usernames, repeat on by default, optional title and loser action, and review. Public and private fights may start with the owner alone. Every fight gets a code and a share link; people join with that code or invite link. Suggested fights that Marc flags appear on New. The person who created a live or upcoming fight can Edit it from the same last-step summary as create: Change opens that create page, then back. The owner also gets Delete at the bottom, which cancels the fight (final stays frozen) and pauses a repeating series. Finished fights stay frozen. |
| Accept / Join | Invites still accept in the fight. Anyone can open the same Accept/Join screen from a code or a shared link. Public fights also appear on the live Join list with no scores. Private fights do not. Joins go through the server. If a repeating fight is past its start day, joiners choose this round (steps count from that start date) or the next round. Same-day joins, even hours later, still count as this round. People waiting for the next round are visible on the fight and do not count in this round. Leave a public, private, or repeating fight from the fight itself so the next window does not copy you in. |
| Invite participants | Exact username in New is optional on public and private fights. They must have signed in and chosen a username. There is no friendship or friend-request layer. |
| Apple Health | Installs background delivery at launch, keeps one interrupted opportunity for foreground reconciliation, and shows private capability/sync status under You → Apple Health → More settings. It sends Apple's merged cumulative Steps total for each exact active/ending Fight window in one small authenticated request. The same request may also send private active and resting energy, distance, exercise, stand, flights, and workout summaries including each workout's active minutes. Extra activity is stored separately so a workout-details failure cannot roll back Steps. You shows the real server or network error on the Apple Health row instead of only "Sync failed", and a failed sync is Retry, not Connected. Extra activity is not a Fight option yet. |
| Daily totals | Sends Apple's merged daily buckets only for days relevant to active Fight charts. They are display data, not the source of the Fight score. |
| Fights list | Every row is titled by the fight name. If there is no title, the loser action is used; older fights still stored as `Steps Fight` show the action the same way. The right-hand number is your gap to the person you are racing, moss when ahead and ember when behind; remaining time sits under the title as months, weeks, days, hours, and minutes, with days and hours when under two days, and without the calendar end date. There is no moss hero: live Fights are all the same size. Pull to refresh on Fights, a fight, Feedback, and You stays open with the current sync sentence; opening the app shows the same while Steps are read, uploaded, and standings refresh. |
| Standings | Live scoring uses exact Fight-window HealthKit aggregates, not overlapping whole-day totals. Both phones read the same serving rows. Each standing shows relative sync freshness; ended Fights distinguish exact final-window coverage from the last available Steps. |
| Fight end | Exact `ends_at` is the final cutoff. The fight screen and finished list show that date and time. The live list shows remaining months, weeks, days, hours, and minutes instead of the stop date; under two days it shows days and hours. Opening the app closes due fights; the protected Vercel cron runs daily if nobody opens it. After finalization, later Steps cannot change the result. **Fix in PR (not on TestFlight yet):** Finished shows **P** during `awaiting_final_sync`. After 24h, people who did not submit forfeit; both miss is a draw. |
| Tabs | Fights, New, You, Feedback. Feedback holds the same fight posts Feed, Bugs & requests, Top ranking, and a Report form. The old Requests tab and Design are removed. |
| Look | Night/Day, Nunito, fixed Moss/Ember/Gold semantics; no accent picker or public design-system showcase. |
| Versions | Works under You → Settings (the public changelog). The top version label stays on every root screen. Tapping it opens the admin/debug menu only for signed-in username `marc`. |
| Bugs & requests | Works on the Feedback tab (Bugs, Top, and Report), with a shortcut still on You above Settings. Signed-in people can post a bug or a feature request, attach a photo, a video, or any file, browse the board, upvote, and comment with their username. Device/debug metadata is stored when someone posts or comments, omitted from the board API, and attached again when Marc taps Send to Cursor (original snapshot plus the phone that sent it, plus attachment links). After `NOTION_TOKEN` is on Vercel, each new post also lands as a P0 Inbox row in the Product Backlog. After `CURSOR_API_KEY` is on Vercel, Marc sees **Send to Cursor** on a post and can start a cloud agent with the post, comments, those device snapshots, and attachment URLs. A successful send moves the matching Notion Product Backlog row to Building; when that agent finishes and opens a PR, FitFight marks the same row Done. |
| Privacy / Support | Pages are implemented and linked under You → Settings. Staging uses `staging.fitfight.app`; production uses `fitfight.app`. Each route must be deployed before that build is tested or submitted. |
| Fight posts / Feed | Accepted and waiting-next-round members can post a short note, up to four photos, or one short video. Root Feedback → Feed is the same fight posts list as before (not a Recent/Top ranking of loaded posts). Root + chooses a new post or a new request. Media can take a photo with the camera or pick photos and video from the library. Posting to several fights keeps one post and shows those fight names; All fights shows Public. A fight’s Feed tab starts on that fight and can add other channels. There is no Main destination or tag-people picker. Each card puts its plain channel label, then the relative time, beneath the author, with actions at the top right. Posts support emoji reactions, nested comments, editing/deleting your own post, reporting another post and hiding its author. Other members of that fight can get a push when you post in that fight’s Feed; the post author can get comments and reactions; a reply notifies the parent commenter, not sibling commenters. You → Settings → Notifications turns each of those on or off, plus challenge reminders and daily status. Fight detail opens on Stats, with Feed, Share and recurring History alongside it. Recurring fights retain earlier posts; invited-only people gain access after joining. |
| Companion | Saved on the account. Pick from a grid of animals, or Custom with one description (species, breed, accessories, colors). That text is stored for later image generation; generation is not built. Other people see the stock animal, or initials until a custom image exists. People who have not chosen an animal are asked the next time they open a build that includes this. Pose and generation controls are not shown. |
| Account deletion | Permanently deletes the profile, photos, username, authentication, Health/Steps data, relationships, invitations, memberships, scores, owned Fights, fight posts, and bugs/requests the User posted; removes participation from other Fights; clears local Health sync state; and revokes a stored Apple credential when available. |
| WHOOP / Strava | Not built |
| Removed scope | No persistent friends, Requests tab, money/payouts, bragging-rights option, other Metrics, goals, or dead settings/actions. |

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

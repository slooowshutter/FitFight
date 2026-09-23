# Notifications

Prepared on 20 Sep 2026. See status.md for cloud verification and deployment evidence.

You > Settings > Preferences > Notifications has a master switch and an individual
switch for every automatic category. The master switch pauses all push delivery,
including the manual admin endpoint, without changing category choices or Feed
visibility. iPhone notification permission is also required.

| Setting | New-account default | Delivery |
| --- | --- | --- |
| Invitations | On | When invited |
| 24-hour ending reminder | On | Once, 24 hours before the end |
| One-week ending reminder | Off | Once, only for 30-calendar-day fights |
| Fight ended | Off | At the end |
| Final sync needed | On | Once after the end, only while final steps are missing |
| Final results | On | When results are confirmed |
| Daily status | Off | Existing daily update per live fight |
| New feed posts | Off | Included in the evening summary when enabled |
| Comments | On | Promptly |
| Replies | On | Promptly |
| Reactions | On | One evening summary |
| Mentions | On | Promptly |

Ending reminders are separate from final sync. A pre-end sync does not contain
the entire fight. Users still have the existing 24-hour post-end grace period;
this change removes the repeated 12-hour, 6-hour, and 1-hour pushes. When both
Fight ended and Final sync needed are enabled, a missing final sync produces one
request instead of two alerts. Completion or finalization cancels that request.

## Evening summary

Reactions and opted-in new posts collect until 20:00 in the account's saved IANA
time zone. Accounts without a saved zone use UTC. Activity after 20:00 goes into
the following evening's summary. Calendar conversion follows daylight-saving
changes. Empty summaries produce no push, and an outbox key limits the summary
to one per account/local date across retries and concurrent workers. Summary
windows expire at midnight so a missed evening does not produce an old morning
recap.

Delivery rechecks enabled categories, current post access, deleted content,
removed reactions, and blocks in both directions. Counts refer to distinct
people and posts. A single-post alert opens that post; a reply opens its comment.
A summary covering multiple posts opens Notifications & activity in the new app.
Older builds recognize its existing fight route and open the first related fight.

People are identified by @username. Copy includes the relevant fight, exact
ending/sync deadline, or post/comment excerpt. Single-post alerts may carry a
signed photo URL. The iOS notification service downloads only from the two
FitFight media hosts, downsamples photos, and delivers the text if a photo fails.
Related pushes use an APNs thread identifier, and retries reuse their collapse ID.

## Compatibility and rollout

`GET/PATCH /api/v1/notifications/preferences` retains all six released fields.
New fields are `enabled`, `fight_invite`, `ending_24h`, `ending_week`, `fight_ended`,
`final_sync`, `fight_finalized`, and `mention`. PATCH remains partial. The legacy
`challenge_reminder` switch controls its original ended/sync/result group;
individual changes maintain that aggregate for older readers. No app-facing RPC
is introduced. The migration retains old columns, kinds, keys, and client grants.
The actor foreign key uses the existing profiles.user_id primary key while reads
use the equivalent canonical profiles.id alias.

Existing saved choices and opt-outs are preserved. Historical rows do not record
which true values were deliberate versus inherited, so those values are not
silently overwritten. Quieter feed and daily defaults apply when preferences
have not yet been saved. Reactions and enabled feed posts move to the evening
summary for existing accounts as well.

Apply the additive migration, deploy the compatible backend, and let old backend
instances drain before distributing the app. Verify the hosted 15-minute job in
each environment invokes `/api/internal/close-fights`. This existing worker now
also queues ending reminders and evening summaries. The daily Vercel backup is
not sufficient for evening delivery. The hosted setup recipe remains in
`supabase/deferred-migrations/20260911153000_supabase_cron_15m.sql`; its Vault secret
must already exist. Recheck job execution after the authorized deployment.

The extension uses automatic cloud signing with bundle ID
`com.fitfight.mvp.notifications`. An archive and physical-device APNs delivery
remain release checks, separate from unsigned cloud simulator compilation.

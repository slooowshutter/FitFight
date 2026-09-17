# Build plan: request status and system comments

This replaces the earlier multi-table plan. Scope: a status on each existing request
and system messages inside its existing comments. **No new tables.**
See the [public copy and schema](feedback-workflow.md) and [proposed SQL](feedback-workflow.sql).

## 1. Extend the two existing tables

Add `feedback_posts.workflow_status`, defaulting to Submitted, and nullable
`feedback_comments.workflow_status` to record a status change. A non-null comment
status identifies a system update; a null value identifies an ordinary comment.
No separate type flag is needed. Existing rows retain their meaning.
Allow `author_id` to be null for system comments only; preserve the author requirement
for ordinary comments and existing foreign-key behavior.

Create the eventual migration through the Supabase CLI. Keep grants and RLS intact.
No database functions, RPCs, new indexes, or background jobs are required.

Done when the migration accepts old inserts, enforces authored user comments, accepts
system comments, and preserves existing request/account deletion behavior in a
disposable cloud database.

## 2. Add one status-change command

The command takes a request ID, expected current status, target status, and stable
operation UUID. Identify Marc through a server-controlled Auth User ID for this
workflow, not mutable profile names or user metadata.

In a transaction: lock the request, check whether a system comment already exists
with that operation UUID, validate the expected/current status, update the request,
and insert the generated system comment with that UUID. A repeated UUID is accepted
only if it belongs to a system update for the same request and target status;
otherwise reject it. Check expected status when first applying the operation, not on
replay. A status mismatch returns a conflict and the UI refreshes. A no-op creates
no comment.

Only Marc's authorized action can change the workflow in this first version. The
ordinary comment API cannot set author or workflow status. The server
writes the system copy. The approval comment stores Marc as the actor; other messages
can have no actor. Existing account deletion removes actor-linked messages as it does
other authored comments; it must not leave a working link to a deleted Profile.

Moving backward for rework is allowed through the same deliberate admin action.
Do not claim Apple approval or availability based on an agent finishing or a branch
merge. Deployed requires the needed production backend deployment to succeed and the
production app build to finish upload/processing for Apple review. Before selecting
Available, Marc confirms the released app contains the change and is installable.
Status selection records progress; it does not perform merges or App Store actions.

Wire only the existing explicit Send action into this command: record Approved before
the existing provider call, then Being built after confirmed success. If approval was
already recorded, do not repeat its comment. A failed send leaves the request Approved
and uses the current error UI; it does not claim work started. Do not hold a database
transaction across the provider call or add automatic retries. The rest of the workflow
uses Marc's manual status control. No new provider callback, tracking service, or release
automation is included.

Done when updates and comments commit together, duplicate/stale operations are safe,
and ordinary users cannot forge either approval or system messages.

## 3. Read system and user comments together

Extend the existing queries in `web/lib/supabase/queries/feedback-supabase-query.ts`.
Their current inner join to Profiles would hide system comments without an author;
use the appropriate left join and type-aware visibility rules. Return FitFight as
`author_handle` for system messages so legacy clients still receive a non-null string.
Keep normal comment visibility/blocking behavior; never expose a hidden actor through
the optional profile link. System bodies contain only public progress copy.

Keep existing feedback endpoints and request fields. Add optional response metadata
for current status, the comment's historical status, and allowed actor identity.
Update Zod contracts under `web/lib/types/feedback/`; check strict server parsers and
old Swift decoders before exposing additions. Old clients can display the readable
system body while newer clients style it as a FitFight update.

Keep comment counts consistent with the discussion, including system comments. User
comment rate limits count user comments only. Existing ordinary comment creation
continues to return its current response shape. The status command has its own
admin-only endpoint under the existing feedback routes.

Do not store provider IDs, private error logs, or approved AI prompt snapshots in
these publicly readable comment rows. When Marc uses the existing explicit send
control, keep user comments as context and exclude generated progress chatter.

Done when existing requests still decode, system comments appear exactly once, user
comments retain their current behavior, and public fields contain no technical logs.

## 4. Add the small native UI change

Update `RequestsView.swift` and `FitFightAPI.swift` for the status, small Next line,
and system-comment styling. Add a status picker to Marc's existing request controls.
Retain the current board, votes, composer, and comment list. The status and discussion
refresh together on entry, foreground, after a change, and pull-to-refresh.

Use `ProfileIdentityLink` from `profiles-friends-and-stats`, with its existing
`feedback` source, for Marc's name in the approval message. Wait for the final shared
Profile contract before integrating this UI; do not modify the other workspace or
invent a replacement screen. Preserve the comment draft when the Profile closes.

Use existing Night/Day tokens, typography, accessible touch targets, and EN/FR strings.
Next is derived from the current status. Available shows FitFight's existing App Store
link instead. Keep the version label on You only. Add the required 1.1.1 ReleaseNote
when the native implementation is made, plus project entries for any new Swift files.

Done when the public flow uses everyday wording, the profile link opens correctly,
normal comments still work, and the release link is shown only at Available.

## 5. Verify and deploy in the existing order

Relevant checks: atomic status/comment writes, duplicate command UUIDs, repeated
status selection, stale updates, unauthorized callers, nullable system authors,
successful/failed explicit Send, blocking/deletion, comment counts and limits,
legacy API fixtures, and native decoding.
Run web typecheck and relevant tests, then the full backend suite because shared
feedback queries change. Run migrations and database integration tests in disposable
cloud CI, and native validation on GitHub-hosted macOS. No local Xcode or manual
agent workflow dispatch.

Deploy schema support first, with system-comment creation still off. Deploy compatible
readers/writers, verify old-client responses, and drain older backend instances before
creating any nullable-author system rows. Existing rows default to Submitted and user
comments; do not invent past approvals or produce historical system messages.
Then enable the admin command and ship the native UI through the authorized
develop/preview flow. Production promotion requires its own authorization and checks.

Recheck each environment's `/api/app-release` before rollout. The last planning
observation on 17 Sep was staging 1.1.1 (201), enforcement off, and production 1.1.1
(202), enforcement on, both without review/internal candidates. Preserve legacy
staging behavior while enforcement is off. API version stays `/api/v1`.

## Deferred from this first version

The original notification request remains a later piece of work: separate in-app
alerts, followers/mutes, unread tracking, and optional push. None is necessary to add
system comments and request statuses. Likewise, do not build an automated release
or agent-tracking service as part of this change.

This pass updates the plan and proposed SQL only. SQL syntax and static checks do
not replace the cloud migration, API, native, and rollout checks listed above.

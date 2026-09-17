# Request status and system comments

Revised after Marc clarified the scope: extend the existing requests and comments.
**Zero new tables.** This replaces the earlier nine-table and four-table proposals.
Companion [SQL](feedback-workflow.sql) and [implementation plan](feedback-implementation-plan.md).

## What people see

| Status | Small secondary line |
| --- | --- |
| Submitted | Next: Approval |
| Approved by Marc for build | Next: Build |
| Being built | Next: Review |
| Being reviewed | Next: Testing |
| Being tested | Next: Deployment |
| Deployed | Next: App Store approval |
| Approved by Apple | Next: Available on the App Store |
| Available on the App Store | Update FitFight link; no Next line |

Each status change adds a system comment to the existing discussion, for example
“Approved by Marc for build” or “This feature is now being tested.” Show these as
FitFight updates, visually distinct from people's comments. No separate activity log.
Keep the full discussion in its current order, with a stable ID tie-breaker for equal
creation times. Generate a comment once per actual change, not on every refresh.

Marc's name in the approval comment opens his shared Profile. Resolve the recorded
approver's User ID through the component from `profiles-friends-and-stats`; do not
build another Profile screen. If a retained comment's Profile temporarily cannot be
opened, omit its active link. Actual account deletion removes the actor-linked approval
comment under the existing deletion rules; it does not erase the request's current status.

The public wording contains no AI, agent, branch, or PR terminology. Next is calculated
from status; it is not another database field. Deployed requires successful production
promotion: required backend changes are healthy and the production app build has been
uploaded and processed for Apple review. This is separate from App Store availability. Show Update
FitFight only after Marc verifies that the containing version is actually available,
using FitFight's existing App Store URL. Apple approval alone is not availability.

## Small database change

| Existing table | Change |
| --- | --- |
| `feedback_posts` | Add `workflow_status` for the current step |
| `feedback_comments` | Add nullable `workflow_status`: filled for a system status update, empty for an ordinary comment |

Every system comment in this version records a status change, so it needs no separate
type flag. Allow a system comment's existing `author_id` to be empty. Ordinary comments must
still have a real author. An approval system comment uses Marc's real User ID for
its profile link; automated status messages need no fake system account. Store
ordinary readable text in the existing `body`, so older supported apps can display it.

The backend updates the request's current status and inserts the corresponding
comment in one transaction. Use the comment's existing UUID as the operation's
idempotency key, plus an expected current status to reject stale changes. Replaying
an operation or choosing the already-current status creates no extra comment.
Only the dedicated server command creates system comments; the ordinary comment
endpoint keeps accepting just user-written content.

Keep the existing votes, permissions, and comment storage. There are no new workflow,
work-run, event, release, follower, preference, or inbox tables. Existing comment counts
include these messages because they are part of the same conversation.

## First implementation boundary

Marc can change the status in the existing request's admin controls. Those changes
produce the system comments. His existing explicit Send action records Approved before
starting work, then Being built after confirmed success. Failure leaves it Approved;
the existing error is shown to Marc. Later review, testing, deployment, and Apple steps
are updated manually in this first version. Changing a status never launches work or merges code.
Posting a comment never sends it to AI. An explicit existing send action can include
the user discussion; generated workflow comments are not additional task instructions.

Do not build a new release tracker or provider-monitoring service for this change.
The first version uses confirmed status updates. Automatic release/provider callbacks
can be wired to the same command separately when the correct current request/work can
be identified. A callback that cannot prove that match must not change the status.

The earlier notification inbox, follow/mute settings, and push delivery are deferred.
This first version shows system updates inside the existing request discussion. It
must not claim that people receive separate alerts or unread notifications yet.

Planning only. The SQL is outside `supabase/migrations/` and has not been applied.

# Feedback management

Implemented in the working branch on 19 Sep 2026, following Marc's approved
interaction and instruction to preserve the native app design. Not deployed.
The temporary HTML prototype has been removed.

## Native screen

The existing Feedback header, composer, cards, type badges, dates, author links,
comments, spacing, and tab bar retain their native design. The filter tabs are
replaced by the displayed post count on the left and a small, bare filter icon
on the right, aligned with the header's plus button. It uses the same `mossText`
green as Edit profile and retains a 44-point tap target. The count reflects the
loaded list, not a hardcoded four.

Defaults show features and bugs together, exclude archived posts, and sort by
most upvoted. The bottom drawer contains:

- Status: Open or Archived.
- Type: All, Features, or Bugs.
- Sort: Most upvoted, Newest first, or Oldest first.

Show feedback applies all choices together. Reset to defaults changes the draft;
Show feedback applies it. Dismissing the drawer discards unapplied changes.
Posting does not replace the user's selected type or sort. The existing 100-post
limit remains; filtering and sorting happen on the backend before that limit.

## Permissions

| Person | Delete | Archive | Reopen |
| --- | --- | --- | --- |
| Author | Their own open or archived post | No | No |
| Existing FitFight admin | Any post | Any open post | Any archived post |
| Other members | No | No | No |

Actions use the existing ellipsis menu on the card and detail screen. Report and
hide-person controls remain. Delete requires confirmation and removes the post,
comments, votes, reports, and attachment links. Existing storage-byte retention
and external Notion copies are unchanged.

Archive asks for confirmation with an optional public reason. It preserves the
post and its discussion, closes voting and comments, and allows a later reopen.
Reopening preserves existing votes and discussion and clears the archive reason.
This is per-post management; bulk actions and the deferred delivery-status
workflow are outside this change.

## Contract and rollout

The server enforces all permissions. `GET /api/v1/feedback` accepts optional
`status` and `sort` alongside existing `kind`. Detail and list responses add
archive fields and capabilities without removing legacy fields. Author deletion
uses the existing DELETE route. PATCH on the same post route archives/reopens.
Votes and comments use transaction locks to respect concurrent archival.

The additive migration adds `archived`, `archive_reason`, and a supporting index.
Client grants and RLS stay intact. Apply the migration, deploy the compatible
backend and drain older instances, then distribute the app. Existing apps can
continue ordinary feedback operations and decode new responses. A stale vote or
comment on an archived post receives the existing `409 conflict` error shape.

Live policy checked on 19 Sep: staging latest 201, review/internal 204, enforcement
off; production latest 202, enforcement on, no review/internal candidates. Existing
legacy fixtures remain. Frozen 201/202 and 204 decoders verify additive responses;
HTTP coverage retains builds 113, 190, 200, 201, 202, 203, and 204.

Current cloud-check evidence and remaining device checks are recorded in
[status.md](../status.md). No hosted database change, live deployment,
release-branch merge, or TestFlight upload is part of this implementation.

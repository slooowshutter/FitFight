# One-time beta data transfer

This is an operator-run cloud maintenance tool for the 1.1.1 release. It is not an
app endpoint or an ongoing synchronization service. The committed environment
schema accepts only the disposable rehearsal project, `qkkhkfepjhdgowmhhpyf`.
Production cannot be selected without a separate, reviewed code change after
Marc authorizes the production rollout.

## What is preserved

The planner matches Apple provider identities, keeps existing production account
and identity IDs, and remaps declared account/source foreign keys and media paths.
Existing production referral codes remain unchanged. Beta usernames, names,
avatars, and companions always win for shared profiles, including catch-up runs.
There is no production-profile option. Unrelated production history remains present.

New Auth rows use the required zero instance ID and empty confirmation/recovery/
email-change fields. These are neutral defaults, not copied credentials. Supabase
documents the [nullable-token failure](https://supabase.com/docs/guides/troubleshooting/database-error-saving-new-user-RU_EwB);
its [Auth account lookup](https://github.com/supabase/auth/blob/master/internal/models/user.go)
filters by the zero instance ID. The cloud rehearsal exercises a fresh insert
followed by an Auth administrative read.

The explicit table allowlist includes accounts, profiles, Fights, series,
memberships, invitations, Health summaries, score history, Feed/Feedback content,
engagement, moderation records, and notification preferences. Credentials,
sessions, devices, jobs, and unfinished uploads are excluded. Any score snapshot
that still references an operational upload stops preparation.

Row conflicts, identity/email/username collisions, deletions, schema drift, and
revoked shared activity connections stop the import. Daily Steps are never added
together. Catch-up runs compare the new source, the previously imported value,
and the current target; production edits outside profile details remain protected
on later runs.

## Cloud deployment

Use an authenticated Supabase CLI and `--use-api`, without local Docker. Package
`index.ts` with these three repository modules in each temporary function folder:

| Local function filename | Repository source |
| --- | --- |
| `data-transfer.ts` | `web/lib/releases/data-transfer.ts` |
| `data-transfer-types.ts` | `web/lib/types/releases/data-transfer.ts` |
| `data-transfer-query.ts` | `web/lib/supabase/queries/data-transfer-supabase-query.ts` |

Use the pinned imports from `deno.json`, resolving the three `@/lib/...` aliases
to those local files. Deploy as `ff-release-transfer` in staging
`zstzbfocunthczzubggz` and the disposable target. Supabase-managed database and
Storage credentials remain inside each project.

Set the same three temporary secrets in both projects: a random 64-hex
`FF_RELEASE_TRANSFER_TOKEN`, a short UTC expiry in
`FF_RELEASE_TRANSFER_EXPIRES_AT`, and the allowed project reference in
`FF_RELEASE_TRANSFER_TARGET`. Set them from a mode-600 ignored file; never print
the token. Deploy with `--no-verify-jwt`: the handler requires the separate
constant-time bearer-token check and expiry on every request.

Apply `archive-bucket.sql` only on the disposable target. The bucket is private
and has no client policies. Source snapshots and actual media travel directly
between the cloud functions. Operators receive counts and digests only; never
invoke the source's `snapshot` or `media` actions from a workstation.

## Request sequence

POST JSON to the target function with the temporary bearer token:

1. `{"action":"prepare"}` freezes the source and target
   into a private checkpoint and returns `run_id`, counts, and expected digests.
   Beta profile details are fixed. Existing requests that explicitly pass
   `"profile_policy":"beta"` remain valid; `"production"` is rejected. A conflict returns 409.
2. `{"action":"copy-media","run_id":"..."}` copies up to five files. Repeat
   until `files_remaining` is zero. Each file is checked against the source
   checksum and downloaded from the target for independent byte verification.
   Existing files are accepted only when the bytes match; they are not overwritten.
3. `{"action":"rehearse","run_id":"..."}` locks the allowlisted tables, checks
   the prepared target digest, restores rows, verifies every foreign key and the
   full expected row digest, then rolls back. `verify` must report `unchanged`.
4. `{"action":"apply","run_id":"..."}` commits the same transaction on the
   disposable target. Repeating the same run must report `already_applied: true`.
5. `{"action":"verify","run_id":"..."}` checks the full database digest and
   reads every account through Supabase Auth, including its Apple identity.
   Run `verify-access.sql` on the linked target for both client/backend read roles.
6. For a catch-up, prepare with the applied run's `previous_run_id` and repeat
   the sequence. The new checkpoint covers later beta activity. Beta profile
   details win again; other independently edited production rows stay protected.

Historical restoration suppresses signup, scoring, and broadcast triggers inside
the transaction. Foreign keys are checked explicitly before commit. Unique and
check constraints still execute. A changed target after preparation stops the
transfer; prepare a new checkpoint rather than forcing it through.

## Verification and cleanup

Run `npm run typecheck` and `npm test` from `web/`, plus
`deno check --config scripts/data-transfer/deno.json scripts/data-transfer/index.ts`
from the repository root. Cloud evidence belongs in `docs/status.md` and the
release preparation document. Auth administrative reads do not prove an Apple
sign-in from an installed production binary; that remains a release check.

Delete both temporary function deployments and unset all three temporary secrets
when rehearsal finishes. Remove the ignored local token file. Retain the private
cloud checkpoint with the paused disposable project until release verification
is complete, then delete that rehearsal project through the normal cleanup flow.

Live production additionally requires Marc's rollout authorization, compatible
production schema/backend deployment, a fresh recoverable backup, and an agreed
final beta cutoff. The rehearsal alone does not
authorize any of those live changes.

# FitFight release preparation: now 1.1.1

On 15 September 2026, Marc authorized the release PR, preview promotion, and
App Store listing preparation. At 22:22 UTC he also authorized implementing and
rehearsing the data transfer. Main promotion and the live production import
remain on hold.

The latest merged fixes select **1.1.1**. Earlier 1.1.0 preparation below is historical; refresh the draft and screenshots for the final 1.1.1 candidate.

## Prepared code and listing

- Marketing version and production upload workflow: `1.1.1`; CI allocates the build.
- New release note in English and French; existing icon is the intended beige FF on green.
- Six screenshots per language and an [HTML gallery](index.html).
- Updated [store copy](../metadata.md), [review notes](../review-notes.md), English/French
  privacy pages, and the native Photos or Videos privacy declaration.
- App Store Connect has a `1.1.1` draft with saved English/French listing text and
  updated App Review instructions. Screenshot upload, production candidate
  selection, privacy questionnaire, and submission remain pending.

## Public build compatibility

The public binary is `1.0.0 (113)`, built from
`d1a3534c9800d845e25ad5b7bae73819cc0312a5`. It directly reads profiles, Fights,
memberships, and daily Steps, changes its profile, creates Fights/invitations, and
accepts or declines membership. It has no update dialog.

Production had applied only the first ten migrations, through `20260901103643`.
The pending `20260904221828` write cutoff would break build 113. Before its first
production application, that migration now retains only the required column grants
and owner/invitee row policies. Score, source, Fight-state update, and deletion
permissions remain server-owned. It cannot accept another person's invitation.
Already-migrated staging retains its existing write cutoff.

The immutable [build 113 fixture](../../../../contracts/fixtures/legacy-build-113.json)
records the released source and request fields. New cloud CI coverage replays Auth
and PostgREST requests against the migrated disposable database, then reproduces
staging's write cutoff and runs the existing security tests unchanged. The later
full client-access cutoff also revokes these separately granted columns.

At 21:38 UTC, staging advertises `1.0.0 (190)` for Friends and `1.1.0 (200)` for
review/internal, with enforcement off. Existing `/api/v1` fixtures and all 237
backend unit tests pass after merging develop `685507d`. No API version changes.
The Auth/PostgREST test, native compile, database security/transaction tests, and
English/French cloud screenshots passed in release PR #241, merged as `25f8ac8`.

## Earlier cloud rehearsal evidence, 15 September

Created temporary Supabase branch `release-1-1-rehearsal` with production data.
All 28 pending migrations applied successfully. Before and after: 3 Auth users,
3 profiles, 14 Fights, 14 memberships, and 0 storage objects. Transactional SQL
replayed build 113 profile update, Fight creation, invitation, acceptance, decline,
and read paths. Unauthorized score changes, joining as a stranger, and accepting
for another person were rejected. The test fixture was rolled back.

This verifies migration execution and database permissions on a production copy.
It predates the final 1.1.1 migrations and does not verify signed-in iOS behavior,
HTTP requests against the candidate backend, beta data import, or live production
readiness. The temporary branch is paused until the next rehearsal.

## One-time data migration

The earlier read-only inventory found staging with 22 Auth users, 22 Fights, 73 memberships, and 47
stored objects. Production has 3 Auth users, 14 Fights, and 14 memberships. Two
Apple identities occur in both environments with different account UUIDs. There
are 23 distinct Apple identities and no username collision between different
identities in this audit.

Preserve existing production UUIDs for the two overlapping identities. Map all
references consistently, preserve production history, and copy the remaining
accounts, profiles, Fight history, Health summaries, posts, and media. Compare
conflicts and references in the rehearsal before a live import. Preserve a
restorable production backup and account for writes made during the transition.
Do not copy sessions, APNs device registrations, pending jobs, or encrypted Apple
refresh credentials under a different environment's key.

The [cloud transfer tool](../../../../scripts/data-transfer/README.md) is now
implemented with an explicit table allowlist, Apple identity mapping, private
checkpoints, file hashes, atomic rollback/commit, and three-way catch-up conflict
detection. Its target allowlist accepts only the disposable rehearsal project;
production remains excluded. See the current evidence in `docs/status.md`.

The completed rehearsal combined 23 beta accounts and 3 production accounts into
24 users, 36 Fights, and 88 memberships. It copied and checked all 52 ready files,
proved rollback and repeat-run safety, and applied a later 86-row catch-up. Auth
reads passed for all users and a fresh importer-created fixture. Both read roles,
the build 113 SQL fixture, TypeScript/Deno checks, and 247 unit tests passed.
Marc confirmed **beta always** for the two shared profiles, including catch-ups.
Production account IDs, referral codes, and unrelated history remain preserved.
A fresh production backup and installed-client Apple
sign-in/API checks are still required for the live rollout.

### Proposed transfer sequence

1. Refresh the read-only inventory, then create and verify a restorable production
   backup. Rehearse on a disposable cloud copy with the final schema and backend.
2. Match accounts by Apple identity. The earlier audit implies 20 new accounts
   plus the 3 existing production accounts. Keep production account IDs for the
   2 overlapping people and map their beta-owned records to those IDs.
3. Check profile, email, daily Health, source, and record-ID collisions before
   importing. Preserve production history. Do not add together two copies of the
   same person's daily Steps or silently overwrite conflicting records.
4. Transfer related profiles, Fights, memberships, activity history, posts, and
   media using the same account/source mapping. Copy the actual stored files and
   update owner-dependent paths; database rows alone do not transfer file bytes.
5. Verify account and record counts, references, permissions, stored results, and
   file hashes. Test login and the changed API against the rehearsed data.
6. After Marc authorizes production, repeat the verified import with a fresh
   backup. Capture later beta writes through an agreed cutoff near public release;
   an early snapshot alone would miss activity during Apple's review.

Users should expect to sign in with the same Apple ID in the production app.
Existing beta sessions are not transferred. After the agreed cutoff, production
holds real history and staging remains independent for testing. This is a one-time
transition, not ongoing synchronization between the two environments.

Supabase documents [Auth migration and session validity](https://supabase.com/docs/guides/troubleshooting/migrating-auth-users-between-projects)
and [database and Storage transfer](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore).
The account merge and conflict handling above are FitFight-specific behavior,
covered by unit tests and the cloud rehearsal. A real Apple sign-in with the
production binary and final live cutover verification remain release checks.

After maintenance, the live audit confirmed three missing migrations. Notification
preferences/social kinds, Fight Realtime invalidations, and chart checkpoints were
applied and verified before the preview promotion. Six old timestamps were
corrected after verifying that their recorded SQL matched repository SQL apart
from whitespace. All 40 migration versions now match, and a subsequent migration-up
run applied nothing. This changed schema/history metadata in staging, not user
identities or beta data in production.

## Required order

1. Release PR #241 is merged into `develop` with database, native, and web checks
   passing. Current Health collection/privacy disclosures still need final review.
2. Staging schema is reconciled and #243 is merged into `preview` at `d97145a`.
   TestFlight upload run `35029178930` passed. Build `1.1.1 (201)` finished Apple
   processing and is assigned to Internal Tester and Friends Beta. Friends wait
   for beta review; verify the installed candidate before promoting production.
3. Rehearse account/history/media import and verify a recoverable backup.
4. Merge `preview` into `main`; apply compatible production migrations before the
   backend needs them, verify production settings, and complete the verified import.
5. Verify production `/api/health`, `/api/app-release`, Apple sign-in, Health sync,
   invitations, Feed/media, notifications, deletion, and both legal-page languages.
6. Let cloud CI upload the production candidate. Refresh screenshots' version/build
   labels, save both store localizations and privacy answers, select the build, and
   verify that the release endpoint admits it for review before submission.
7. Submit for Apple review. Release after approval using the approved manual-release
   setting. Keep staging for tests and production for real history.

Retiring build 113's database permissions is a separate rollout. Its missing update
dialog means API enforcement alone cannot prove direct database access is retired.

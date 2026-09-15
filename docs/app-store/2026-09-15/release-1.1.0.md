# FitFight 1.1.0 release

Marc authorized the production update and one-time beta data migration on
15 September 2026. PR creation still requires an explicit PR request under AGENTS.md.

## Prepared code and listing

- Marketing version and production upload workflow: `1.1.0`; CI allocates the build.
- New release note in English and French; existing icon is the intended beige FF on green.
- Six screenshots per language and an [HTML gallery](index.html).
- Updated [store copy](../metadata.md), [review notes](../review-notes.md), English/French
  privacy pages, and the native Photos or Videos privacy declaration.
- App Store Connect has a `1.1.0` draft. Screenshot upload, saved localized copy,
  candidate selection, privacy questionnaire, and submission remain pending.

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

Staging currently admits `1.0.0 (190)` for Friends and `1.0.0 (198)` for review/internal.
Existing `/api/v1` fixtures and 205 backend tests pass. No API version changes.
The new Auth/PostgREST test and native compile still need PR CI.

## Cloud rehearsal evidence, 15 September

Created temporary Supabase branch `release-1-1-rehearsal` with production data.
All 28 pending migrations applied successfully. Before and after: 3 Auth users,
3 profiles, 14 Fights, 14 memberships, and 0 storage objects. Transactional SQL
replayed build 113 profile update, Fight creation, invitation, acceptance, decline,
and read paths. Unauthorized score changes, joining as a stranger, and accepting
for another person were rejected. The test fixture was rolled back.

This verifies migration execution and database permissions on a production copy.
It does not verify signed-in iOS behavior, HTTP requests against the candidate
backend, beta data import, or live production readiness.

## One-time data migration

Read-only inventory: staging has 22 Auth users, 22 Fights, 73 memberships, and 47
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

The source import and storage transfer are not implemented or executed yet.
Staging's migration ledger contains several manually assigned timestamps that
differ from repository filenames, plus the social-notification migration is absent.
Reconcile schema and ledger before the next staging deployment.

## Required order

1. Open the release PR into `develop` when explicitly authorized; pass database,
   native, and web CI. Review the current Health collection/privacy disclosures.
2. Reconcile staging schema, deploy the compatible backend, and merge to `preview`
   for the staging TestFlight candidate. Verify the installed candidate.
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

# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **3 Sep 2026**. App: **1.0.0**.

Do **not** restore removed surfaces. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, notifications, social, or a broader marketing site unless [`backlog.md`](backlog.md) says so. Only the public privacy and support pages exist on the web.

---

## GitHub vs Supabase (the two pairs)

There are two **git** branches and two **hosted databases**. They line up.

| | Testing | Real users / App Store |
|---|---|---|
| GitHub | `develop` | `main` |
| TestFlight | any push that is **not** `main`, plus the daily scheduled `develop` build | never; `main` does not upload to TestFlight |
| Supabase | develop project (`zstzbf…`, version line says `staging`) | production (`pvqn…`, version line says `prod`) |
| What you do | Merge PRs **into `develop`**. Try the app. | Merge `develop` → `main` only when Marc says ship |

A feature PR is a third git branch. Merge it **into `develop`**. That updates the **staging** database (new SQL) and is the home for later chats.

Once configured, Vercel accepts small authenticated Apple Health aggregate requests and receives account-deletion commands. The phone sends Apple's merged Steps total for each exact Fight window, plus merged daily buckets only for the relevant Fight chart days. The phone still writes the temporary Fight/membership path directly to Supabase. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Before this branch ships

Apple Health synchronization requires `FITFIGHT_API_URL=https://staging.fitfight.app` plus Vercel's server-only Supabase URL/secret and pooled `DATABASE_URL`. Fresh Apple sign-in and automatic revocation also require the Vercel Sign in with Apple Team/key/private-key/client-ID values and stable token-encryption key. Configure those first; otherwise sign-in fails visibly. Do not expose schema `private`.

After the backend is configured, merge the feature PR into **`develop`**, not `main`. The staging migration must land before testing the new TestFlight build.

Verify the minimal product alongside Apple Health synchronization:

1. TestFlight → **Update**. Look for `1.0.0 · build N · staging · 3 Sep` at the top.
2. Check Fights, a Fight detail, New, and You in both Night and Day. There are only three tabs: Fights, New, You.
3. New accepts exact usernames, requires an action, and offers 1 hour / 6 hours / 1 day for testing plus 3 days / 1 week / 2 weeks / 1 month. **Start fight** shows Starting… and ignores extra taps. On staging, You → Try 10 layouts (or 1–10 on New) switches New-fight UX; each layout still starts the same fight.
4. Confirm sign-in, username, Apple Health Steps, Fight invitations, standings, Privacy, Support, Versions, sign out, and Delete account.
5. Confirm Requests, friend requests/lists, money, other Metrics, and dead settings are absent.
6. If sign-in fails: hosted **develop** Supabase → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

The native Fight path uses Supabase; Apple Health synchronization and account deletion also require Vercel.

---

## What this build does

| Surface | Status |
|---|---|
| Welcome + Apple sign-in | Works |
| Username onboarding | Works. Required once after sign-in. |
| Version line | Release-candidate TestFlight says `1.0.0 · build N · staging`; the App Store build says `prod` |
| Create Steps challenge | Add one or more exact usernames, choose 1 / 6 hours or 1 / 3 / 7 / 14 / 30 days, and type the required loser action. Steps × highest total is fixed. |
| Accept / Join | Phone updates your membership |
| Invite participants | Exact username in New. They must have signed in and chosen one. There is no friendship or friend-request layer, and at least one invitee is required. |
| Apple Health | Sends Apple's merged cumulative Steps total for each exact active/ending Fight window in one small authenticated request. It does not send raw samples, deletions, per-source totals, device/source metadata, anchors, or archives. |
| Daily totals | Sends Apple's merged daily buckets only for days relevant to active Fight charts. They are display data, not the source of the Fight score. |
| Standings | Live scoring uses exact Fight-window HealthKit aggregates, not overlapping whole-day totals. Both phones read the same serving rows. |
| Fight end | Exact `ends_at` is the final cutoff. Opening the app closes due fights; the protected Vercel cron runs daily if nobody opens it. After finalization, later Steps cannot change the result. |
| Tabs | Fights, New, You. Requests and Design are removed. |
| New fight layouts | Staging only. You → Try 10 layouts, or numbered chips on New. Ten UX versions of the same Steps form. Production stays on Current. |
| Look | Night/Day, Nunito, fixed Moss/Ember/Gold semantics; no accent picker or public design-system showcase. |
| Versions | Works under You → Settings; the version label stays at the top of every root screen. |
| Privacy / Support | Pages are implemented and linked under You → Settings. Staging uses `staging.fitfight.app`; production uses `fitfight.app`. Each route must be deployed before that build is tested or submitted. |
| Account deletion | Permanently deletes the profile, username, authentication, Health/Steps data, relationships, invitations, memberships, scores, and owned Fights; removes participation from other Fights; clears local Health sync state; and revokes a stored Apple credential when available. |
| WHOOP / Strava | Not built |
| Removed scope | No persistent friends, Requests, money/payouts, bragging-rights option, other Metrics, goals, custom dates, or dead settings/actions. |

---

## Honest limits

- The server accepts a signed-in User's device upload as their own activity. Fine for two friends; not anti-cheat yet.
- FitFight trusts Apple's current merged aggregate from the signed-in User's device. It does not retain the underlying raw samples or source/device provenance, so this is not an anti-cheat or audit trail.
- Apple may revise its merged total after a Watch sync, edit, or deletion. Live snapshots can change until the exact Fight-end value is finalized; chart buckets never overwrite that exact-window score.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` owns Apple Health aggregate ingestion and account deletion. There are no app-facing Postgres RPCs.

---

## Next product work

Two phones: invite by exact username, accept, run a 3-day Steps challenge, verify the typed action and matching standings, and confirm the Fight finishes at the cutoff. Also smoke-test creation for 7 / 14 / 30 days. Then App Store when Marc says.

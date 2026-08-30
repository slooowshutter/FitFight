# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **30 Aug 2026**. App: **0.9.0**. Git: `sports-health-data-apis`.

Do **not** invent screens for dead buttons. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, notifications, social, or the marketing site unless [`backlog.md`](backlog.md) says so.

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

Apple Health synchronization requires `FITFIGHT_API_URL=https://staging.fitfight.app` plus Vercel's server-only Supabase URL/secret and pooled `DATABASE_URL`. Configure those first; otherwise synchronization fails visibly. Do not expose schema `private`.

After the backend is configured, merge the feature PR into **`develop`**, not `main`. The staging migration must land before testing the new TestFlight build.

The branch also includes the design-system build already on `develop`. Verify it alongside the HealthKit changes:

1. TestFlight → **Update**. Look for `0.9.0 · build N · staging · 30 Aug` at the top.
2. Check Fights, a Fight detail, New, Requests, and You in both Night and Day.
3. You → Settings → **Design system** shows all twelve sections from the approved HTML kit.
4. New → **Start fight once**. The button shows Starting… and ignores extra taps while the insert runs.
5. Confirm existing sign-in, username, Apple Health, friends, and Steps standings still work.
6. If sign-in fails: hosted **develop** Supabase → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

The design-system changes themselves need no Vercel. This branch's Apple Health synchronization currently does.

---

## What this build does

| Surface | Status |
|---|---|
| Welcome + Apple sign-in | Works |
| Username onboarding | Works. Required once after sign-in. |
| Version line | TestFlight always says `0.9.0 · build N · staging`; future App Store builds say `prod` |
| Create Steps fight | Phone writes the fight to Supabase |
| Accept / Join | Phone updates your membership |
| Add friend / add to a fight | Username. They must have signed in and picked one. No request dance — add is enough. You can start alone. |
| Apple Health | Sends Apple's merged cumulative Steps total for each exact active/ending Fight window in one small authenticated request. It does not send raw samples, deletions, per-source totals, device/source metadata, anchors, or archives. |
| Daily totals | Sends Apple's merged daily buckets only for days relevant to active Fight charts. They are display data, not the source of the Fight score. |
| Standings | Live scoring uses exact Fight-window HealthKit aggregates, not overlapping whole-day totals. Both phones read the same serving rows. |
| Fight end | Exact `ends_at` is the final cutoff. Opening the app closes due fights; the protected Vercel cron runs daily if nobody opens it. After finalization, later Steps cannot change the result. |
| Design tab | Removed |
| Design system | Works under You → Settings. Night/Day, Nunito, fixed Moss/Ember/Gold semantics; no accent picker. |
| Versions | Works under You → Settings; the version label stays at the top of every root screen. |
| WHOOP / Strava | Not built |
| Dead buttons | Still dead (bell, share, Edit, Units & goals, Notifications, Privacy, Payouts, Requests New). Leave them. |

---

## Honest limits

- The server accepts a signed-in User's device upload as their own activity. Fine for two friends; not anti-cheat yet.
- FitFight trusts Apple's current merged aggregate from the signed-in User's device. It does not retain the underlying raw samples or source/device provenance, so this is not an anti-cheat or audit trail.
- Apple may revise its merged total after a Watch sync, edit, or deletion. Live snapshots can change until the exact Fight-end value is finalized; chart buckets never overwrite that exact-window score.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` owns Apple Health aggregate ingestion and account deletion. There are no app-facing Postgres RPCs.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then App Store when Marc says.

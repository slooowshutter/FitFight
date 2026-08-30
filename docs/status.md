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

Once configured, Vercel coordinates private HealthKit archives and receives account-deletion commands. Health data goes directly from the phone to one private Supabase Storage object, not through Vercel's request body. The phone still writes the temporary Fight/membership path directly to Supabase. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Before this branch ships

The HealthKit archive requires `FITFIGHT_API_URL=https://staging.fitfight.app` plus Vercel's server-only Supabase secret and pooled `DATABASE_URL`. Configure those first; otherwise coordination fails visibly and the HealthKit anchor stays unchanged. Do not expose schema `private` or grant clients general access to `provider-inbox`.

After the backend is configured, merge the feature PR into **`develop`**, not `main`. The staging migration must land before testing the new TestFlight build.

The branch also includes the design-system build already on `develop`. Verify it alongside the HealthKit changes:

1. TestFlight → **Update**. Look for `0.9.0 · build N · staging · 30 Aug` at the top.
2. Check Fights, a Fight detail, New, Requests, and You in both Night and Day.
3. You → Settings → **Design system** shows all twelve sections from the approved HTML kit.
4. New → **Start fight once**. The button shows Starting… and ignores extra taps while the insert runs.
5. Confirm existing sign-in, username, Apple Health, friends, and Steps standings still work.
6. If sign-in fails: hosted **develop** Supabase → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

The design-system changes themselves need no Vercel. This branch's HealthKit archive currently does.

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
| Apple Health | Writes every accessible raw Steps sample/change/deletion, merged daily total, per-source daily statistic, exact active/ending Fight aggregate, provenance, and final checkpoint into one protected NDJSON archive. TUS resumes transfer of the same private object. The active HealthKit anchor advances only after processing and object deletion complete. |
| Daily totals | Today is provisional. The first complete post-midnight sync freezes yesterday; a historical day imported later arrives frozen. Later provider corrections stay private and do not rewrite the served total. |
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
- Raw HealthKit samples and source statistics are self-only and never returned to Fight peers; peers receive merged totals only for their shared Fight dates.
- A complete encoded archive must stay at or below 512 MiB. Raw events are processed in bounded batches; oversize archives are rejected without truncation or anchor advancement.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` owns HealthKit ingestion and account deletion. There are no app-facing Postgres RPCs.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then App Store when Marc says.

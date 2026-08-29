# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **29 Aug 2026**. App: **0.9.0**. Git: `sports-health-data-apis`.

Do **not** merge `develop` → `main` until Marc says ship to production. Do **not** invent screens for dead buttons. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, notifications, social, or the marketing site unless [`backlog.md`](backlog.md) says so.

---

## GitHub vs Supabase (the two pairs)

There are two **git** branches and two **hosted databases**. They line up.

| | Testing | Real users / App Store |
|---|---|---|
| GitHub | `develop` | `main` |
| TestFlight | any push that is **not** `main` | only builds from `main` |
| Supabase | develop project (`jldjgf…`, version line says `staging`) | production (`pvqn…`, version line says `prod`) |
| What you do | Merge PRs **into `develop`**. Try the app. | Merge `develop` → `main` only when Marc says ship |

A feature PR is a third git branch. Merge it **into `develop`**. That updates the **staging** database (new SQL) and is the home for later chats.

Once configured, Vercel receives private HealthKit batches and account-deletion commands. The phone still writes the temporary Fight/membership path directly to Supabase. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Before this branch ships

The HealthKit archive requires the staging API URL plus Vercel's server-only Supabase secret and pooled `DATABASE_URL`. Configure those first; otherwise the app intentionally skips archival uploads. Do not expose schema `private` through the Data API.

After the backend is configured, merge the feature PR into **`develop`**, not `main`. The staging migration must land before testing the new TestFlight build.

---

## What this build does

| Surface | Status |
|---|---|
| Welcome + Apple sign-in | Works (develop / staging) |
| Username onboarding | Works. Required once after sign-in. |
| Version line | `0.9.0 · build N · staging · 25 Aug` |
| Create Steps fight | Phone writes the fight to Supabase |
| Accept / Join | Phone updates your membership |
| Add friend / add to a fight | Username. They must have signed in and picked one. No request dance — add is enough. You can start alone. |
| Apple Health | Reads Apple's merged total for scoring. On first archive it sends all accessible raw Steps samples, deletion tombstones, merged daily totals, per-source daily statistics, and provenance to the authenticated TypeScript backend; later syncs use a HealthKit anchor. |
| Standings | Sum of uploaded days in the fight window. Both phones read the same rows. |
| Fight end | If `ends_at` is past, the app marks it finished when someone opens it. No cron. |
| Design tab | Removed |
| WHOOP / Strava | Not built |
| Dead buttons | Still dead (bell, share, Edit, Settings rows, Requests New). Leave them. |

---

## Honest limits

- The server accepts a signed-in User's device upload as their own activity. Fine for two friends; not anti-cheat yet.
- Raw HealthKit samples and source statistics are self-only and never returned to Fight peers; peers receive merged totals only for their shared Fight dates.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` owns HealthKit ingestion and account deletion. There are no app-facing Postgres RPCs.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then Marc can say ship (`develop` → `main`).

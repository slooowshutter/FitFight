# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **25 Aug 2026**. App: **0.9.0**. Git: PR **#30** → `develop`.

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

A feature PR (like #30) is a third git branch. Merge that **into `develop`**. That updates the **staging** database (new SQL) and is the home for later chats.

You do **not** need Vercel or a cron job for the first real fight. The phone writes fights and steps to Supabase. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Merge this PR?

**Yes — merge #30 into `develop`.** Wait a minute for the new SQL to land on staging. Then TestFlight → **Update**.

**Do not merge into `main`.**

If you Update before the merge, Start fight / upload can fail (the new tables are not on staging yet).

---

## After you merge (only you)

1. GitHub: merge #30 into **`develop`**. Not `main`.
2. TestFlight → **Update**. Look for `0.9.0 · build N · staging` at the top.
3. Sign in. Pick a **username**. That’s how friends find you.
4. You → Apple Health (allow Steps). You → Friends: copy your username, add theirs.
5. If sign-in fails: Supabase **develop** → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.
6. Friends: TestFlight → Internal Testing → their emails. Same build. Their own Apple IDs (they are staging users). Then a 3-day Steps fight.

No Vercel. No cron secret. No “expose schema private”.

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
| Apple Health | Reads Apple's merged total for scoring. On first archive it backfills all accessible raw Steps samples, deletion tombstones, merged daily totals, per-source daily statistics, and provenance; later syncs use a HealthKit anchor. |
| Standings | Sum of uploaded days in the fight window. Both phones read the same rows. |
| Fight end | If `ends_at` is past, the app marks it finished when someone opens it. No cron. |
| Design tab | Removed |
| WHOOP / Strava | Not built |
| Dead buttons | Still dead (bell, share, Edit, Settings rows, Requests New). Leave them. |

---

## Honest limits

- Anyone can write **their own** step rows. Fine for two friends. Not anti-cheat.
- Raw HealthKit samples and source statistics are self-only and never returned to Fight peers; peers receive merged totals only for their shared Fight dates.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` Next.js API is still in the repo for later. Not required on the phone now.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then Marc can say ship (`develop` → `main`).

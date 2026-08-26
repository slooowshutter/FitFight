# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **26 Aug 2026**. App: **0.9.0**. Git: #30 is on `develop`. TestFlight **0.9.0 (53)** uploaded from that merge.

Do **not** merge `develop` → `main` until Marc says ship to production. Do **not** invent screens for dead buttons. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, notifications, social, or the marketing site unless [`backlog.md`](backlog.md) says so.

---

## GitHub vs Supabase (the two pairs)

There are two **git** branches and two **hosted databases**. They line up. Full map: [`environments.md`](environments.md).

| | Testing | Real users / App Store |
|---|---|---|
| GitHub | `develop` | `main` |
| TestFlight | any push that is **not** `main` | only builds from `main` |
| Supabase | develop project (`jldjgf…`, version line says `staging`) | production (`pvqn…`, version line says `prod`) |
| What you do | Merge PRs **into `develop`**. Try the app. | Merge `develop` → `main` only when Marc says ship |

The first real fight does **not** wait on Vercel: the phone writes fights and steps to Supabase. Opening the app closes a fight whose days are up. Standings are a comparison of those rows.

Marc wants Vercel on. The Next.js API lives in `web/`. It is not live until he creates the Vercel project (see [`next.md`](next.md)). After `FITFIGHT_API_URL` is set, TestFlight calls that server. Preview must use the **develop** Supabase project, never production.

You still do **not** paste `sb_secret_...` anywhere.

---

## On the phone (only you)

1. TestFlight → **Update**. Look for `0.9.0 · build N · staging`.
2. Sign in. Pick a **username**. That’s how friends find you.
3. You → Apple Health (allow Steps). You → Friends: copy your username, add theirs.
4. New → 3d → Start a Steps fight (alone is fine).
5. If sign-in fails: Supabase **develop** → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.
6. Friends: TestFlight → Internal Testing → their emails. Same build. Their own Apple IDs (they are staging users). Then a 3-day Steps fight.

Vercel is the next server step (`web/`). Not required to start a fight today.

---

## What this build does

| Surface | Status |
|---|---|
| Welcome + Apple sign-in | Works (develop / staging) |
| Username onboarding | Works. Required once after sign-in. |
| Version line | `0.9.0 · build N · staging · d MMM` |
| Create Steps fight | Phone writes the fight to Supabase. Starts **now**, not tomorrow. |
| Accept / Join | Phone updates your membership. Detail standings refresh on that screen. |
| Add friend / add to a fight | Username. They must have signed in and picked one. No request dance — add is enough. You can start alone. |
| Apple Health | Reads today. Uploads last 31 days to `step_days`. Failed upload shows on You. |
| Standings | Sum of uploaded days in the fight window (N-day chip = N days). Both phones read the same rows. |
| Fight end | If `ends_at` is past, the app marks it finished when someone opens it. No cron. |
| Design tab | Removed |
| WHOOP / Strava | Not built |
| Dead buttons | Still dead (bell, share, Edit, Settings rows, Requests New). Leave them. |

---

## Honest limits

- Anyone can write **their own** step rows. Fine for two friends. Not anti-cheat.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` Next.js API is still in the repo for later. Not required on the phone now.
- Fight windows use the phone’s calendar, not `fights.time_zone`. Fine for two people in the same place.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then Marc can say ship (`develop` → `main`).

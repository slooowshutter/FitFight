# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **29 Aug 2026**. App: **0.9.0**. Git: SwiftUI design-system branch → `develop` (staging).

Do **not** invent screens for dead buttons. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, notifications, social, or the marketing site unless [`backlog.md`](backlog.md) says so.

---

## GitHub vs Supabase (the two pairs)

There are two **git** branches and two **hosted databases**. They line up.

| | Testing | Real users / App Store |
|---|---|---|
| GitHub | `develop` | `main` |
| TestFlight | any push that is **not** `main` | only builds from `main` |
| Supabase | develop project (`zstzbf…`, version line says `staging`) | production (`pvqn…`, version line says `prod`) |
| What you do | Merge PRs **into `develop`**. Try the app. | Merge `develop` → `main` only when Marc says ship |

A feature PR (like #30) is a third git branch. Merge that **into `develop`**. That updates the **staging** database (new SQL) and is the home for later chats.

You do **not** need Vercel or a cron job for the first real fight. The phone writes fights and steps to Supabase. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Try the design-system build on staging

1. TestFlight → **Update**. Look for `0.9.0 · build N · staging · 29 Aug` at the top.
2. Check Fights, a Fight detail, New, Requests, and You in both Night and Day.
3. You → Settings → **Design system** shows all twelve sections from the approved HTML kit.
4. New → **Start fight once**. The button shows Starting… and ignores extra taps while the insert runs.
5. Confirm existing sign-in, username, Apple Health, friends, and Steps standings still work.
6. If sign-in fails: hosted **develop** Supabase → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

No Vercel. No cron secret. No “expose schema private”.

---

## What this build does

| Surface | Status |
|---|---|
| Welcome + Apple sign-in | Works |
| Username onboarding | Works. Required once after sign-in. |
| Version line | `0.9.0 · build N · prod` on main builds; `staging` on the rest |
| Create Steps fight | Phone writes the fight to Supabase |
| Accept / Join | Phone updates your membership |
| Add friend / add to a fight | Username. They must have signed in and picked one. No request dance — add is enough. You can start alone. |
| Apple Health | Reads today. Uploads last 31 days to `step_days`. |
| Standings | Sum of uploaded days in the fight window. Both phones read the same rows. |
| Fight end | If `ends_at` is past, the app marks it finished when someone opens it. No cron. |
| Design tab | Removed |
| Design system | Works under You → Settings. Night/Day, Nunito, fixed Moss/Ember/Gold semantics; no accent picker. |
| Versions | Works under You → Settings; the version label stays at the top of every root screen. |
| WHOOP / Strava | Not built |
| Dead buttons | Still dead (bell, share, Edit, Units & goals, Notifications, Privacy, Payouts, Requests New). Leave them. |

---

## Honest limits

- Anyone can write **their own** step rows. Fine for two friends. Not anti-cheat.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` Next.js API is still in the repo for later. Not required on the phone now.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then App Store when Marc says.

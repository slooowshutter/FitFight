# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **26 Aug 2026**. App: **0.9.0**. Git: **#32** merged `develop` → `main` (production).

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

## After #32 (production — only you)

1. TestFlight → **Update**. Look for `0.9.0 · build N · prod` at the top.
2. Sign in. Pick a **username** if you have not. That’s how friends find you.
3. You → Apple Health (allow Steps).
4. New → **Start fight once**. Wait until Fights shows it. Extra copies from mashing Start are leftover test rows.
5. Confirm your steps show on the fight. Alone is fine.
6. If sign-in fails: hosted **production** Supabase → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

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
| WHOOP / Strava | Not built |
| Dead buttons | Still dead (bell, share, Edit, Settings rows, Requests New). Leave them. |

---

## Honest limits

- Anyone can write **their own** step rows. Fine for two friends. Not anti-cheat.
- Same Apple ID on production vs staging is **two** accounts.
- `web/` Next.js API is still in the repo for later. Not required on the phone now.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then App Store when Marc says.

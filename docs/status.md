# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **28 Aug 2026**. App: **0.9.0**. Staging host `zstzbf…`. Production is **#32** (`develop` → `main`).

Do **not** invent screens for notifications, payouts, or request threads. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, social, or the marketing site unless [`backlog.md`](backlog.md) says so.

---

## GitHub vs Supabase (the two pairs)

There are two **git** branches and two **hosted databases**. They line up.

| | Testing | Real users / App Store |
|---|---|---|
| GitHub | `develop` | `main` |
| TestFlight | any push that is **not** `main` | only builds from `main` |
| Supabase | develop project (`zstzbf…`, version line says `staging`) | production (`pvqn…`, version line says `prod`) |
| What you do | Merge PRs **into `develop`**. Try the app. | Merge `develop` → `main` only when Marc says ship |

A feature PR is a third git branch. Merge that **into `develop`**. That updates the **staging** database (new SQL) and is the home for later chats.

You do **not** need Vercel or a cron job for the first real fight. The phone writes fights and steps to Supabase. Opening the app closes a fight whose days are up. Standings are a comparison of rows already in the database.

You still do **not** paste `sb_secret_...` anywhere.

---

## Stuck on “Loading your account”?

The old staging host is gone. A leftover sign-in, or a missing `profiles` row, left the phone with no way out.

**Merge this PR into `develop`.** Then TestFlight → **Update**. If it still says it couldn’t load: **Sign out** → Sign in with Apple. Do not merge to `main`.

---

## After this TestFlight (staging)

1. TestFlight → **Update**. Look for `0.9.0 · build N · staging · 28 Aug` at the top (this PR is not `main`).
2. Sign in. Pick a **username** if you have not.
3. You → Apple Health. Allow Steps. Tap **Sync now**. You should see today and the last 31 days.
4. New → **Start fight once**. Pull Fights to refresh. Steps should land on the card.
5. Fight detail **share** / **i challenge you** opens the system share sheet. Invite **Accept** on the list accepts in place.
6. You → **Edit** changes your name. Finished fights show under Fight history.

No Vercel. No cron secret. Do not merge to `main` unless Marc says ship.

---

## What this build does

| Surface | Status |
|---|---|
| Welcome + Apple sign-in | Works. Stuck load has Try again + Sign out. |
| Username onboarding | Works. Asks Apple Health on Continue. |
| Version line | `0.9.0 · build N · staging` on this PR; `prod` only on `main` |
| Create Steps fight | Phone writes the fight. Active Minutes / Workout Count are disabled. |
| Accept / Join | Phone updates your membership. List Accept accepts in place. |
| Add friend / add to a fight | Username. They must have signed in and picked one. You can start alone. |
| Apple Health | You → Apple Health: today, last sync, 31-day history, Sync now. Uploads to `step_days`. Writes `data_sources`. Syncs on open and on pull-to-refresh. |
| Standings | Sum of uploaded civil days in `[start, end)`. Money line is computed from those scores. |
| Fight share | System share sheet. |
| Fight history | Finished fights on You and on Fights. W/L is real. Empty state if none. |
| Fight end | If `ends_at` is past, the app marks it finished when someone opens it. No cron. |
| Edit / Privacy | Edit name + username. Privacy says what we store. Sign out / Delete. |
| Requests | Talk to the boss and New both email Marc. No fake vote board on a live phone. |
| Design tab | Removed |
| WHOOP / Strava | Not built |
| Hidden (no fake tap) | Bell, Units & goals, Notifications, Payouts |

---

## Honest limits

- Anyone can write **their own** step rows. Fine for two friends. Not anti-cheat.
- Same Apple ID on production vs staging is **two** accounts.
- HealthKit does not say if permission was denied. Empty reads say “No accessible data”.
- No background HealthKit delivery yet. Open the app (or Sync now) to upload.
- Money is informal. You settle up yourselves. No payouts in the app.
- `web/` Next.js API is still in the repo for later. Not required on the phone now.

---

## Next product work

Two phones, 3-day Steps fight, standings match, fight shows finished after the days. Then App Store when Marc says.

# FitFight status — what works, what’s fake, what’s next

Read this before building. Last updated **25 Aug 2026**. App on TestFlight: **0.9.0 (50)**. Git: PR **#30** (`cursor/live-steps-fight-ffad` → `develop`). Phone after Update talks to **Supabase develop** (`staging` on the version line). Production Supabase is only for git **`main`**.

Do **not** merge `develop` → `main` until Marc says ship to production. Do **not** invent screens for dead buttons. Do **not** build WHOOP, Strava, Active Minutes, Workout Count, payments, notifications, social, or the marketing site unless [`backlog.md`](backlog.md) says so.

---

## Merge this PR?

**Yes — merge #30 into `develop`.** It is the live Steps Fight + welcome + develop wiring. After merge, later chats branch off `develop` instead of this long PR.

**Do not merge `develop` into `main`.** That is App Store / production Supabase. The product is not proven on two phones yet.

---

## What works on the phone (after Update to 0.9.0 (50))

| Surface | Real? | Notes |
|---|---|---|
| Welcome (signed out) | **Yes** | FitFight title, one line, Sign in with Apple. Tabs hidden until signed in. |
| Sign in with Apple | **Yes** (develop) | Creates a `profiles` row on **develop**. Same Apple ID as production is a **new** user. |
| Sign out / Delete account | **Yes** | You → those rows. |
| Version at top | **Yes** | `0.9.0 (n) · staging · 25 Aug`. Versions under You → Settings. |
| Design tab | **Yes** | 11 Fights layouts. Preview data is **fixtures**. `original` follows You → Look. |
| You → Look | **Yes** | Dark/light + accents (tokens). |
| You → Data sources → Apple Health | **Local read** | Today’s Steps from HealthKit on this phone. Empty = “No accessible data”. Tap asks Health permission. Upload is skipped (no API). |
| You stats / history | **Wired, usually empty** | Reads real memberships on develop. Not Leo/Sam. Empty until a fight exists in the DB. |
| Fights tab | **Wired, usually empty** | Same. Empty is correct — fixtures only show in the Design tab / screenshots. |
| Add friend by handle (New) | **Code is live; unproven** | Writes `friendships` straight to develop Supabase. Needs the other person already signed in on **this** project. Does **not** need Vercel. |
| Requests → Talk to the boss | **Yes** | Opens Mail to `marc@marclamy.com`. |
| Requests vote board | **Local only** | Votes stay on this phone. Row tap does nothing (no thread). |

---

## What does **not** work yet (the big hole)

**The server API is not live.** CI never got a Vercel URL (`FITFIGHT_API_URL` empty). The app’s `APIConfig.baseURL` is **nil**. So:

- **Create fight / invite / accept via API** — code is in the app + `web/`, but the phone has nowhere to POST.
- **HealthKit upload** — local read works; **upload to the database is skipped** until the API URL exists.
- **Standings from the server** — scoring math exists in `web/` with tests. Nothing writes scores until ingest + API run.
- **Fight closer / cron** — `POST /api/internal/close-fights` exists. Needs Vercel + `CRON_SECRET`. Opening the app can also sync due fights **once the API exists**.

Until Marc puts `web/` on Vercel (develop env = develop Supabase **secret**), Steps are **not** pooled in the cloud. Two phones cannot share a real fight.

On the phone, **Start fight** and **Accept / Join** will show a red error: `FitFight API is not configured`. That is expected until the Vercel URL is compiled into the next TestFlight.

---

## Connectors

| Source | Status |
|---|---|
| Apple Health / HealthKit **Steps** | **Read on device: yes.** Upload: **no** (no API). Only this source is on You. |
| WHOOP | Not built. Not even a row. Backlog / later. |
| Strava | Not built. Not even a row. Backlog / later. |
| Active Minutes / Workout Count | New can select them. **Start stays Steps-only** (“Steps only for now”). |
| Apple Health **write** / other Health types | Not in scope. |

---

## Buttons and screens that do nothing (design kit)

These are **on purpose** until Marc asks. Do not invent the missing screen.

| Where | What | Why |
|---|---|---|
| Fights | Bell | No notification inbox. |
| Fight detail | Share / “i challenge you” | No share sheet / deep link. |
| New | Active Minutes / Workout Count | Selectable in the kit. Start is Steps-only. |
| Requests | New | No compose. |
| You | Edit | No profile editor. |
| You → Settings | Units & goals | No screen. |
| You → Settings | Notifications | No APNs / prefs. |
| You → Settings | Privacy | No screen. |
| You → Settings | Payouts | No wallet. Stakes copy is informational. |

Money on fight cards is **not** a wallet.

---

## After you merge #30 (Marc only)

1. GitHub: merge the PR into **`develop`**. Do not merge to **`main`**.
2. Supabase **develop**: Apple provider **On**, client ID `com.fitfight.mvp` (if sign-in ever fails).
3. **Vercel**: import the repo, root **`web/`**. Preview/`develop` env = develop Supabase URL + **secret**. Production env = main project. Never paste `sb_secret_...` in chat. Send the agent the `https://….vercel.app` URL so the next ship can set `FITFIGHT_API_URL`.
4. Supabase develop **Data API**: expose schema **`private`** (needed for `metric_observations`).
5. Vercel: `CRON_SECRET` on Preview + Production (fight closer).
6. TestFlight → Internal Testing → friends’ emails. Same build. They sign in with **their** Apple IDs (staging users).

Agents cannot `workflow_dispatch`. After the API URL is in CI, the next **app** push uploads TestFlight by itself. Open TestFlight → **Update**.

---

## After Vercel (next product work)

Proof: **two phones**, 3-day **Steps** fight, standings from the database, fight **closes** after `ends_at` (open the app or wait for cron). Then Marc can say ship (`develop` → `main`) and App Store.

Until that proof, do not submit the fixture-only app to the store.

---

## Already in the repo (do not rebuild)

- `web/` Next.js `/api/v1`: Apple Health connect, HealthKit batches, create/invite/accept/start/cancel, `POST /fights/sync-due`, cron closer.
- Scoring: highest_total, proportional, hit_your_goal. Clock tests with fake `now` (1 / 3 / 7 / 14 days). Steps after `ends_at` do not count. 24h grace then final.
- iOS never writes fights, scores, or `private.metric_observations` itself.
- Non-`main` TestFlight → develop Supabase. `main` → production.
- Welcome gate when signed out.

---

## Rules that stay

- Marketing version stays **0.9.0** until Marc says bump. CI only bumps the **build** number.
- Every user-facing ship: `Changelog.swift` row (reuse 0.9.0) + **Last TestFlight** in `backlog.md`.
- No `supabase db reset` / destructive SQL on hosted unless Marc asked and the file starts with `-- allow-destructive`.
- New `.swift` files go in `project.pbxproj`. Tokens only — no hardcoded colours.

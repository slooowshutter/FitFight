# Who uses what

Two worlds. **Staging** (we try it). **Production** (real users / App Store).

There is only **one** TestFlight app. The top line says `staging` or `prod`. Same Apple ID on both is **two** accounts.

Do **not** make one Supabase branch per Cursor chat. Preview DBs cost money (max **3**). The phone cannot switch URL per conversation — the URL is compiled into the build.

---

## The two worlds

| | Staging (try it) | Production (ship) |
|---|---|---|
| GitHub | `develop` | `main` |
| Your phone | TestFlight, line says **staging** | TestFlight from `main`, or App Store, line says **prod** |
| Supabase | develop project `jldjgf…` | production `pvqn…` |
| Vercel | Preview + the `develop` deploy | Production deploy (`main` only) |
| Keys | develop publishable + develop secret | production publishable + production secret |
| GitHub variable for the API | `FITFIGHT_API_URL` | `FITFIGHT_API_PRODUCTION_URL` |

`cursor/…` chats are **not** a third world. They are drafts that want to become `develop`.

---

## GitHub

- `cursor/…` — one conversation’s PR. Merge **into `develop`**.
- `develop` — staging. You tap merge. Agents do not, unless you said so.
- `main` — production. You merge `develop` → `main` when V1 is real. Never before.

Two chats at once is fine for **Swift**. It is **not** fine for two SQL PRs that both change the same tables. One schema PR at a time. Merge it before the next.

---

## Supabase

Two **projects**, not three. Ignore extra names.

| Project | When it changes |
|---|---|
| develop (`jldjgf…`) | After you merge a PR **into GitHub `develop`** |
| production (`pvqn…`) | After you merge GitHub `develop` → `main` |

SQL in a `cursor/…` PR is tested in GitHub CI (fake Postgres). It is **not** on hosted develop until you merge.

**The mismatch you felt:** a TestFlight from this PR already has the **new app**. It still talks to **old develop** tables until you merge. So: merge #31, wait a minute, then Update. Then app and DB match.

Supabase “preview branches” (auto, max 3) are extra copies when `supabase/` changes. We do **not** point TestFlight at those. Too many keys. Too expensive. Skip them for V1.

---

## Vercel (you create this)

Ignore Vercel’s “Development” tab. That is a laptop. We do not use it.

| Vercel | Git | Database |
|---|---|---|
| Production | `main` | production Supabase |
| Preview (every other git branch, including `develop` and `cursor/…`) | that branch | **develop** Supabase — never production |

You do **not** invent a special preview branch. Vercel makes a Preview URL for each push. We do not put those Preview URLs in the iPhone. Too many.

The phone uses **two** URLs you set once in GitHub:

| GitHub variable | What you paste |
|---|---|
| `FITFIGHT_API_URL` | The stable **develop** Vercel URL (Production Branch `develop`, or a `*.vercel.app` you keep for staging) |
| `FITFIGHT_API_PRODUCTION_URL` | The Production Vercel URL (`main`) — empty until you ship |

Env **inside** Vercel (dashboard, never chat):

| Name | Preview + develop | Production |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | `jldjgf…` | `pvqn…` |
| `SUPABASE_SECRET_KEY` | develop secret | production secret |
| `CRON_SECRET` | random string | random string |

Root Directory: `web/`. Production branch: `main`.

Vercel’s folder picker uses the **git branch you selected on Import**. `web/` is on `develop` (and on feature PRs). It is **not** on `main` until you ship. If you only see `FitFight`, `docs`, `supabase` — switch the import branch to **`develop`**, then pick `web`.

Until those GitHub variables are set, the phone writes straight to Supabase. That is OK for V1.

---

## TestFlight vs App Store

| Build from | Top line | Database | Vercel API |
|---|---|---|---|
| PR or `develop` | `staging` | develop | `FITFIGHT_API_URL` (or none) |
| `main` | `prod` | production | `FITFIGHT_API_PRODUCTION_URL` (or none) |

Apple has one app ID. Staging and prod are **different backends**, not two App Store listings.

---

## Keys (who holds what)

| Key | Where | In the iPhone? |
|---|---|---|
| Supabase **publishable** | GitHub vars + compiled `BuildEnv` | Yes. Safe-ish. |
| Supabase **secret** | Vercel + hosted dashboard only | **Never.** |
| `CRON_SECRET` | Vercel only | **Never.** |
| Apple `.p8` | GitHub Actions secrets (already) | **Never.** |

CI writes `FitFight/Generated/BuildEnv.swift` at archive time. Empty API URL = phone talks to Supabase only.

---

## V1 (Marc’s definition)

People create a fight, add friends, run a Steps challenge.

**Already there** (staging, after #30; #31 makes the 3-day window honest):

- Sign in with Apple, username
- Add friend by username
- Start a Steps fight (alone is fine)
- Apple Health → upload steps
- Standings from the database

**You do:** merge #31 → Update → two phones, 3 days. Then Vercel when you want the server. Then `develop` → `main` when you say ship.

**Not V1:** WHOOP, Strava, money, pushes, social, company credits, stickers. Dead buttons (bell, share, Edit, Requests New) stay dead or we hide them — we do not invent those screens. Apple Health is the connector for V1.

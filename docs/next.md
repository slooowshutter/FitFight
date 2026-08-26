# Next

Who uses what: [`environments.md`](environments.md). You want **Vercel**. Keep it. The last chat wrote “no Vercel” after the no-cron turn. That was the agent, not you.

The phone already works **without** Vercel (it writes to Supabase). Vercel is the **server**: close fights if nobody opens, write `private.metric_observations`, later pushes. Code is in `web/`. Nothing is deployed until you create the project.

Do **not** merge `develop` → `main`.

## Now (phone, 5 min)

1. TestFlight → **Update**. `0.9.0 (56)` is this PR’s build. Or merge [#31](https://github.com/slooowshutter/FitFight/pull/31) into `develop` first, then Update again.
2. Sign in. Pick a **username**.
3. You → Apple Health. Copy your username. Add a friend the same way.
4. New → **3d** → Start fight (alone is fine).

If sign-in fails: Supabase **develop** → Authentication → Providers → Apple → On, client ID `com.fitfight.mvp`.

## Then (Vercel — only you can do this)

In the Vercel site (not Apple/GitHub docs):

1. New project → this GitHub repo (`slooowshutter/FitFight` or `marclelamy/FitFight`).
2. Import branch: **`develop`** (not `main`). `web/` is not on `main` yet.
3. **Root Directory:** `web/`
4. Later, set Production branch to `main`. Preview / `develop` stays on staging keys.
4. Env (dashboard only — never paste in chat or git):

| Name | Preview + `develop` | Production (`main`) |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | develop project URL (`jldjgf…`) | production (`pvqn…`) |
| `SUPABASE_SECRET_KEY` | develop secret | production secret |
| `CRON_SECRET` | long random string | same or different |

5. Deploy. Copy the **staging / develop** URL (looks like `https://….vercel.app`).
6. GitHub → this repo → Settings → Secrets and variables → Actions → Variables → `FITFIGHT_API_URL` = that URL (no trailing slash).

Then tell this chat “Vercel URL is in the GitHub variable.” Next TestFlight will call the server. Do not paste the secret key here.

Hobby cron may run once a day. Opening the app still closes a due fight.

## After you try the fight

New conversation. Point it at this file, then [`status.md`](status.md). Proof: two phones, standings match, fight shows finished after the days.

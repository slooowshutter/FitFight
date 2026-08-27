# Backend

Empty platform first. Feature code later. Production Metric is **Steps**. Phone vs server status: [`status.md`](status.md). The phone may write its own fights, memberships, and `step_days`. It still cannot write `private.metric_observations`.

[`system-design.md`](system-design.md) is the golden guide. This folder is the first slice of it, not the whole thing. Do not add Active Minutes, Workout Count, WHOOP, Strava, payments, notifications, social, or a website until the backlog says so.

Hosted production (no secrets): https://pvqntpteehdvhqyctwum.supabase.co  
Hosted staging / git `develop` (no secrets): https://zstzbfocunthczzubggz.supabase.co

## Loop

A cloud agent writes SQL in `supabase/migrations` and tests in `supabase/tests`, then opens a PR **into `develop`**. Marc merges that. The persistent Supabase branch `develop` picks it up. Production only changes when Marc merges `develop` → `main`. Agents do not get the database password or `sb_secret_...` key, and they do not merge unless Marc asked.

GitHub-hosted **Ubuntu** (not a Mac) runs `supabase db start`, lints the schema, runs pgTAP as `authenticated`, and rejects `DROP TABLE` / `TRUNCATE` / `DROP COLUMN` unless the **first line** of the file is exactly `-- allow-destructive`. This Linux cloud VM has no Docker, so agents do not run the stack here.

iOS TestFlight is unchanged and still ignores this folder. iOS simulator and screenshot jobs skip when the PR does not touch the app.

## GitHub Integration fields

In the project: **Project Settings → Integrations → GitHub**.

| Field | Value |
| --- | --- |
| GitHub repository | `marclelamy/FitFight` (same repo as `slooowshutter/FitFight`) |
| Working directory | `.` |
| Deploy to production | On |
| Production branch | `main` |
| Automatic branching | On |
| Branch limit | `3` (preview branches cost extra; do not raise this) |
| Supabase changes only | On |

Then **Enable integration**. Do not paste a secret key, `service_role` key, or database password into GitHub. Those are legacy for this loop. Deploys go through the GitHub app, not a key in Actions.

GitHub branches:

| GitHub branch | Meaning | Hosted database |
| --- | --- | --- |
| Feature (`cursor/…`) | One piece of work | Preview (only if `supabase/` changed, max 3) |
| `develop` | Staging / testing | Persistent Supabase branch named **`develop`** |
| `main` | Production | The main project |

In **Branching**, create one long-lived branch named **`develop`** (not `staging`). It tracks the GitHub `develop` branch. Feature PRs merge into `develop`. When Marc wants production, he merges `develop` into `main`.

## So an agent cannot nuke production

- Production changes only by merging `develop` into `main`. Agents open PRs into `develop`. They do not merge unless Marc said so in that chat.
- CI refuses destructive SQL (`DROP TABLE`, `DROP SCHEMA`, `TRUNCATE`, `DROP COLUMN`) unless Marc approved it and the **first line** of the migration is exactly `-- allow-destructive`.
- Agents never receive `sb_secret_...`, the old `service_role` JWT, or the database password. Never put those in git, chat, or iOS.
- Never run `supabase db reset`, `supabase db push`, or `DROP DATABASE` against the hosted project.
- Prefer additive migrations (expand → migrate → contract).
- Keep the preview branch limit at 3.

Marc’s extra lock (GitHub ruleset **Protect main**): target **`main` and `develop`** → require a pull request, required approvals **0**, require status check **Migrations and RLS**, block force pushes. That stops a push onto either branch without the database check. You still tap merge. You cannot approve your own PR, which is why approvals stay at 0.

## Commands (CI, or any machine with Docker)

```bash
python3 scripts/forbid-destructive-sql.py
npx supabase@2.115.0 db start
npx supabase@2.115.0 db lint --local --schema public,private --fail-on error
npx supabase@2.115.0 test db --local
```

Pin the CLI to **2.115.0** until you mean to bump it (`config.toml` was generated with that version).

The iOS publishable key (`sb_publishable_...`) production fallback lives in `FitFight/SupabaseConfig.swift`. The secret key is not.

TestFlight binaries that are **not** built from `main` talk to the develop project. CI writes `FitFight/Generated/BuildEnv.swift` before archive. GitHub variables `SUPABASE_STAGING_*` override if set; otherwise the known develop URL and publishable key are compiled in. `main` uses the production URL/key plus `FITFIGHT_API_PRODUCTION_URL`. See [`shipping.md`](shipping.md). What is live on the phone: [`status.md`](status.md).

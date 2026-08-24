# Backend

Empty platform first. Feature code later. Production Metric is **Steps**.

[`system-design.md`](system-design.md) is the golden guide. This folder is the first slice of it, not the whole thing. Do not add Active Minutes, Workout Count, WHOOP, Strava, payments, notifications, social, or a website until the backlog says so.

## Loop

A cloud agent writes SQL in `supabase/migrations` and tests in `supabase/tests`, then opens a PR.

GitHub-hosted **Ubuntu** (not a Mac) runs `supabase db start`, lints the schema, and runs pgTAP. That is the proof the database works. This Linux cloud VM has no Docker, so agents do not run the stack here.

iOS TestFlight is unchanged and still ignores this folder. iOS simulator and screenshot jobs skip when the PR does not touch the app.

## Marc, once

On the phone: supabase.com → New project → name **FitFight** → region **East US (North Virginia)**. Then tell the agent “project is up.” Do not paste the database password or the secret key.

Later, same dashboard: turn on Branching and connect this GitHub repo. Keep one long-lived branch named `staging`. Production is the main project.

## Commands (CI, or any machine with Docker)

```bash
npx supabase@2.115.0 db start
npx supabase@2.115.0 db lint --local --schema public,private --fail-on error
npx supabase@2.115.0 test db --local
```

Pin the CLI to **2.115.0** until you mean to bump it (`config.toml` was generated with that version).

## Secrets (after the hosted project exists)

Names only. Never print values. Never put them in git or chat.

| Secret | What it is |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Personal access token so CI can link the project |
| `SUPABASE_PROJECT_ID` | Production project ref |
| `SUPABASE_DB_PASSWORD` | Production database password |
| Staging branch ids/passwords | Only after the persistent `staging` branch exists |

The iOS publishable key is client configuration. The secret/service key is not.

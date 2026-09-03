# Backend

Production Metric is **Steps**. Phone vs server status: [`status.md`](status.md). The phone may temporarily write its own fights and memberships. For Apple Health, it asks HealthKit for Apple's merged cumulative total over each exact Fight window and sends those totals to authenticated `POST /api/v1/healthkit/steps`. Staging also sends daily statistics and workout, sleep, and mindful summaries to `POST /api/v1/healthkit/collection`; that path never writes Fight scores. It may also send Apple's merged daily Steps buckets for the active Fight days needed by charts; those buckets never determine the Fight score. The backend validates the User, Fight membership, server-issued windows and cutoffs, then stores the exact-window snapshots and updates standings in a TypeScript-owned Postgres transaction. There are no app-facing database RPCs.

[`system-design.md`](system-design.md) is the golden guide. This folder is the first slice of it, not the whole thing. Do not add Active Minutes, Workout Count, WHOOP, Strava, payments, notifications, social, or a website until the backlog says so.

Hosted production (no secrets): https://pvqntpteehdvhqyctwum.supabase.co  
Hosted staging / git `develop` (no secrets): https://zstzbfocunthczzubggz.supabase.co

## Loop

A cloud agent writes SQL in `supabase/migrations` and tests in `supabase/tests`, then opens a PR **into `develop`**. Marc merges that. The persistent Supabase branch `develop` picks it up. Production only changes when Marc merges `develop` → `main`. Agents do not get the database password or `sb_secret_...` key, and they do not merge unless Marc asked.

GitHub-hosted **Ubuntu** (not a Mac) runs `supabase db start`, lints the schema, runs pgTAP as `authenticated`, exercises the TypeScript database transactions, and rejects `DROP TABLE` / `TRUNCATE` / `DROP COLUMN` unless the **first line** of the file is exactly `-- allow-destructive`. This Linux cloud VM has no Docker, so agents do not run the stack here.

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

Vercel holds `DATABASE_URL`, using Supavisor transaction mode on port `6543`, separately for develop and production. It is a server-only database password and never belongs in GitHub, chat, or iOS. `private` stays absent from the Data API's exposed schemas.

Vercel also holds the server-only Supabase URL and secret used to authenticate requests and perform reviewed admin operations. Neither value belongs in iOS or chat.

Native Sign in with Apple sends its short-lived authorization code to authenticated
`POST /api/v1/auth/apple`. The server exchanges it with Apple, checks the returned Apple
subject against the User's Supabase Apple identity, encrypts the refresh token, and stores
it in `private.apple_sign_in_tokens`. Vercel holds the Sign in with Apple Team ID, key ID,
private `.p8`, client ID, and a separate 32-byte encryption key. `DELETE /api/v1/me`
loads any revocation token, removes pending private Storage objects, deletes Fights owned by
the User, removes the User from other Fights, and hard-deletes the full auth account before
making a bounded Apple revocation request. Apple cannot block FitFight deletion. Legacy
accounts without a stored Apple token still delete; the app gives the manual Apple Settings
disconnect path.

`GET /api/v1/provider-uploads/context` temporarily remains the context route and returns the server time plus exact live/awaiting-final-sync Fight windows. `POST /api/v1/healthkit/steps` accepts one strict JSON document with `complete_through`, the User's `time_zone`, `merged_days`, and `fight_aggregates`. `fight_aggregates` are Apple's merged cumulative totals from each server-authoritative `starts_at...cutoff_at` interval and are the only input to standings. `merged_days` are limited to relevant active Fight days and serve charts only. The request contains no raw sample, deletion, per-source statistic, device/source metadata, anchor, NDJSON, object path, or upload capability.

`POST /api/v1/healthkit/diagnostics` overwrites one latest private operational snapshot for the authenticated User. It stores only stable capability, trigger, error, app-version, and synchronization timestamps; it stores no device identifier, free-form error, raw HealthKit data, or event history. Fight peers can read only `fight_members.final_steps_complete`, which becomes true monotonically when the selected source's `complete_through` reaches the exact Fight end.

The older one-object archive migrations, `private.provider_uploads` / `private.provider_events` tables, `provider-inbox` bucket, archive contract, and provider-upload create/status/process routes remain legacy infrastructure during the additive rollout so older builds and migration history are not rewritten. The aggregate-only sync does not create new archive rows or Storage objects and does not use TUS. Remove that legacy surface separately only after incompatible TestFlight builds no longer need it.

Every TestFlight binary talks to the develop project. The workflow rejects `main`, and the daily scheduled build explicitly checks out `develop`. CI writes `FitFight/Generated/BuildEnv.swift` before archive. GitHub variables `SUPABASE_STAGING_*` override if set; otherwise the known develop URL and publishable key are compiled in. Production configuration belongs only to the future App Store flow. See [`shipping.md`](shipping.md). What is live on the phone: [`status.md`](status.md).

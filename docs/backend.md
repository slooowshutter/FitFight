# Backend

Production Metric is **Steps**. Phone vs server status: [`status.md`](status.md). The phone may temporarily write its own fights and memberships. For HealthKit, it writes one complete NDJSON archive to a protected local file and uploads that one object directly to the private `provider-inbox` bucket with TUS. The authenticated Next.js API authorizes the exact object, downloads and verifies it, then uses one TypeScript-owned Postgres transaction to archive raw `add`/`change`/`delete` events, canonical observations, frozen daily values, and exact Fight-window aggregates. It deletes the object before acknowledging completion. There are no app-facing database RPCs, and the phone cannot list, read, download, or delete private objects or archive rows.

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

Vercel also holds the server-only Supabase URL and secret used for Storage signing/download/deletion. Storage bucket `provider-inbox` is private, limited to **512 MiB per object**, accepts `application/x-ndjson`, and grants authenticated clients no general object permissions. `POST /api/v1/provider-uploads` returns a short-lived signed TUS capability for exactly `USER_UUID/UPLOAD_UUID/archive.ndjson`; replacement is disabled. The 4.5 MB Vercel request-body limit is irrelevant because the archive never passes through a request body.

One UUID-v4 `upload_id` identifies the authorization, Storage object, processing lease, retries, and replayable receipt. The app saves its candidate HealthKit anchor only after the upload reaches `completed`, meaning Postgres committed and the Storage object was deleted. A `committed` upload retries cleanup without rewriting Postgres; a missing object during cleanup counts as already deleted. Large archives are validated without retaining every decoded raw event, then reread into bounded database batches. Archives over 512 MiB fail visibly and leave the active anchor unchanged.

The public coordination contract is [`contracts/openapi.yaml`](../contracts/openapi.yaml); each archive line follows [`provider-archive-v1.json`](../contracts/schemas/provider-archive-v1.json). Version 1 is UTF-8 with one strict JSON object and one LF per line. Record discriminators are `sample` (`add` or `change`), `deletion` (`delete`), `merged_day`, `source_day`, and `fight_aggregate`, followed by exactly one final `checkpoint`. The archive contains no upload envelope: `upload_id`, expected bytes, and expected SHA-256 belong to the coordination row.

Coordination endpoints are small:

- `GET /api/v1/provider-uploads/context` returns server time and exact live/awaiting-final-sync Fight windows.
- `POST /api/v1/provider-uploads` creates or replays the row and signed TUS capability.
- `POST /api/v1/provider-uploads/{uploadID}/process` verifies, commits, cleans up, and returns the receipt.
- `GET /api/v1/provider-uploads/{uploadID}` recovers state or the completed receipt after an app restart or lost response.

States are `issued → processing → committed → completed`, with `rejected` and `retryable_failure` alternatives. Safe error codes may be shown/retried; internal error detail and secrets are never returned.

Every TestFlight binary talks to the develop project. The workflow rejects `main`, and the daily scheduled build explicitly checks out `develop`. CI writes `FitFight/Generated/BuildEnv.swift` before archive. GitHub variables `SUPABASE_STAGING_*` override if set; otherwise the known develop URL and publishable key are compiled in. Production configuration belongs only to the future App Store flow. See [`shipping.md`](shipping.md). What is live on the phone: [`status.md`](status.md).

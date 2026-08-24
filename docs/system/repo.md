# Repo and rollout

Keep **`FitFight/` and `FitFight.xcodeproj` at the repo root.** A prettier `apps/ios` moves pbxproj, Fastlane, three macOS workflows, and every agent’s memory. Not worth it.

## Target tree

```
/
  FitFight/  FitFight.xcodeproj/  fastlane/   # unchanged
  apps/web/                                   # Next.js, Vercel root dir
  packages/contracts/                         # Zod + JSON Schema snapshots
  supabase/migrations/  supabase/config.toml
  docs/system/                                # this design
  package.json  pnpm-workspace.yaml           # JS only
```

pnpm workspaces: `apps/*`, `packages/*`. Xcode is not a workspace package. No Nx.

`docs/design` tokens stay dual-copied with `FitFight/DesignSystem`. Do not invent `packages/tokens` until web consumes them.

## Contracts

v1: **Zod is source of truth. Swift is hand-mirrored Codable. Commit JSON Schema + example JSON.** Linux agents can dump schema; they cannot compile generated Swift into pbxproj.

Wire for Vercel `/api/v1`: camelCase. PostgREST: snake_case. One mapper on iOS.

Same PR when a payload changes: Zod + snapshot + Swift + route.

Codegen when there are two production decode failures or ~25 objects.

`packages/db`: committed `supabase gen types` output so CI typecheck does not need a live project.

## CI

Keep existing macOS iOS jobs. Add Ubuntu:

- `supabase db reset` + `db lint` on `supabase/**`
- `pnpm` lint/typecheck on `apps/web` + `packages/**`

Tighten path filters so docs-only PRs do not eat `macos-26`. A Zod-only PR **must not** upload TestFlight; it **should** compile iOS if Swift mirrors changed.

Vercel deploys web itself. Do not add `vercel deploy` to GHA.

TestFlight concurrency `cancel-in-progress: false` stays.

## Migrations

Timestamped SQL. Never edit a file already on `main`. RLS in the same file as `CREATE TABLE`. Default deny.

Expand/contract: TestFlight users lag. Add nullable columns; drop later. Do not `NOT NULL` without a backfill and a shipped writer.

Two Supabase projects (**staging + prod**) before any real fight data. Preview never gets prod service role. One project is only acceptable while everything is still fixtures.

## Flags

Table `feature_flags`. First keys: `ff.fights.live_backend`, `ff.health.upload`, `ff.pokes.send`. Fail **closed** for writes. Marc flips rows in Table Editor. Not LaunchDarkly. Not the Design tab.

Ship the flag **before** the feature.

## Env

Gitignore `.env`, `.vercel`, `*.p8`. Commit `.env.example` names only.

iOS: Debug → staging URL; Release → prod. Anon key in the IPA is expected.

Cloud agents: no prod service role in the VM. SQL files + CI `db reset`. Marc still does Apple capabilities and new GitHub secrets.

## Marc’s loop once this exists

App change → TestFlight Update (staging backend).

Web/SQL change → Vercel preview / staging. Do not wait for TestFlight.

Do not ask him to run `supabase start` or Xcode.

## Build order

1. `supabase/migrations` + RLS + flags
2. `packages/contracts` + ingest route that writes samples and no-ops settle
3. iOS Sign in with Apple + repositories still on fixtures
4. Live GET fights behind `ff.fights.live_backend`
5. HealthKit upload
6. Crons: nudge + settle
7. Invite landing + AASA
8. Report/block before any new UGC (pokes)

## Explicitly later

Staging as a hard gate the day fight data is real (two Supabase projects). Swift OpenAPI. Playwright. Stripe. `apps/ios` rename. GraphQL. Social feed. Friends table.

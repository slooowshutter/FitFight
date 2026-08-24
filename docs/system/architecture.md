# Architecture

## Duty split

```
                    iPhone
         HealthKit / Sign in with Apple
           │                │            │
    anon+JWT reads    JWT ingest      APNs
           ▼                ▼            ▲
     ┌───────────┐    ┌───────────┐      │
     │ Supabase  │◄───│  Vercel   │──────┘
     │ Auth      │    │ /api/v1/* │
     │ Postgres  │    │ /api/cron │
     │ Realtime  │    │ /i /s     │
     │ Storage   │    │ privacy   │
     └───────────┘    └───────────┘
```

| Owner | Owns | Does not own |
| --- | --- | --- |
| **Supabase** | Rows, RLS, sessions, avatars, live standings wire | Settlement math, Strava tokens in a client-visible table, APNs |
| **Vercel** | Ingest, dedup, recompute, crons, outbox drain, public HTTP, admin | Long-term file storage, being the iOS read cache |
| **iOS** | UI, HK read, L4 SwiftData, upload queue | Rank, pot, freeze, “today” in the fight zone |

## HTTP surface (Vercel)

All `/api/v1/*` (except webhooks and cron) require `Authorization: Bearer <supabase_jwt>`. User id is the token `sub`, never a body field.

| Method | Path | Job |
| --- | --- | --- |
| POST | `/api/v1/ingest/healthkit` | L0 samples → canonical → fight days |
| POST | `/api/v1/ingest/strava/pull` | Server fetches Strava with stored refresh token |
| GET/POST | `/api/v1/webhooks/strava` | Hub verify; enqueue fetch (200 in <2s) |
| POST | `/api/v1/sources/strava/oauth/start` | Auth URL |
| POST | `/api/v1/sources/strava/oauth/finish` | Store encrypted tokens |
| DELETE | `/api/v1/sources/strava` | Revoke |
| GET | `/api/v1/sources` | You-tab rows |
| POST | `/api/v1/fights` | Create fight + members (trusted rules) |
| POST | `/api/v1/fights/:id/accept` | Invitee accepts |
| POST | `/api/v1/fights/:id/decline` | |
| POST | `/api/v1/sync/wake` | After nudge; `{ ingestRecommended }` |
| POST | `/api/v1/devices` | APNs token upsert |
| POST | `/api/v1/invites/:token/claim` | Authenticated join |
| GET | `/api/cron/settle` | See cron table |
| GET | `/api/cron/nudge-sync` | |
| GET | `/api/cron/outbox` | |
| GET | `/api/cron/roll-series` | Later |
| GET | `/api/cron/strava-refresh` | |
| GET | `/api/cron/apns-gc` | |

Reads of fights/standings/requests can go **PostgREST** under RLS so Realtime and GET share one shape. Create/accept/ingest stay on Vercel so the client cannot set `buy_in_cents` after the fact or write `fight_member_days`.

Idempotency: `Idempotency-Key` on ingest (client run id). Unique `(user_id, source, external_id)` on samples.

## Cron catalog

Assume **Vercel Pro**. Hobby cannot run minute jobs. Crons run only on **production** deployments of each project (prod and staging are two Vercel projects).

Protect `/api/cron/*` with `Authorization: Bearer ${CRON_SECRET}`.

| Job | Cadence (UTC) | Claim |
| --- | --- | --- |
| Settle | `* * * * *` | `live/settling` → `settling` with `FOR UPDATE SKIP LOCKED`; unique `fight_settlements(fight_id)` |
| Sync nudge | `* * * * *` | Unique outbox key `(fight_id, ends_at, kind)` |
| Outbox drain | `* * * * *` | Backup if DB webhook is down |
| Roll series | `*/5 * * * *` | When series exists; unique `(series_id, window_start)` |
| Strava refresh | `*/30 * * * *` | Tokens expiring within 90 min |
| APNs GC | `15 4 * * *` | 410 Unregistered |

Nudge and settle are **two jobs**. First nudge at `ends_at` (`kind=sync_nudge`). Second nudge at `ends_at + 2h` if that member has not synced (`kind=sync_nudge_2`). Settle when `now >= settle_at` (`ends_at + 6h`) **or** every accepted member has a qualifying sync after `ends_at`.

`maxDuration` 60–120s. Batch `LIMIT 50`. Never “select all live fights.”

Do **not** also schedule the same work with `pg_cron`.

## Realtime

Publish only:

- `fights` (status, name — not a health dump)
- `fight_members`
- `fight_member_days_read` (totals, **no** `audit` jsonb)
- `request_votes` / `requests`
- `boss_messages` (RLS: own thread)

Never publish: `metric_samples`, `connection_secrets`, `ingest_batches`, `device_tokens`, `push_outbox`, `user_reports`.

Subscribe **per fight** `fight:{id}`, not to the whole standings table. Invited-not-accepted: RLS hides day values (see [privacy.md](privacy.md)).

Soft-delete members (`left_at`) rather than DELETE — Realtime DELETE does not apply RLS.

## Public web

Origin: `https://fitfight.app` (prod), staging host separate.

| Route | Job |
| --- | --- |
| `/privacy` `/support` | App Store URLs |
| `/i/{token}` | Invite teaser: names, metric, length, bragging vs money **exists**. No live scores. Universal Link or App Store. |
| `/s/{campaign}` | Sticker QR later. UTM only. |
| `/.well-known/apple-app-site-association` | `/i/*`, `/f/*`, later `/s/*` |

Anon peek is an RPC `peek_invite(token)`, not `SELECT * FROM fights`.

## Secrets

| Secret | iOS | Vercel Preview | Vercel staging/prod | GitHub Actions |
| --- | --- | --- | --- | --- |
| Supabase URL + anon | yes | staging | matching project | no |
| `SERVICE_ROLE` | **never** | **never** | matching project | **never** |
| APNs `.p8` | never | never | yes | no (different from ASC `.p8`) |
| Strava secret | never | never | yes | never |
| `CRON_SECRET` | never | unused | yes | no |
| ASC API `.p8` | never | never | never | yes (already) |

Boot check on trusted routes: if `VERCEL_ENV === 'preview'` → 503. If URL is prod project and env is not production → 503.

## Environments

Two Supabase projects, two Vercel productions (`main` → prod, `staging` branch → staging). iOS Debug / PR TestFlight → staging. App Store → prod.

Today every app push goes to TestFlight. Once a backend exists, **PR builds must point at staging** or a TestFlight from a random PR writes junk into real fights.

## Outbox (pushes)

Insert `push_outbox` in the **same transaction** as the state change (nudge, settle, invite). Worker claims `pending → sending`. Retry 429/5xx. 410 drops the device token.

Outbox payload is a **template kind** + names. The worker does not look up `standings.score` to “make the alert nicer.”

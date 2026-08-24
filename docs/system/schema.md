# Schema

Postgres is the system of record. Migrations live in `supabase/migrations/` when we implement (not this PR). This file is the target shape.

Rules:

- UUID PKs. Human `code` on fights is a label, unique, not a secret.
- `timestamptz` everywhere. Civil `date` only for fight-local days.
- Money: `integer` cents. Metrics: `bigint` in canonical units (see [types.md](types.md)).
- RLS on from `CREATE TABLE`. Default deny.
- Clients do not `INSERT` samples or days. Vercel service role does.
- No `pot` column. No English copy columns.

## Enums

```text
metric_kind          steps | active_minutes | workouts | weight_kg
sample_source        healthkit | strava | scale | manual
stake_kind           bragging | money | action
settlement_kind      winner | proportional | goal
fight_lifecycle      scheduled | live | settling | settled | cancelled
member_status        invited | accepted | declined | left | expired
obligation_status    open | payer_marked | confirmed | written_off
request_kind         feature | bug
request_status       open | planned | shipped
```

`weight_kg` exists so dual/scale later does not need a new enum dance. Unused in v1. If used, store **grams** in `bigint` (`value`); the enum name is the metric, not the unit.

## Tables (logical groups)

### Identity

**`profiles`** — PK = `auth.users.id`

- `handle` citext unique, 3–20, `^[a-z][a-z0-9._]{2,19}$`
- `display_name`, `initials`, `avatar_path`
- `timezone` IANA — **profile default**, not a live fight’s zone
- `role` `user | staff`
- `deleted_at` tombstone
- `settle_hint` nullable, self/staff only (Venmo handle later — no screen yet)

Trigger on `auth.users` insert creates a stub profile. Handle claimed via RPC.

**`handle_history`** — old handles reserved 90 days.

**`reserved_handles`** — `marc`, `fitfight`, `support`, `admin`, …

### Sources

**`connections`** — `(user_id, provider)` unique. `status`, `last_sync_at`, `cursor` jsonb (HK anchor metadata / Strava after). No tokens.

**`connection_secrets`** — service role only. Encrypted refresh/access. HK has no row.

### Evidence (private)

**`ingest_batches`** — `(user_id, client_batch_id)` unique. Retry = no-op.

**`metric_samples`** — append-only L0/L1.

- `source`, `external_id`, unique `(user_id, source, external_id)`
- `metric`, `value` (canonical), `started_at`, `ended_at`
- `fingerprint` for cross-source match (no unique — two real runs an hour apart)
- `duplicate_of`, `excluded_reason` (`duplicate | source_policy | invalid`)
- **No** GPS, HR, route, title, raw vendor JSON in v1

Canonical rows: `duplicate_of IS NULL AND excluded_reason IS NULL`.

### Fights

**`fights`**

- `code` `FIGHT-` + 6 Crockford chars (not 3 digits)
- `name`, `metric`, `created_by`
- `timezone` **frozen** IANA
- `starts_on` / `ends_on` dates in that zone; `starts_at` / `ends_at` timestamptz (`ends_at` exclusive midnight after last day)
- `settle_at` = `ends_at + 6 hours`
- `length_days` generated
- `stake_kind`, `settlement_kind` (null if bragging), `buy_in_cents`, `currency` default USD
- `forfeit_text` if action
- `daily_goal` if goal mode
- `recipe_version` int (scoring recipe; freeze uses `algorithm_version` on the settlement row)
- `series_id` uuid **no FK** until series table exists
- `subject_user_id` nullable (dual later)
- `sponsor_key` nullable (credits later)

Checks: action cannot be proportional; money buy-in 500–10000; bragging buy-in 0.

Money/metric/window **immutable after insert** (trigger). Status moves via Vercel.

**`fight_members`**

- unique `(fight_id, user_id)`
- `status`, `invited_by`, timestamps
- `daily_goal` override nullable (UI is still shared)
- `last_sync_at`, `last_sample_at` — nudge targeting
- `buy_in_cents_snapshot` copied at accept

**`fight_member_days`** — L3. PK `(fight_id, user_id, day_index)`.

- `day_date`, `value`, `computed_at`
- `audit` jsonb (sample ids) — **not** granted to `authenticated`

A view `fight_member_days_read` drops `audit`. Realtime uses the view’s table or a slim replica.

### Settlement

**`fight_settlements`** — PK `fight_id`. `algorithm_version`, `pot_cents`, `accepted_count`, `settled_at`, `input_hash`.

**`fight_settlement_lines`** — per accepted member: score, rank, `buy_in_cents`, `payout_cents`, `net_cents`, `hit_goal`, `outcome`.

**`obligations`** — pairwise after freeze. `kind` money|action, `amount_cents`, `action_text`, `status`.

**`obligation_events`** — append-only acknowledgements. No UI yet; API can exist.

### UGC / ops

**`requests`**, **`request_votes`** PK `(request_id, user_id)`, **`request_comments`** (no client insert until compose exists).

**`boss_messages`** — `user_id` is the customer thread; `side` user|boss.

**`user_blocks`**, **`user_reports`**.

**`device_tokens`**, **`push_outbox`**. Device upsert goes through `POST /api/v1/devices` (Vercel). Authenticated SELECT own tokens only — no client INSERT. No `push_events` table; outbox status is enough.

**`invite_tokens`** — unguessable, `fight_id`, expiry, `claimed_by`. Peek RPC for the web teaser.

**`feature_flags`** — `key`, `enabled`, `payload`, `min_ios_build`.

**`sync_runs`** — ingest observability; no sample payloads in logs.

## Stored vs computed

| Fact | Where |
| --- | --- |
| Daily fight values | Stored L3 |
| Rank, today, projected net | Computed (view or Vercel), same `settle()` |
| Pot | `buy_in × accepted_count` |
| `days_left`, kickers, “Ended Jul 13” | Client L5 |
| Vote counts | `count(*)` |
| You-tab W/L / $ won | Sum of settlement lines |

## RLS (sketch)

`anon`: peek invite RPC only.

`authenticated`:

| Table | SELECT | Write |
| --- | --- | --- |
| `profiles` | public view of **self + people you share a fight with** (minus blocked). Handle search is an RPC with prefix + limit, not `SELECT *` | self via RPC for handle |
| `fights` | member (any status) | none |
| `fight_members` | fellow members; **no** `last_sync_at` (view exposes `live/stale/missing` only) | accept/decline self via RPC/Vercel |
| `fight_member_days_read` | **accepted** members of that fight | none |
| `fight_settlements/_lines` | **accepted** members (receipt after freeze) | none |
| `metric_samples` | **none** to clients (You-tab uses `/sources`) | none |
| `connections` | own metadata | none |
| `connection_secrets` | none | none |
| `requests` / votes | all authenticated minus blocks | vote self; insert request only when compose ships |
| `boss_messages` | own thread | insert `side=user` |
| `device_tokens` | own | none (Vercel upsert) |
| `obligations` | party to the row | mark paid via RPC later |

Service role: ingest, recompute, settle, push, delete-account.

Invited-not-accepted: can SELECT fight **metadata** and member **names**, not day values. The mock that shows a live board on an invite is a leak — do not API it.

## Indexes worth having

- `metric_samples (user_id, ended_at)`
- `fights (lifecycle, settle_at)` partial live/settling
- `fight_members (user_id, status)`
- unique samples `(user_id, source, external_id)`
- unique outbox `dedupe_key`

## Later, without new product tables now

| Later | Hook |
| --- | --- |
| Recurring | `fights.series_id` |
| Dual / scale | `subject_user_id`, `weight_kg` |
| Sponsor credits | `sponsor_key` + future `credit_ledger` |
| Pokes | blocks/reports exist; `pokes` table when the screen exists |
| Social posts | separate bounded context, not a fight column |
| Friendships | still no |

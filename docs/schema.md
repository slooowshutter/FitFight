# Postgres schema — FitFight

Law for the **server** database. The phone replica is a read model (`cache_*`);
do not clone this ERD onto the device. No Supabase Auth, Storage, Realtime, or
RLS-as-the-lock. Postgres stays private behind an API we own.

The mock `Fight` struct in `AppModel` is a **view model**. Lifting it into
tables is the original sin: `pot`, `projectedNet`, kickers, `daysLeft`, and
`status == invited` are not facts.

---

## Critique of the fixture shape

| Mock field | If you store it | What actually is |
| --- | --- | --- |
| `Fight.id` = `"sweat"` / `code` = `FIGHT-742` | Sequential codes are guessable; string ids leak into FKs | UUID PK + `public_code` (Crockford). Never sequential. |
| `Fight.status` invited/live/finished | **Viewer-relative.** You are invited; the fight is live | Fight lifecycle ≠ membership status |
| `pot`, `buyIn` as display dollars | Stale pot after join (already a Requests bug) | Buy-in frozen on membership; pot = Σ accepted buy-ins |
| `score: Double`, `dailyGoal: Double` | Proportional 60% will not replay | `bigint` milli-units |
| `projectedNet`, `rank`, `daysLeft` | Diverges from settlement | API projection using `rules_version` |
| `kicker*`, `payoutLine`, `listSubtitle` | Copy changes, data doesn't | Format at the edge |
| `Standing.invited` on a fight row | Mixed people who don't score into the board SoT | Membership `invited` until accept |
| No timezone | “Day 3” disagrees across friends | IANA tz **frozen** on the fight; civil dates in that tz |
| History `net` as a person field | Can't explain who owes whom | Directed IOU obligations + ledger |

Health: the phone compiles **daily totals** and uploads those. Raw HealthKit
samples, GPS, HR, sleep never enter this database. “Samples” below means
**accepted fight-day quantities**, not HK rows. Weight stays off-server until
dual-challenge ships and legal says otherwise.

---

## Conventions

- PK `uuid` default `gen_random_uuid()`. `public_code` is not a PK.
- Money: `amount_minor bigint` (cents). `currency char(3)` default `'USD'`. Never `numeric`/`float`.
- Metrics: `value_milli bigint` = quantity × 1000 in the metric’s unit (step, minute, workout, gram).
- Timestamps: `timestamptz`. Civil days: `date` in the **fight** timezone.
- Closed statuses: `CREATE TYPE` (append values only, never rename). Product-volatile vocab: `text` + `CHECK`.
- App-layer authz. Optional RLS later is belt, not the lock.
- Integer `rules_version` on every fight; settlement is a pure function of that version.

---

## Bounded contexts (Postgres schemas)

| Schema | Owns |
| --- | --- |
| `core` | Users, SIWA, sessions, devices, blocks, commands, idempotency, events, outbox |
| `fights` | Series, fights, members, invites, day scores, settlements |
| `health` | Ingest batches, day quantities, provenance (fight-scoped, not a warehouse) |
| `ledger` | Accounts, transactions, entries, IOU obligations |
| `social` | Pokes, reports |
| `feedback` | Product requests, votes, comments |
| `orgs` | Sponsor orgs (empty in v1, FK-ready) |

---

## DDL

```sql
-- PostgreSQL 16+. No extra extensions required.
CREATE SCHEMA core;
CREATE SCHEMA fights;
CREATE SCHEMA health;
CREATE SCHEMA ledger;
CREATE SCHEMA social;
CREATE SCHEMA feedback;
CREATE SCHEMA orgs;

-- ─── enums (append-only) ───────────────────────────────────────────
CREATE TYPE core.session_status AS ENUM ('active', 'revoked');
CREATE TYPE core.outbox_status AS ENUM ('pending', 'sending', 'sent', 'failed', 'dead');
CREATE TYPE core.apns_env AS ENUM ('sandbox', 'production');

CREATE TYPE fights.fight_shape AS ENUM ('race', 'dual', 'sponsored_race');
CREATE TYPE fights.fight_status AS ENUM (
  'scheduled', 'live', 'grace', 'settling', 'settled', 'cancelled'
);
CREATE TYPE fights.stake_kind AS ENUM ('none', 'money_iou', 'action', 'credit');
CREATE TYPE fights.settlement_kind AS ENUM ('winner', 'proportional', 'goal');
CREATE TYPE fights.member_status AS ENUM (
  'invited', 'accepted', 'declined', 'left', 'forfeited', 'kicked'
);
CREATE TYPE fights.member_role AS ENUM ('racer', 'challenger', 'backer');
CREATE TYPE fights.dual_miss_policy AS ENUM ('refund_backers', 'challenger_pays');
CREATE TYPE fights.invite_status AS ENUM (
  'pending', 'accepted', 'declined', 'expired', 'revoked'
);
CREATE TYPE fights.score_day_status AS ENUM ('open', 'frozen');

CREATE TYPE health.ingest_status AS ENUM ('accepted', 'rejected', 'applied');
CREATE TYPE health.provider AS ENUM ('healthkit', 'strava', 'connected_scale');

CREATE TYPE ledger.account_kind AS ENUM (
  'user_iou', 'fight_clearing', 'sponsor_pool', 'system'
);
CREATE TYPE ledger.tx_kind AS ENUM (
  'stake_commit', 'stake_release', 'fight_settle',
  'iou_waive', 'iou_off_platform', 'sponsor_grant', 'sponsor_redeem'
);
CREATE TYPE ledger.entry_dir AS ENUM ('debit', 'credit');
CREATE TYPE ledger.obligation_status AS ENUM ('open', 'waived', 'paid_off_platform');

CREATE TYPE social.poke_kind AS ENUM ('encourage', 'discourage');

CREATE TYPE feedback.request_kind AS ENUM ('feature', 'bug');
CREATE TYPE feedback.request_status AS ENUM ('open', 'planned', 'shipped');

-- ─── metric catalogue (row, not enum: weight is an INSERT) ─────────
CREATE TABLE fights.metric_defs (
  kind        text PRIMARY KEY,          -- steps | active_minutes | workouts | mass
  unit        text NOT NULL,             -- step | min | workout | g
  scale       integer NOT NULL DEFAULT 1000
    CHECK (scale > 0)
);
INSERT INTO fights.metric_defs (kind, unit) VALUES
  ('steps', 'step'),
  ('active_minutes', 'min'),
  ('workouts', 'workout'),
  ('mass', 'g');                         -- unused until dual-challenge

-- ═══════════════════════════════════════════════════════════════════
-- core
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE core.users (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handle          text NOT NULL,          -- display @maya.moves; user-typed
  display_name    text NOT NULL,
  avatar_url      text,
  iana_timezone   text NOT NULL DEFAULT 'Europe/Paris', -- reminders only; fights freeze their own
  locale          text NOT NULL DEFAULT 'en',
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deleted_at      timestamptz,            -- tombstone; keep numbers on boards
  CHECK (handle ~ '^[a-z0-9._]{2,30}$')
);
CREATE UNIQUE INDEX users_handle_alive ON core.users (lower(handle))
  WHERE deleted_at IS NULL;

-- Apple sub is identity, not the PK (transfer / team change / tombstone).
CREATE TABLE core.apple_identities (
  user_id           uuid PRIMARY KEY REFERENCES core.users (id),
  apple_sub         text NOT NULL UNIQUE,
  email             text,                 -- often Hide My Email; not unique, not login
  is_private_email  boolean NOT NULL DEFAULT false,
  first_seen_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.devices (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES core.users (id),
  apns_token      text UNIQUE,            -- nullable until permission
  apns_env        core.apns_env NOT NULL DEFAULT 'production',
  bundle_id       text NOT NULL DEFAULT 'com.fitfight.mvp',
  created_at      timestamptz NOT NULL DEFAULT now(),
  last_seen_at    timestamptz NOT NULL DEFAULT now(),
  disabled_at     timestamptz             -- APNs Unregistered / logout
);
CREATE INDEX devices_user ON core.devices (user_id) WHERE disabled_at IS NULL;

CREATE TABLE core.sessions (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid NOT NULL REFERENCES core.users (id),
  device_id           uuid REFERENCES core.devices (id),
  refresh_token_hash  bytea NOT NULL,
  status              core.session_status NOT NULL DEFAULT 'active',
  created_at          timestamptz NOT NULL DEFAULT now(),
  expires_at          timestamptz NOT NULL,
  revoked_at          timestamptz,
  last_seen_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX sessions_user_active ON core.sessions (user_id)
  WHERE status = 'active';

CREATE TABLE core.blocks (
  blocker_id  uuid NOT NULL REFERENCES core.users (id),
  blocked_id  uuid NOT NULL REFERENCES core.users (id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

-- Client command UUID = idempotency key (create fight, accept, vote, poke).
CREATE TABLE core.commands (
  id            uuid PRIMARY KEY,         -- client-supplied
  user_id       uuid NOT NULL REFERENCES core.users (id),
  type          text NOT NULL,
  body          jsonb NOT NULL,
  request_hash  bytea,
  result        jsonb,
  applied_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX commands_user_applied ON core.commands (user_id, applied_at DESC);

-- HTTP POSTs that are not commands (rare); commands.id covers the rest.
CREATE TABLE core.idempotency_keys (
  user_id          uuid NOT NULL REFERENCES core.users (id),
  scope            text NOT NULL,
  key              text NOT NULL,
  request_hash     bytea,
  response_status  integer,
  response_body    jsonb,
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL,
  PRIMARY KEY (user_id, scope, key)
);

-- Domain facts. Not the APNs outbox. Not the OLTP source of truth.
CREATE TABLE core.domain_events (
  id              bigint GENERATED ALWAYS AS IDENTITY,
  occurred_at     timestamptz NOT NULL DEFAULT now(),
  aggregate_type  text NOT NULL,
  aggregate_id    uuid NOT NULL,
  event_type      text NOT NULL,
  event_version   integer NOT NULL DEFAULT 1,
  actor_id        uuid REFERENCES core.users (id),
  payload         jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE core.domain_events_2026_08
  PARTITION OF core.domain_events
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

CREATE INDEX domain_events_agg
  ON core.domain_events (aggregate_type, aggregate_id, occurred_at);

-- Transactional outbox. Same txn as the fact. Worker sends APNs.
-- payload MUST NOT contain health numbers or money amounts.
CREATE TABLE core.notification_outbox (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES core.users (id),
  device_id       uuid REFERENCES core.devices (id),
  kind            text NOT NULL,          -- invite | poke | sync_nudge | settled
  payload         jsonb NOT NULL DEFAULT '{}',
  status          core.outbox_status NOT NULL DEFAULT 'pending',
  idempotency_key text NOT NULL UNIQUE,
  available_at    timestamptz NOT NULL DEFAULT now(),
  attempt_count   integer NOT NULL DEFAULT 0,
  last_error      text,
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX outbox_due ON core.notification_outbox (available_at)
  WHERE status = 'pending';

-- ═══════════════════════════════════════════════════════════════════
-- orgs (v1 empty)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE orgs.organizations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  name        text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════════════
-- fights
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE fights.series (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id         uuid NOT NULL REFERENCES core.users (id),
  cadence_days    integer NOT NULL CHECK (cadence_days > 0),
  iana_timezone   text NOT NULL,
  template        jsonb NOT NULL,         -- metric, stake, settlement, length
  is_active       boolean NOT NULL DEFAULT true,
  next_starts_on  date,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE fights.fights (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  public_code          text NOT NULL,     -- Crockford, display FF-XXXX-XXXX
  series_id            uuid REFERENCES fights.series (id),
  occurrence_index     integer,           -- 1,2,3… inside a series
  host_id              uuid NOT NULL REFERENCES core.users (id),
  sponsor_org_id       uuid REFERENCES orgs.organizations (id),
  name                 text NOT NULL,
  shape                fights.fight_shape NOT NULL DEFAULT 'race',
  status               fights.fight_status NOT NULL DEFAULT 'scheduled',
  metric_kind          text NOT NULL REFERENCES fights.metric_defs (kind),
  iana_timezone        text NOT NULL,     -- frozen at create
  starts_on            date NOT NULL,
  ends_on              date NOT NULL,     -- inclusive civil days
  window_start         timestamptz NOT NULL,
  window_end           timestamptz NOT NULL,
  grace_until          timestamptz NOT NULL, -- window_end + 6h (server constant)
  stake_kind           fights.stake_kind NOT NULL,
  settlement_kind      fights.settlement_kind NOT NULL,
  buy_in_minor         bigint NOT NULL DEFAULT 0 CHECK (buy_in_minor >= 0),
  currency             char(3) NOT NULL DEFAULT 'USD',
  action_text          text,              -- forfeit copy; never proportional
  daily_goal_milli     bigint,            -- shared default; members may override
  dual_target_milli    bigint,            -- dual: e.g. lose 10 kg
  dual_miss_policy     fights.dual_miss_policy,
  rules_version        integer NOT NULL,  -- settlement interpreter
  merge_policy_version integer NOT NULL DEFAULT 1, -- health source merge
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  settled_at           timestamptz,
  cancelled_at         timestamptz,

  CHECK (ends_on >= starts_on),
  CHECK (window_end > window_start),
  CHECK (grace_until >= window_end),
  CHECK (public_code ~ '^[0-9A-HJKMNP-TV-Z]{8}$'),
  CHECK (stake_kind <> 'action' OR settlement_kind <> 'proportional'),
  CHECK (stake_kind <> 'none' OR buy_in_minor = 0),
  CHECK (stake_kind <> 'action' OR action_text IS NOT NULL),
  CHECK (settlement_kind <> 'goal' OR daily_goal_milli IS NOT NULL),
  CHECK (shape <> 'dual' OR (dual_target_milli IS NOT NULL AND dual_miss_policy IS NOT NULL)),
  CHECK (shape <> 'sponsored_race' OR sponsor_org_id IS NOT NULL),
  CHECK (series_id IS NULL OR occurrence_index IS NOT NULL)
);

CREATE UNIQUE INDEX fights_public_code ON fights.fights (public_code);
CREATE UNIQUE INDEX fights_series_occ ON fights.fights (series_id, occurrence_index)
  WHERE series_id IS NOT NULL;
CREATE INDEX fights_settle_job ON fights.fights (status, grace_until)
  WHERE status IN ('live', 'grace');
CREATE INDEX fights_host ON fights.fights (host_id, created_at DESC);

CREATE TABLE fights.memberships (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id         uuid NOT NULL REFERENCES fights.fights (id),
  user_id          uuid NOT NULL REFERENCES core.users (id),
  role             fights.member_role NOT NULL DEFAULT 'racer',
  status           fights.member_status NOT NULL DEFAULT 'invited',
  is_host          boolean NOT NULL DEFAULT false,
  buy_in_minor     bigint NOT NULL DEFAULT 0 CHECK (buy_in_minor >= 0),
  daily_goal_milli bigint,                -- per-person override; UI ships shared
  baseline_milli   bigint,                -- dual challenger starting mass
  accepted_at      timestamptz,
  left_at          timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (fight_id, user_id)
);
CREATE INDEX memberships_user ON fights.memberships (user_id, status);
CREATE UNIQUE INDEX memberships_one_host ON fights.memberships (fight_id)
  WHERE is_host;
CREATE UNIQUE INDEX memberships_one_challenger ON fights.memberships (fight_id)
  WHERE role = 'challenger' AND status = 'accepted';

CREATE TABLE fights.invites (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id        uuid NOT NULL REFERENCES fights.fights (id),
  created_by      uuid NOT NULL REFERENCES core.users (id),
  invited_user_id uuid REFERENCES core.users (id), -- null = link-only
  status          fights.invite_status NOT NULL DEFAULT 'pending',
  expires_at      timestamptz NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  responded_at    timestamptz
);
CREATE INDEX invites_open ON fights.invites (invited_user_id, status)
  WHERE status = 'pending';
CREATE UNIQUE INDEX invites_one_pending ON fights.invites (fight_id, invited_user_id)
  WHERE status = 'pending' AND invited_user_id IS NOT NULL;
-- public_code on fights is the shareable join secret; rate-limit in the API.

-- Competition numbers. Mutable until freeze; revisions audited in health.
CREATE TABLE fights.score_days (
  fight_id        uuid NOT NULL REFERENCES fights.fights (id),
  user_id         uuid NOT NULL REFERENCES core.users (id),
  local_date      date NOT NULL,          -- civil day in fight.iana_timezone
  value_milli     bigint NOT NULL CHECK (value_milli >= 0),
  status          fights.score_day_status NOT NULL DEFAULT 'open',
  ingest_batch_id uuid,                   -- last batch that won
  compiled_at     timestamptz NOT NULL,   -- phone's compile clock
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fight_id, user_id, local_date)
);
CREATE INDEX score_days_user ON fights.score_days (user_id, local_date);

-- Written once. Never update. Replay uses this + score_days + rules_version.
CREATE TABLE fights.settlements (
  fight_id      uuid PRIMARY KEY REFERENCES fights.fights (id),
  rules_version integer NOT NULL,
  ledger_tx_id  uuid,                     -- null when stake_kind = none | action
  input_hash    bytea NOT NULL,           -- hash of frozen inputs
  computed_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE fights.settlement_lines (
  fight_id    uuid NOT NULL REFERENCES fights.settlements (fight_id),
  user_id     uuid NOT NULL REFERENCES core.users (id),
  rank        integer NOT NULL,
  score_milli bigint NOT NULL,
  net_minor   bigint NOT NULL,            -- signed cents; 0 for bragging/action
  scored      boolean NOT NULL,           -- false = no successful upload → refund
  PRIMARY KEY (fight_id, user_id)
);

-- Action stakes: who owes the forfeit. Not money.
CREATE TABLE fights.action_obligations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id     uuid NOT NULL REFERENCES fights.fights (id),
  from_user_id uuid NOT NULL REFERENCES core.users (id),
  to_user_id   uuid NOT NULL REFERENCES core.users (id),
  description  text NOT NULL,
  status       text NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open', 'done', 'waived')),
  created_at   timestamptz NOT NULL DEFAULT now(),
  closed_at    timestamptz
);

CREATE VIEW fights.v_pots AS
SELECT m.fight_id,
       f.currency,
       SUM(m.buy_in_minor) FILTER (WHERE m.status = 'accepted') AS pot_minor,
       COUNT(*) FILTER (WHERE m.status = 'accepted') AS accepted_count,
       COUNT(*) FILTER (WHERE m.status = 'invited') AS pending_count
FROM fights.memberships m
JOIN fights.fights f ON f.id = m.fight_id
GROUP BY m.fight_id, f.currency;

CREATE VIEW fights.v_totals AS
SELECT fight_id, user_id, SUM(value_milli) AS score_milli
FROM fights.score_days
GROUP BY fight_id, user_id;

-- ═══════════════════════════════════════════════════════════════════
-- health  (fight-scoped daily totals — not an HK warehouse)
-- ═══════════════════════════════════════════════════════════════════
-- Unpartitioned on purpose: UNIQUE (user_id, idempotency_key) cannot live on a
-- RANGE(received_at) parent (Postgres unique indexes must include the partition key).
CREATE TABLE health.ingest_batches (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          uuid NOT NULL REFERENCES core.users (id),
  fight_id         uuid NOT NULL REFERENCES fights.fights (id),
  device_id        uuid REFERENCES core.devices (id),
  idempotency_key  text NOT NULL,         -- scores:{user}:{fight}:{from}:{to}:{sha256}
  provider         health.provider NOT NULL DEFAULT 'healthkit',
  compiled_at      timestamptz NOT NULL,
  from_day         date NOT NULL,
  to_day           date NOT NULL,
  payload_sha256   bytea NOT NULL,
  status           health.ingest_status NOT NULL DEFAULT 'accepted',
  reject_reason    text,
  received_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);
CREATE INDEX ingest_batches_received ON health.ingest_batches (received_at);

-- One accepted value per member-day. Overwrites until freeze if compiled_at newer.
CREATE TABLE health.day_quantities (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ingest_batch_id      uuid NOT NULL,     -- no FK onto ingest_batches (keep apply cheap)
  fight_id             uuid NOT NULL REFERENCES fights.fights (id),
  user_id              uuid NOT NULL REFERENCES core.users (id),
  metric_kind          text NOT NULL REFERENCES fights.metric_defs (kind),
  local_date           date NOT NULL,
  value_milli          bigint NOT NULL CHECK (value_milli >= 0),
  provider             health.provider NOT NULL,
  source_bundle_id     text,              -- HK sourceRevision.bundleIdentifier
  source_device        text,
  merge_policy_version integer NOT NULL DEFAULT 1,
  compiled_at          timestamptz NOT NULL,
  UNIQUE (fight_id, user_id, local_date)
);

-- Append-only history of every accepted (and superseded) day value.
CREATE TABLE health.day_quantity_revisions (
  id              bigint GENERATED ALWAYS AS IDENTITY,
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  fight_id        uuid NOT NULL,
  user_id         uuid NOT NULL,
  local_date      date NOT NULL,
  value_milli     bigint NOT NULL,
  ingest_batch_id uuid NOT NULL,
  compiled_at     timestamptz NOT NULL,
  provider        health.provider NOT NULL,
  provenance      jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, recorded_at)
) PARTITION BY RANGE (recorded_at);

CREATE TABLE health.day_quantity_revisions_2026_08
  PARTITION OF health.day_quantity_revisions
  FOR VALUES FROM ('2026-08-01') TO ('2026-09-01');

CREATE INDEX day_rev_lookup
  ON health.day_quantity_revisions (fight_id, user_id, local_date, recorded_at);

-- Dual-challenge later. Do not backfill a lifetime weight history.
CREATE TABLE health.mass_checkpoints (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id        uuid NOT NULL REFERENCES fights.fights (id),
  user_id         uuid NOT NULL REFERENCES core.users (id),
  recorded_at     timestamptz NOT NULL,
  value_milli     bigint NOT NULL,        -- milligrams (unit g × scale 1000)
  provider        health.provider NOT NULL DEFAULT 'connected_scale',
  ingest_batch_id uuid,
  UNIQUE (fight_id, user_id, recorded_at)
);

-- ═══════════════════════════════════════════════════════════════════
-- ledger  (IOUs among friends — not a payment processor)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE ledger.accounts (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind       ledger.account_kind NOT NULL,
  user_id    uuid REFERENCES core.users (id),
  fight_id   uuid REFERENCES fights.fights (id),
  org_id     uuid REFERENCES orgs.organizations (id),
  currency   char(3) NOT NULL DEFAULT 'USD',
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (
    (kind = 'user_iou'       AND user_id IS NOT NULL AND fight_id IS NULL AND org_id IS NULL) OR
    (kind = 'fight_clearing' AND fight_id IS NOT NULL AND user_id IS NULL AND org_id IS NULL) OR
    (kind = 'sponsor_pool'   AND org_id IS NOT NULL AND user_id IS NULL) OR
    (kind = 'system'         AND user_id IS NULL AND fight_id IS NULL AND org_id IS NULL)
  )
);
CREATE UNIQUE INDEX accounts_user_iou ON ledger.accounts (user_id, currency)
  WHERE kind = 'user_iou';
CREATE UNIQUE INDEX accounts_fight ON ledger.accounts (fight_id, currency)
  WHERE kind = 'fight_clearing';
CREATE UNIQUE INDEX accounts_sponsor ON ledger.accounts (org_id, currency)
  WHERE kind = 'sponsor_pool';

CREATE TABLE ledger.transactions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind             ledger.tx_kind NOT NULL,
  fight_id         uuid REFERENCES fights.fights (id),
  idempotency_key  text NOT NULL UNIQUE,
  memo             text,
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ledger.entries (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tx_id        uuid NOT NULL REFERENCES ledger.transactions (id),
  account_id   uuid NOT NULL REFERENCES ledger.accounts (id),
  dir          ledger.entry_dir NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0)
);
CREATE INDEX entries_tx ON ledger.entries (tx_id);
CREATE INDEX entries_account ON ledger.entries (account_id);

-- Who owes whom. Net user balance is not enough for settle-up.
CREATE TABLE ledger.obligations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id     uuid NOT NULL REFERENCES fights.fights (id),
  from_user_id uuid NOT NULL REFERENCES core.users (id), -- debtor
  to_user_id   uuid NOT NULL REFERENCES core.users (id), -- creditor
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency     char(3) NOT NULL DEFAULT 'USD',
  status       ledger.obligation_status NOT NULL DEFAULT 'open',
  opened_tx_id uuid NOT NULL REFERENCES ledger.transactions (id),
  closed_tx_id uuid REFERENCES ledger.transactions (id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  closed_at    timestamptz,
  CHECK (from_user_id <> to_user_id)
);
CREATE INDEX obligations_open_from ON ledger.obligations (from_user_id)
  WHERE status = 'open';
CREATE INDEX obligations_open_to ON ledger.obligations (to_user_id)
  WHERE status = 'open';

-- App enforces Σ debit = Σ credit per tx (deferrable trigger when we code it).

-- ═══════════════════════════════════════════════════════════════════
-- social
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE social.pokes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id uuid NOT NULL REFERENCES core.users (id),
  to_user_id   uuid NOT NULL REFERENCES core.users (id),
  fight_id     uuid REFERENCES fights.fights (id),
  kind         social.poke_kind NOT NULL,
  body         text NOT NULL CHECK (char_length(body) BETWEEN 1 AND 80),
  created_at   timestamptz NOT NULL DEFAULT now(),
  hidden_at    timestamptz,
  CHECK (from_user_id <> to_user_id)
);
CREATE INDEX pokes_from_rate ON social.pokes (from_user_id, created_at DESC);
CREATE INDEX pokes_to ON social.pokes (to_user_id, created_at DESC);

CREATE TABLE social.reports (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id     uuid NOT NULL REFERENCES core.users (id),
  subject_user_id uuid NOT NULL REFERENCES core.users (id),
  poke_id         uuid REFERENCES social.pokes (id),
  reason          text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

-- ═══════════════════════════════════════════════════════════════════
-- feedback  (separate bounded context — Requests tab)
-- ═══════════════════════════════════════════════════════════════════
CREATE TABLE feedback.requests (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id  uuid NOT NULL REFERENCES core.users (id),
  kind       feedback.request_kind NOT NULL,
  status     feedback.request_status NOT NULL DEFAULT 'open',
  title      text NOT NULL,
  body       text NOT NULL,
  vote_count integer NOT NULL DEFAULT 0,  -- cache; votes table is SoT
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX requests_rank ON feedback.requests (kind, vote_count DESC);

CREATE TABLE feedback.votes (
  request_id uuid NOT NULL REFERENCES feedback.requests (id),
  user_id    uuid NOT NULL REFERENCES core.users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (request_id, user_id)
);

-- Thread UI is not designed; table is cheap and keeps votes a separate context.
CREATE TABLE feedback.comments (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES feedback.requests (id),
  author_id  uuid NOT NULL REFERENCES core.users (id),
  body       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX comments_request ON feedback.comments (request_id, created_at);
```

---

## Append-only vs mutable

| Append-only (insert, never update/delete*) | Mutable |
| --- | --- |
| `core.commands` | `core.users` profile, `deleted_at` |
| `core.domain_events` | `core.sessions.status`, `core.devices.apns_token` |
| `core.idempotency_keys` (until expiry) | `fights.fights.status` (scheduled→…→settled) |
| `health.ingest_batches` | `fights.memberships.status` |
| `health.day_quantity_revisions` | `fights.score_days.value_milli` until freeze |
| `ledger.transactions` + `ledger.entries` | `ledger.obligations.status` (close via new tx) |
| `fights.settlements` + `settlement_lines` | `health.day_quantities` (newer `compiled_at` wins) |
| `social.pokes` body | `social.pokes.hidden_at`, `core.notification_outbox.status` |
| `feedback.votes` (delete row = unvote) | `feedback.requests.status`, cached `vote_count` |

\*Retention drops **partitions**, not row-level deletes of facts you still owe.

**Freeze rule:** when `now() >= fights.fights.grace_until`, `score_days.status`
→ `frozen`. Later batches get `409 window_frozen`. Settlement insert is
idempotent on `fight_id`.

**Reversals:** cancel/refund = new ledger tx, never `UPDATE amount` / `DELETE FROM entries`.

---

## Do not store (not source of truth)

- Kickers, `listSubtitle`, `payoutLine`, `invitePitch`, `paceNote`, `standingsMeta`
- `projectedNet`, `rank`, `daysLeft`, “if nothing changes” money
- `pot` as a column on `fights` (use `fights.v_pots`; cache only with a generation if you must)
- Formatted strings: `$30`, `61.4k`, `Mon 27 Jul`, `12 min behind Leo`
- You-tab aggregates (fights, wins, win rate, `$ won`) — queries / cache
- Apple identity token, Strava tokens, raw HK samples, GPS, HR, sleep
- Health or money in `core.notification_outbox.payload` (copy is “open FitFight” / friend poke text)
- Card PAN, Stripe customer IDs (v1 is IOU)
- `float`/`double` scores or money

Live standings = `SUM(fights.score_days)` + `fights.rules_version` in the API.
Settlement lines are the only frozen money.

---

## Partitioning and retention

| Table | Partition | Keep |
| --- | --- | --- |
| `health.ingest_batches` | **none** (unique idempotency key) | 12 months, then `DELETE` by `received_at` |
| `health.day_quantity_revisions` | month on `recorded_at` | 24 months, drop partition |
| `core.domain_events` | month on `occurred_at` | 24 months, drop partition |
| `core.notification_outbox` | none | delete `sent` after 14d; `dead` after 90d |
| `fights.score_days` | none | 24 months after fight ends, then drop (GDPR) |
| `ledger.*` | none | forever (obligations survive delete-me as numbers) |
| `health.day_quantities` | none | same as score_days (tiny: users × days × fights) |

Do **not** partition memberships, fights, votes, or ingest batches. A unique
`(user_id, idempotency_key)` on a `RANGE(received_at)` parent is invalid in
Postgres unless the unique also contains `received_at` — which defeats
idempotency. Do **not** introduce Timescale/Citus/Supabase. App cron:
`CREATE TABLE … PARTITION OF` for next month on events + revisions.

There is no `samples` hypertable. If someone adds `health.hk_samples`, reject
the PR. Workout **counts** are daily `value_milli` on the fight metric.

---

## Idempotency keys

| Action | Key |
| --- | --- |
| Create fight / accept / decline / vote / poke | `core.commands.id` (client UUID) |
| Other POSTs | `core.idempotency_keys (user_id, scope, key)` |
| Score upload | `health.ingest_batches (user_id, idempotency_key)` = `scores:{user}:{fight}:{from}:{to}:{sha256(days)}` |
| Ledger post | `ledger.transactions.idempotency_key` (`settle:{fight_id}`, `stake:{membership_id}`) |
| APNs | `core.notification_outbox.idempotency_key` (`poke:{poke_id}`, `nudge:{fight_id}:{user_id}:{day}`) |
| SIWA | `core.apple_identities.apple_sub` |
| Device | `core.devices.apns_token` unique (token can move users: upsert, reassign) |
| Vote | `feedback.votes (request_id, user_id)` |
| Join code | `fights.fights.public_code` |

Retry the **same** key on HTTP timeout. Server no-ops duplicates.

---

## Settlement (server, once)

Inputs: `fights.rules_version`, shape, stake, settlement, accepted members,
`fights.score_days` (frozen), `scored` = (at least one applied ingest in window).

- **unscored** (no successful upload): buy-in released to that user, not treated as 0. Friends hate forfeit-on-Don't-Allow.
- **winner:** max `score_milli` among scored racers takes clearing; ties: split or documented tie-break in `rules_version`.
- **proportional:** share = score / Σ scores; skip action (CHECK already forbids).
- **goal:** hitters (`score_milli / days >= daily_goal_milli`) split misses' buy-ins; hitters get buy-in back.
- **dual:** challenger vs target vs baseline; miss policy column.
- **none / action:** no ledger tx; action writes `fights.action_obligations`.

Write `settlements` + lines + ledger tx + obligations in **one** DB transaction.
`SELECT … FOR UPDATE` the fight row. Replay = same `input_hash` → return existing.

---

## Extensibility (columns now, product later)

| Later feature | Hook already here |
| --- | --- |
| Recurring | `fights.series` + `fights.series_id` / `occurrence_index`. Cron inserts the next fight from `template`; do not pre-generate years. |
| Dual vs backers | `shape = dual`, `memberships.role` challenger/backer, `dual_*`, `health.mass_checkpoints` |
| Company credits | `stake_kind = credit`, `sponsor_org_id`, `ledger.account_kind = sponsor_pool` |
| Per-person goals | `fights.memberships.daily_goal_milli` |
| Strava | `provider = strava`; **one provider per fight metric** (don't SUM HK+Strava) |
| Teams 2v2 | **not** hooked. Needs a `side` column later. Don't fake it with backers. |

---

## The 5 decisions we'll be glad we made

1. **UUID PK ≠ Apple `sub` ≠ `handle` ≠ `public_code`.** Tombstone, rename, rotate a guessed code, without rewriting FKs. Sequential `FIGHT-742` is a scrape.
2. **`rules_version` frozen + immutable settlement + `input_hash`.** Shipping proportional-rounding v2 cannot restate last month's pots.
3. **Fight-scoped daily totals in fight tz, not a health warehouse.** Two overlapping step fights with different zones are two uploads. No global day table to join. Raw samples never land here.
4. **Directed IOU obligations + double-entry clearing, not a `pot` column and not a net `users.balance`.** Settle-up needs “Sam owes Maya $10 for 10K Club.” Sponsor credits are another account kind, not a rewrite.
5. **`shape` + `memberships.role` + nullable `series_id` from day one.** Recurring / dual / sponsors do not split `fights` into new PK hierarchies.

---

## The 5 traps that cause painful migrations

1. **Postgres `ENUM` for words that will split.** Renaming `goal` → `hit_daily_goal` or adding `hybrid` after storing millions of rows is a rewrite. Statuses above are truly closed. If a new settlement mode is a maybe, use `text` + CHECK. **Never `RENAME VALUE`.**
2. **Fight-level `status = invited`.** It is viewer-relative. You will add `my_status`, then rewrite the list query, then break push targeting. Membership vs fight lifecycle stay split.
3. **`float`/`numeric` money and scores.** Proportional “60% pays $30” will not replay; `0.1 + 0.2` will show a $1 off the money line. Milli `bigint` only.
4. **SUM of HealthKit + Strava (or any two sources) as the score.** The mock already filed this bug. One `provider` per fight metric; `merge_policy_version` if you ever change that. Provenance columns exist so you can *see* the source, not so you can add it.
5. **Updating settlement / pot / ledger in place.** Friends will screenshot the money line. Reverse with a new tx. Dropping `pot_minor` onto `fights` as SoT recreates “pot shows the old amount after someone joins.”

Honourable mentions: timezone-less `timestamptz` as a “day”; event-sourcing the OLTP; RLS-only auth with a key in the iOS binary; cloning this 3NF onto GRDB; storing kickers; email as unique identity.

---

## Phone mapping (do not 3NF the replica)

| Server | Phone `cache_*` |
| --- | --- |
| `fights.fights` + `v_pots` + `v_totals` | `cache_fight` (includes **cached** pot for the card) |
| `memberships` | `cache_membership` |
| `score_days` | `cache_score_day` |
| `settlements` + lines | `cache_settlement` payload, immutable |
| `feedback.*` | `cache_request` / `cache_vote` |
| — | kickers, rank, projected net: compute or copy GET `display`, never columns |

---

## What this is not

Not a payment processor. Not a HealthKit mirror. Not Supabase. Not the
Requests UI, poke compose, or settle-up screens (undesigned). The API
projects the mock; this schema stores the facts the mock was pretending to be.

# Postgres schema

Law for the **server** database. The phone replica is a read model (`cache_*`); do not clone this ERD onto the device. Postgres stays private behind an API we own.

The mock `Fight` struct is a **view model**. `pot`, `projectedNet`, kickers, `daysLeft`, and `status == invited` are not facts.

Fuller commentary: [`decisions.md`](decisions.md), [`domain.md`](domain.md). Phone tables: [`../sync.md`](../sync.md).

## Conventions

- PK `uuid` default `gen_random_uuid()`. Display codes are not PKs.
- Money: `bigint` cents + `char(3)` currency. Never float.
- Metrics: `bigint` native units (steps; **seconds** for active minutes; workout counts).
- Civil days: `date` in the **fight** IANA timezone. Instants: `timestamptz`.
- Status enums are closed. Product-volatile words: `text` + CHECK.
- Apple `sub` is identity, not the user PK.

## Bounded contexts (schemas)

`core` identity/session/outbox · `fights` windows/members/scores/settlement · `health` ingest · `ledger` IOUs · `social` pokes · `feedback` Requests tab · `orgs` sponsors (empty v1)

## DDL

```sql
CREATE SCHEMA core;
CREATE SCHEMA fights;
CREATE SCHEMA health;
CREATE SCHEMA ledger;
CREATE SCHEMA social;
CREATE SCHEMA feedback;
CREATE SCHEMA orgs;

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
CREATE TYPE fights.score_day_status AS ENUM ('open', 'frozen');
CREATE TYPE health.provider AS ENUM ('healthkit', 'strava', 'connected_scale');
CREATE TYPE health.ingest_status AS ENUM ('accepted', 'rejected', 'applied');
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
CREATE TYPE core.session_status AS ENUM ('active', 'revoked');
CREATE TYPE core.outbox_status AS ENUM ('pending', 'sending', 'sent', 'failed', 'dead');

CREATE TABLE fights.metric_defs (
  kind  text PRIMARY KEY,     -- steps | active_minutes | workouts | mass
  unit  text NOT NULL         -- step | second | workout | gram
);
INSERT INTO fights.metric_defs (kind, unit) VALUES
  ('steps', 'step'),
  ('active_minutes', 'second'),
  ('workouts', 'workout'),
  ('mass', 'gram');

CREATE TABLE core.users (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  handle         text NOT NULL,
  display_name   text NOT NULL,
  avatar_url     text,
  iana_timezone  text NOT NULL DEFAULT 'Europe/Paris', -- reminders only
  locale         text NOT NULL DEFAULT 'en',
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  deleted_at     timestamptz,
  CHECK (handle ~ '^[a-z0-9._]{2,30}$')
);
CREATE UNIQUE INDEX users_handle_alive ON core.users (lower(handle))
  WHERE deleted_at IS NULL;

CREATE TABLE core.apple_identities (
  user_id          uuid PRIMARY KEY REFERENCES core.users (id),
  apple_sub        text NOT NULL UNIQUE,
  email            text,          -- often Hide My Email; not login
  is_private_email boolean NOT NULL DEFAULT false,
  first_seen_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.devices (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES core.users (id),
  apns_token   text UNIQUE,
  bundle_id    text NOT NULL DEFAULT 'com.fitfight.mvp',
  created_at   timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  disabled_at  timestamptz
);

CREATE TABLE core.sessions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL REFERENCES core.users (id),
  device_id          uuid REFERENCES core.devices (id),
  refresh_token_hash bytea NOT NULL,
  status             core.session_status NOT NULL DEFAULT 'active',
  created_at         timestamptz NOT NULL DEFAULT now(),
  expires_at         timestamptz NOT NULL,
  revoked_at         timestamptz
);

CREATE TABLE core.blocks (
  blocker_id uuid NOT NULL REFERENCES core.users (id),
  blocked_id uuid NOT NULL REFERENCES core.users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (blocker_id, blocked_id),
  CHECK (blocker_id <> blocked_id)
);

CREATE TABLE core.commands (
  id        uuid PRIMARY KEY,          -- client UUID = idempotency key
  user_id   uuid NOT NULL REFERENCES core.users (id),
  type      text NOT NULL,
  body      jsonb NOT NULL,
  result    jsonb,
  applied_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.notification_outbox (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES core.users (id),
  kind            text NOT NULL,
  payload         jsonb NOT NULL DEFAULT '{}', -- NEVER health or money numbers
  status          core.outbox_status NOT NULL DEFAULT 'pending',
  idempotency_key text NOT NULL UNIQUE,
  available_at    timestamptz NOT NULL DEFAULT now(),
  attempt_count   integer NOT NULL DEFAULT 0,
  sent_at         timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE core.domain_events (
  id             bigint GENERATED ALWAYS AS IDENTITY,
  occurred_at    timestamptz NOT NULL DEFAULT now(),
  aggregate_type text NOT NULL,
  aggregate_id   uuid NOT NULL,
  event_type     text NOT NULL,
  actor_id       uuid REFERENCES core.users (id),
  payload        jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

CREATE TABLE orgs.organizations (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug       text NOT NULL UNIQUE,
  name       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE fights.series (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id        uuid NOT NULL REFERENCES core.users (id),
  cadence_days   integer NOT NULL CHECK (cadence_days > 0),
  iana_timezone  text NOT NULL,
  template       jsonb NOT NULL,
  is_active      boolean NOT NULL DEFAULT true,
  next_starts_on date,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE fights.fights (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  public_code           text NOT NULL,     -- 8 Crockford chars
  series_id             uuid REFERENCES fights.series (id),
  occurrence_index      integer,
  host_id               uuid NOT NULL REFERENCES core.users (id),
  sponsor_org_id        uuid REFERENCES orgs.organizations (id),
  name                  text NOT NULL,
  shape                 fights.fight_shape NOT NULL DEFAULT 'race',
  status                fights.fight_status NOT NULL DEFAULT 'scheduled',
  metric_kind           text NOT NULL REFERENCES fights.metric_defs (kind),
  iana_timezone         text NOT NULL,     -- frozen at create
  starts_on             date NOT NULL,
  ends_on               date NOT NULL,
  window_start          timestamptz NOT NULL,
  window_end            timestamptz NOT NULL,
  grace_until           timestamptz NOT NULL, -- next noon fight TZ, cap 48h
  stake_kind            fights.stake_kind NOT NULL,
  settlement_kind       fights.settlement_kind NOT NULL,
  buy_in_minor          bigint NOT NULL DEFAULT 0 CHECK (buy_in_minor >= 0),
  currency              char(3) NOT NULL DEFAULT 'USD',
  action_text           text,
  daily_goal_milli      bigint,            -- native units; name is historical
  dual_target_milli     bigint,
  dual_miss_policy      text CHECK (dual_miss_policy IN ('refund_backers', 'challenger_pays')),
  rules_version         integer NOT NULL,
  merge_policy_version  integer NOT NULL DEFAULT 1,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  settled_at            timestamptz,
  cancelled_at          timestamptz,
  CHECK (ends_on >= starts_on),
  CHECK (window_end > window_start),
  CHECK (grace_until >= window_end),
  CHECK (public_code ~ '^[0-9A-HJKMNP-TV-Z]{8}$'),
  CHECK (stake_kind <> 'action' OR settlement_kind <> 'proportional'),
  CHECK (stake_kind <> 'none' OR buy_in_minor = 0),
  CHECK (stake_kind <> 'action' OR action_text IS NOT NULL),
  CHECK (settlement_kind <> 'goal' OR daily_goal_milli IS NOT NULL),
  CHECK (shape <> 'dual' OR dual_target_milli IS NOT NULL),
  CHECK (shape <> 'sponsored_race' OR sponsor_org_id IS NOT NULL),
  CHECK (series_id IS NULL OR occurrence_index IS NOT NULL)
);
CREATE UNIQUE INDEX fights_public_code ON fights.fights (public_code);
CREATE INDEX fights_settle_job ON fights.fights (status, grace_until)
  WHERE status IN ('live', 'grace');

CREATE TABLE fights.memberships (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id         uuid NOT NULL REFERENCES fights.fights (id),
  user_id          uuid NOT NULL REFERENCES core.users (id),
  role             fights.member_role NOT NULL DEFAULT 'racer',
  status           fights.member_status NOT NULL DEFAULT 'invited',
  is_host          boolean NOT NULL DEFAULT false,
  buy_in_minor     bigint NOT NULL DEFAULT 0,
  daily_goal_milli bigint,               -- per-person later; UI ships shared
  accepted_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE (fight_id, user_id)
);
CREATE UNIQUE INDEX memberships_one_host ON fights.memberships (fight_id)
  WHERE is_host;

CREATE TABLE fights.score_days (
  fight_id        uuid NOT NULL REFERENCES fights.fights (id),
  user_id         uuid NOT NULL REFERENCES core.users (id),
  local_date      date NOT NULL,
  value_milli     bigint NOT NULL CHECK (value_milli >= 0),
  status          fights.score_day_status NOT NULL DEFAULT 'open',
  compiled_at     timestamptz NOT NULL,
  updated_at      timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (fight_id, user_id, local_date)
);

CREATE TABLE fights.settlements (
  fight_id      uuid PRIMARY KEY REFERENCES fights.fights (id),
  rules_version integer NOT NULL,
  ledger_tx_id  uuid,
  input_hash    bytea NOT NULL,
  computed_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE fights.settlement_lines (
  fight_id    uuid NOT NULL REFERENCES fights.settlements (fight_id),
  user_id     uuid NOT NULL REFERENCES core.users (id),
  rank        integer NOT NULL,
  score_milli bigint NOT NULL,
  net_minor   bigint NOT NULL,
  scored      boolean NOT NULL,          -- false = never uploaded → refund
  PRIMARY KEY (fight_id, user_id)
);

CREATE TABLE fights.action_obligations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id     uuid NOT NULL REFERENCES fights.fights (id),
  from_user_id uuid NOT NULL REFERENCES core.users (id),
  to_user_id   uuid NOT NULL REFERENCES core.users (id),
  description  text NOT NULL,
  status       text NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open', 'done', 'waived'))
);

CREATE VIEW fights.v_pots AS
SELECT m.fight_id, f.currency,
       SUM(m.buy_in_minor) FILTER (WHERE m.status = 'accepted') AS pot_minor,
       COUNT(*) FILTER (WHERE m.status = 'accepted') AS accepted_count,
       COUNT(*) FILTER (WHERE m.status = 'invited') AS pending_count
FROM fights.memberships m
JOIN fights.fights f ON f.id = m.fight_id
GROUP BY m.fight_id, f.currency;

CREATE TABLE health.ingest_batches (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid NOT NULL REFERENCES core.users (id),
  fight_id        uuid NOT NULL REFERENCES fights.fights (id),
  idempotency_key text NOT NULL,
  provider        health.provider NOT NULL DEFAULT 'healthkit',
  compiled_at     timestamptz NOT NULL,
  from_day        date NOT NULL,
  to_day          date NOT NULL,
  payload_sha256  bytea NOT NULL,
  status          health.ingest_status NOT NULL DEFAULT 'accepted',
  received_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, idempotency_key)
);

CREATE TABLE health.day_quantities (
  fight_id     uuid NOT NULL REFERENCES fights.fights (id),
  user_id      uuid NOT NULL REFERENCES core.users (id),
  local_date   date NOT NULL,
  value_milli  bigint NOT NULL,
  provider     health.provider NOT NULL,
  fingerprint  text,
  compiled_at  timestamptz NOT NULL,
  PRIMARY KEY (fight_id, user_id, local_date)
);

CREATE TABLE health.day_quantity_revisions (
  id              bigint GENERATED ALWAYS AS IDENTITY,
  recorded_at     timestamptz NOT NULL DEFAULT now(),
  fight_id        uuid NOT NULL,
  user_id         uuid NOT NULL,
  local_date      date NOT NULL,
  value_milli     bigint NOT NULL,
  compiled_at     timestamptz NOT NULL,
  provider        health.provider NOT NULL,
  provenance      jsonb NOT NULL DEFAULT '{}',
  PRIMARY KEY (id, recorded_at)
) PARTITION BY RANGE (recorded_at);

CREATE TABLE ledger.accounts (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind     ledger.account_kind NOT NULL,
  user_id  uuid REFERENCES core.users (id),
  fight_id uuid REFERENCES fights.fights (id),
  org_id   uuid REFERENCES orgs.organizations (id),
  currency char(3) NOT NULL DEFAULT 'USD'
);

CREATE TABLE ledger.transactions (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  kind            ledger.tx_kind NOT NULL,
  fight_id        uuid REFERENCES fights.fights (id),
  idempotency_key text NOT NULL UNIQUE,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE ledger.entries (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tx_id        uuid NOT NULL REFERENCES ledger.transactions (id),
  account_id   uuid NOT NULL REFERENCES ledger.accounts (id),
  dir          ledger.entry_dir NOT NULL,
  amount_minor bigint NOT NULL CHECK (amount_minor > 0)
);

CREATE TABLE ledger.obligations (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fight_id     uuid NOT NULL REFERENCES fights.fights (id),
  from_user_id uuid NOT NULL REFERENCES core.users (id),
  to_user_id   uuid NOT NULL REFERENCES core.users (id),
  amount_minor bigint NOT NULL CHECK (amount_minor > 0),
  currency     char(3) NOT NULL DEFAULT 'USD',
  status       ledger.obligation_status NOT NULL DEFAULT 'open',
  opened_tx_id uuid NOT NULL REFERENCES ledger.transactions (id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  CHECK (from_user_id <> to_user_id)
);

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

CREATE TABLE social.reports (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id     uuid NOT NULL REFERENCES core.users (id),
  subject_user_id uuid NOT NULL REFERENCES core.users (id),
  poke_id         uuid REFERENCES social.pokes (id),
  reason          text NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE feedback.requests (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id  uuid NOT NULL REFERENCES core.users (id),
  kind       feedback.request_kind NOT NULL,
  status     feedback.request_status NOT NULL DEFAULT 'open',
  title      text NOT NULL,
  body       text NOT NULL,
  vote_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE feedback.votes (
  request_id uuid NOT NULL REFERENCES feedback.requests (id),
  user_id    uuid NOT NULL REFERENCES core.users (id),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (request_id, user_id)
);
```

## Do not store

Kickers, `listSubtitle`, `payoutLine`, `projectedNet`, rank, `daysLeft`, a `pot` column as source of truth, formatted `$30` / `61.4k`, raw HealthKit, HR, GPS, Apple identity token as a session, Strava tokens, health or money in push payloads, float scores.

## Glad in 6–9 months

1. UUID ≠ Apple `sub` ≠ handle ≠ `public_code`
2. Frozen `rules_version` + immutable settlement + `input_hash`
3. Fight-scoped daily totals in fight TZ — not a health warehouse
4. Directed IOUs + double-entry, not a pot column
5. `shape` + `memberships.role` + nullable `series_id` from day one

## Painful if we reverse them

ENUM we later split · fight-level `invited` · float money · SUM of HealthKit+Strava · updating settlement in place · cloning this 3NF onto GRDB

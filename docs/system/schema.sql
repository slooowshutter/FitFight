-- FitFight target schema (design). Not applied.
-- Implement as timestamped files in supabase/migrations/. Do not edit this
-- file in place once migrations exist; copy forward.

create extension if not exists citext;
create extension if not exists pgcrypto;

create type metric_kind as enum ('steps', 'active_minutes', 'workouts', 'weight_kg');
create type sample_source as enum ('healthkit', 'strava', 'scale', 'manual');
create type stake_kind as enum ('bragging', 'money', 'action');
create type settlement_kind as enum ('winner', 'proportional', 'goal');
create type fight_lifecycle as enum ('scheduled', 'live', 'settling', 'settled', 'cancelled');
create type member_status as enum ('invited', 'accepted', 'declined', 'left', 'expired');
create type obligation_status as enum ('open', 'payer_marked', 'confirmed', 'written_off');
create type request_kind as enum ('feature', 'bug');
create type request_status as enum ('open', 'planned', 'shipped');
create type author_side as enum ('user', 'boss');
create type sod as enum ('healthkit', 'strava', 'scale', 'manual', 'derived', 'user', 'system');

create table profiles (
  id uuid primary key references auth.users (id) on delete restrict,
  handle citext unique check (handle is null or handle ~ '^[a-z][a-z0-9._]{2,19}$'),
  display_name text not null default '',
  initials text not null default '?',
  avatar_path text,
  timezone text not null default 'America/New_York',
  role text not null default 'user' check (role in ('user', 'staff')),
  settle_hint text,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table reserved_handles (
  handle citext primary key
);

create table handle_history (
  handle citext not null,
  profile_id uuid not null references profiles (id),
  released_at timestamptz not null default now()
);

create table connections (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  provider sample_source not null,
  status text not null default 'active',
  external_athlete_id text,
  last_sync_at timestamptz,
  cursor jsonb not null default '{}',
  created_at timestamptz not null default now(),
  unique (user_id, provider)
);

create table connection_secrets (
  connection_id uuid primary key references connections (id) on delete cascade,
  refresh_token_enc bytea not null,
  access_token_enc bytea,
  access_expires_at timestamptz,
  updated_at timestamptz not null default now()
);

create table ingest_batches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  client_batch_id uuid not null,
  source sample_source not null,
  received_at timestamptz not null default now(),
  sample_count int not null check (sample_count >= 0),
  unique (user_id, client_batch_id)
);

create table metric_samples (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  batch_id uuid references ingest_batches (id),
  source sample_source not null,
  metric metric_kind not null,
  value bigint not null check (value >= 0),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  external_id text not null,
  fingerprint text,
  duplicate_of uuid references metric_samples (id),
  excluded_reason text check (excluded_reason in ('duplicate', 'source_policy', 'invalid', 'late')),
  sod sod not null,
  ingested_at timestamptz not null default now(),
  unique (user_id, source, external_id),
  check (ended_at >= started_at)
);

create index metric_samples_user_ended on metric_samples (user_id, ended_at);

create table fights (
  id uuid primary key default gen_random_uuid(),
  code text not null unique check (code ~ '^FIGHT-[0-9A-HJKMNP-TV-Z]{6}$'),
  name text not null,
  created_by uuid not null references profiles (id),
  timezone text not null,
  starts_on date not null,
  ends_on date not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  settle_at timestamptz not null,
  length_days int generated always as (ends_on - starts_on + 1) stored,
  metric metric_kind not null,
  stake_kind stake_kind not null,
  settlement_kind settlement_kind,
  daily_goal bigint,
  buy_in_cents int not null default 0 check (buy_in_cents >= 0),
  currency char(3) not null default 'USD',
  forfeit_text text,
  lifecycle fight_lifecycle not null default 'scheduled',
  recipe_version int not null default 1,
  series_id uuid,
  subject_user_id uuid references profiles (id),
  sponsor_key text,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on >= starts_on),
  check (ends_at > starts_at),
  check (settle_at >= ends_at),
  check (length_days between 1 and 90),
  check (
    (stake_kind = 'bragging' and buy_in_cents = 0 and settlement_kind is null and forfeit_text is null)
    or (stake_kind = 'money' and buy_in_cents between 500 and 10000 and settlement_kind is not null and forfeit_text is null)
    or (stake_kind = 'action' and buy_in_cents = 0 and forfeit_text is not null
        and settlement_kind in ('winner', 'goal'))
  ),
  check (settlement_kind is distinct from 'goal' or (daily_goal is not null and daily_goal > 0))
);

create table fight_members (
  fight_id uuid not null references fights (id) on delete cascade,
  user_id uuid not null references profiles (id),
  status member_status not null,
  daily_goal bigint,
  buy_in_cents_snapshot int not null default 0,
  invited_by uuid references profiles (id),
  accepted_at timestamptz,
  declined_at timestamptz,
  left_at timestamptz,
  last_sync_at timestamptz,
  last_sample_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (fight_id, user_id)
);

create table fight_member_days (
  fight_id uuid not null,
  user_id uuid not null,
  day_index int not null check (day_index >= 0),
  day_date date not null,
  value bigint not null default 0 check (value >= 0),
  computed_at timestamptz not null default now(),
  audit jsonb,
  primary key (fight_id, user_id, day_index),
  foreign key (fight_id, user_id) references fight_members (fight_id, user_id)
);

create view fight_member_days_read as
  select fight_id, user_id, day_index, day_date, value, computed_at
  from fight_member_days;

create table fight_settlements (
  fight_id uuid primary key references fights (id),
  settled_at timestamptz not null default now(),
  algorithm_version int not null default 1,
  pot_cents int not null,
  accepted_count int not null,
  input_hash text not null,
  forfeit_text text
);

create table fight_settlement_lines (
  fight_id uuid not null references fight_settlements (fight_id) on delete cascade,
  user_id uuid not null,
  score bigint not null,
  rank int not null,
  hit_goal boolean,
  buy_in_cents int not null,
  payout_cents int not null,
  net_cents int not null,
  outcome text not null check (outcome in ('won', 'lost', 'even', 'void')),
  primary key (fight_id, user_id)
);

create table obligations (
  id uuid primary key default gen_random_uuid(),
  fight_id uuid not null references fights (id),
  kind text not null check (kind in ('money', 'action')),
  from_user_id uuid not null references profiles (id),
  to_user_id uuid not null references profiles (id),
  amount_cents int not null default 0,
  currency char(3),
  action_text text,
  status obligation_status not null default 'open',
  created_at timestamptz not null default now()
);

create table obligation_events (
  id uuid primary key default gen_random_uuid(),
  obligation_id uuid not null references obligations (id) on delete cascade,
  kind text not null,
  actor_id uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table requests (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references profiles (id),
  kind request_kind not null,
  status request_status not null default 'open',
  title text not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table request_votes (
  request_id uuid not null references requests (id) on delete cascade,
  user_id uuid not null references profiles (id),
  created_at timestamptz not null default now(),
  primary key (request_id, user_id)
);

create table request_comments (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references requests (id) on delete cascade,
  author_id uuid not null references profiles (id),
  body text not null,
  created_at timestamptz not null default now()
);

create table boss_messages (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  side author_side not null,
  body text not null,
  email_message_id text,
  created_at timestamptz not null default now()
);

create unique index boss_messages_email
  on boss_messages (email_message_id)
  where email_message_id is not null;

create table user_blocks (
  blocker_id uuid not null references profiles (id) on delete cascade,
  blocked_id uuid not null references profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

create table user_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references profiles (id),
  subject text not null,
  subject_id uuid not null,
  reason text not null,
  created_at timestamptz not null default now(),
  unique (reporter_id, subject, subject_id)
);

create table device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  token text not null unique,
  env text not null default 'sandbox',
  updated_at timestamptz not null default now()
);

create table push_outbox (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  kind text not null,
  fight_id uuid references fights (id),
  dedupe_key text not null unique,
  payload jsonb not null default '{}',
  status text not null default 'pending',
  attempts int not null default 0,
  next_attempt_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table invite_tokens (
  token text primary key,
  fight_id uuid not null references fights (id) on delete cascade,
  created_by uuid not null references profiles (id),
  expires_at timestamptz not null,
  claimed_by uuid references profiles (id),
  created_at timestamptz not null default now()
);

create table feature_flags (
  key text primary key,
  enabled boolean not null default false,
  payload jsonb not null default '{}',
  min_ios_build int,
  note text
);

create table sync_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references profiles (id) on delete cascade,
  source sample_source not null,
  trigger text not null,
  status text not null,
  accepted int not null default 0,
  duplicates int not null default 0,
  rejected int not null default 0,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  error_code text
);

-- RLS: enable on all; policies added in a real migration.
-- Grant authenticated SELECT on fight_member_days_read, never on metric_samples
-- to other users, never on connection_secrets.

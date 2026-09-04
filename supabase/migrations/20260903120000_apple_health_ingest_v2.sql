-- Private Apple Health collection (statistics + workouts/sleep/mindful).
-- Does not change Steps Fight scoring. Clients cannot read these tables.

create table private.health_ingest_state (
  user_id uuid primary key references public.profiles (user_id) on delete cascade,
  complete_through timestamptz not null,
  time_zone text not null,
  updated_at timestamptz not null default now()
);

create table private.health_metric_days (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  metric text not null,
  day date not null,
  value numeric not null,
  unit text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  time_zone text not null,
  input_hash text not null,
  finalized_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, metric, day),
  constraint health_metric_days_metric check (metric in (
    'distance_walking_running',
    'flights_climbed',
    'active_energy',
    'basal_energy',
    'exercise_time',
    'stand_time',
    'resting_heart_rate',
    'walking_heart_rate_average',
    'body_mass'
  )),
  constraint health_metric_days_value_nonnegative check (value >= 0),
  constraint health_metric_days_window check (ends_at > starts_at),
  constraint health_metric_days_input_hash check (input_hash ~ '^[0-9a-f]{64}$')
);

create index health_metric_days_day_idx on private.health_metric_days (day);

create table private.health_sessions (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_uuid uuid not null,
  kind text not null,
  activity_type text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  duration_seconds numeric not null,
  energy_kcal numeric,
  distance_m numeric,
  input_hash text not null,
  finalized_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, source_uuid),
  constraint health_sessions_kind check (kind in ('workout', 'sleep', 'mindful')),
  constraint health_sessions_window check (ends_at > starts_at),
  constraint health_sessions_duration_nonnegative check (duration_seconds >= 0),
  constraint health_sessions_energy_nonnegative check (energy_kcal is null or energy_kcal >= 0),
  constraint health_sessions_distance_nonnegative check (distance_m is null or distance_m >= 0),
  constraint health_sessions_input_hash check (input_hash ~ '^[0-9a-f]{64}$')
);

create index health_sessions_ends_at_idx on private.health_sessions (user_id, ends_at);

revoke all on table private.health_ingest_state, private.health_metric_days,
  private.health_sessions from public, anon, authenticated;
grant all on table private.health_ingest_state, private.health_metric_days,
  private.health_sessions to postgres, service_role;

alter table private.health_ingest_state enable row level security;
alter table private.health_metric_days enable row level security;
alter table private.health_sessions enable row level security;
alter table private.health_ingest_state force row level security;
alter table private.health_metric_days force row level security;
alter table private.health_sessions force row level security;

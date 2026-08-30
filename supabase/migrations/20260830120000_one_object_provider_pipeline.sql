-- One complete provider sync is one private Storage object and one processing job.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'provider-inbox',
  'provider-inbox',
  false,
  52428800,
  array['application/x-ndjson']::text[]
)
on conflict (id) do update
set public = false,
    file_size_limit = 52428800,
    allowed_mime_types = array['application/x-ndjson']::text[];

create table private.provider_uploads (
  upload_id uuid primary key,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_id uuid references public.data_sources (id),
  provider text not null,
  connection_route text not null,
  metric text not null,
  format_version integer not null,
  expected_byte_size bigint not null,
  expected_sha256 text not null,
  actual_byte_size bigint,
  actual_sha256 text,
  object_path text not null unique,
  status text not null default 'issued',
  lease_expires_at timestamptz,
  error_code text,
  receipt jsonb,
  issued_at timestamptz not null default now(),
  processing_started_at timestamptz,
  committed_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  constraint provider_uploads_uuid_v4 check (
    upload_id::text ~ '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  ),
  constraint provider_uploads_apple_steps check (
    provider = 'apple_health'
    and connection_route = 'healthkit'
    and metric = 'steps'
    and format_version = 1
  ),
  constraint provider_uploads_size check (expected_byte_size between 1 and 52428800),
  constraint provider_uploads_hash check (expected_sha256 ~ '^[0-9a-f]{64}$'),
  constraint provider_uploads_actual_size check (
    actual_byte_size is null or actual_byte_size between 1 and 52428800
  ),
  constraint provider_uploads_actual_hash check (
    actual_sha256 is null or actual_sha256 ~ '^[0-9a-f]{64}$'
  ),
  constraint provider_uploads_path check (
    object_path = user_id::text || '/' || upload_id::text || '/archive.ndjson'
  ),
  constraint provider_uploads_status check (
    status in ('issued', 'processing', 'committed', 'completed', 'rejected', 'retryable_failure')
  ),
  constraint provider_uploads_receipt_object check (
    receipt is null or jsonb_typeof(receipt) = 'object'
  )
);

create index provider_uploads_user_updated_idx
  on private.provider_uploads (user_id, updated_at desc);

create table private.provider_events (
  id uuid primary key default gen_random_uuid(),
  upload_id uuid not null references private.provider_uploads (upload_id) on delete restrict,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_id uuid not null references public.data_sources (id),
  event_kind text not null,
  external_record_id text not null,
  payload_hash text not null,
  payload jsonb not null,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  constraint provider_events_kind check (event_kind in ('add', 'change', 'delete')),
  constraint provider_events_hash check (payload_hash ~ '^[0-9a-f]{64}$'),
  constraint provider_events_payload_object check (jsonb_typeof(payload) = 'object'),
  constraint provider_events_idempotent unique (
    user_id, source_id, event_kind, external_record_id, payload_hash
  )
);

create index provider_events_user_record_idx
  on private.provider_events (user_id, source_id, external_record_id, received_at);

alter table private.metric_observations
  add column if not exists upload_id uuid references private.provider_uploads (upload_id) on delete restrict,
  add column if not exists scope text not null default 'civil_day',
  add column if not exists civil_day date,
  add column if not exists cutoff_at timestamptz,
  add column if not exists input_hash text,
  add column if not exists normalization_version integer not null default 1,
  add column if not exists calculation_version integer not null default 1;

alter table private.metric_observations
  add constraint metric_observations_scope check (scope in ('civil_day', 'fight_window')),
  add constraint metric_observations_input_hash check (
    input_hash is null or input_hash ~ '^[0-9a-f]{64}$'
  );

create table public.metric_days (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_id uuid not null references public.data_sources (id),
  metric text not null,
  day date not null,
  value numeric not null,
  unit text not null,
  input_hash text not null,
  normalization_version integer not null,
  calculation_version integer not null,
  finalized_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (user_id, source_id, metric, day),
  constraint metric_days_steps_only check (metric = 'steps' and unit = 'steps'),
  constraint metric_days_value_nonnegative check (value >= 0),
  constraint metric_days_input_hash check (input_hash ~ '^[0-9a-f]{64}$')
);

create index metric_days_day_idx on public.metric_days (day);

create table private.fight_score_snapshots (
  id uuid primary key default gen_random_uuid(),
  fight_id uuid not null references public.fights (id) on delete cascade,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  source_id uuid not null references public.data_sources (id),
  upload_id uuid not null references private.provider_uploads (upload_id) on delete restrict,
  cutoff_at timestamptz not null,
  value numeric not null,
  input_hash text not null,
  calculation_version integer not null,
  is_final boolean not null default false,
  created_at timestamptz not null default now(),
  constraint fight_score_snapshots_value_nonnegative check (value >= 0),
  constraint fight_score_snapshots_hash check (input_hash ~ '^[0-9a-f]{64}$'),
  constraint fight_score_snapshots_unique unique (fight_id, user_id, cutoff_at, input_hash)
);

revoke all on table private.provider_uploads, private.provider_events,
  private.fight_score_snapshots from public, anon, authenticated;
grant all on table private.provider_uploads, private.provider_events,
  private.fight_score_snapshots to postgres, service_role;

alter table private.provider_uploads enable row level security;
alter table private.provider_events enable row level security;
alter table private.fight_score_snapshots enable row level security;
alter table private.provider_uploads force row level security;
alter table private.provider_events force row level security;
alter table private.fight_score_snapshots force row level security;

grant select on public.metric_days to authenticated;
revoke insert, update, delete on public.metric_days from authenticated;
alter table public.metric_days enable row level security;
alter table public.metric_days force row level security;

create policy metric_days_select_self_or_fight
  on public.metric_days
  for select
  to authenticated
  using (
    user_id = (select auth.uid())
    or private.current_user_shares_accepted_fight_day(user_id, day)
  );

revoke insert, update, delete on public.step_days from authenticated;
drop policy if exists step_days_insert_own on public.step_days;
drop policy if exists step_days_update_own on public.step_days;

-- Signed capabilities bypass object policies. No client policy is created for
-- provider-inbox, so clients cannot list, read, download, or remove its objects.

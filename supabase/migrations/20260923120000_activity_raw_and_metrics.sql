-- Received Apple Health records and readings, then the current measurements resolved from them.
-- Private to the backend. Personal history stays correctable; final Fights stay frozen elsewhere.

create table private.activity_raw (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    source_id uuid not null references public.data_sources (id) on delete cascade,
    record_kind text not null,
    record_type text not null,
    record_key text not null,
    starts_at timestamptz,
    ends_at timestamptz,
    time_zone text,
    payload jsonb not null,
    payload_hash text not null,
    collected_at timestamptz not null,
    received_at timestamptz not null default now(),
    processing_state text not null default 'pending',
    processing_version integer,
    processing_attempts integer not null default 0,
    processing_error text,
    lease_expires_at timestamptz,
    processed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint activity_raw_kind check (record_kind in ('total', 'workout', 'deletion')),
    constraint activity_raw_state check (
        processing_state in ('pending', 'processing', 'processed', 'failed')
    ),
    constraint activity_raw_interval check (
        starts_at is null or ends_at is null or ends_at >= starts_at
    ),
    constraint activity_raw_hash check (payload_hash ~ '^[0-9a-f]{64}$'),
    constraint activity_raw_payload_object check (jsonb_typeof(payload) = 'object'),
    constraint activity_raw_attempts check (processing_attempts >= 0),
    -- Leading identity columns also serve the resolver's per-record lookups.
    constraint activity_raw_idempotent unique (
        source_id, record_type, record_key, record_kind, payload_hash
    )
);

create trigger maintain_row_timestamps
before update on private.activity_raw
for each row execute function private.maintain_row_timestamps();

create index activity_raw_unprocessed_idx
    on private.activity_raw (user_id, received_at)
    where processing_state <> 'processed';
create index activity_raw_user_idx on private.activity_raw (user_id);

alter table private.activity_raw enable row level security;
alter table private.activity_raw force row level security;
revoke all on private.activity_raw from public, anon, authenticated;
grant all on private.activity_raw to postgres, service_role;

create table private.activity_metrics (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    source_id uuid not null references public.data_sources (id) on delete cascade,
    scope text not null,
    scope_key text not null,
    metric text not null,
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    observed_through timestamptz not null,
    day date,
    time_zone text,
    fight_id uuid references public.fights (id) on delete cascade,
    value numeric not null,
    unit text not null,
    details jsonb not null default '{}',
    input_ids uuid[] not null,
    calculation_version integer not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    constraint activity_metrics_scope check (scope in ('workout', 'day', 'fight_window')),
    constraint activity_metrics_window check (ends_at > starts_at),
    constraint activity_metrics_observed check (observed_through <= ends_at),
    constraint activity_metrics_value_nonnegative check (value >= 0),
    constraint activity_metrics_details_object check (jsonb_typeof(details) = 'object'),
    constraint activity_metrics_inputs check (cardinality(input_ids) > 0),
    constraint activity_metrics_day_scope check (scope <> 'day' or day is not null),
    constraint activity_metrics_fight_scope check (scope <> 'fight_window' or fight_id is not null),
    constraint activity_metrics_current unique (source_id, scope, scope_key, metric)
);

create trigger maintain_row_timestamps
before update on private.activity_metrics
for each row execute function private.maintain_row_timestamps();

create index activity_metrics_user_day_idx
    on private.activity_metrics (user_id, metric, day)
    where scope = 'day';
create index activity_metrics_workout_day_idx
    on private.activity_metrics (source_id, day)
    where scope = 'workout';

alter table private.activity_metrics enable row level security;
alter table private.activity_metrics force row level security;
revoke all on private.activity_metrics from public, anon, authenticated;
grant all on private.activity_metrics to postgres, service_role;

-- Keep Profile Steps history when its reader moves from metric_days to activity_metrics.
-- Each legacy day becomes one processed input and its measurement. Legacy days without a
-- time zone keep a null zone, so Profile statistics still exclude them.
insert into private.activity_raw (
    user_id, source_id, record_kind, record_type, record_key, starts_at, ends_at, time_zone,
    payload, payload_hash, collected_at, created_at, processing_state, processing_version,
    processed_at
)
select legacy.user_id, legacy.source_id, 'total', 'steps', 'day:' || legacy.day::text,
    legacy.starts_at, legacy.observed_through, legacy.time_zone, legacy.payload,
    encode(sha256(convert_to(legacy.payload::text, 'UTF8')), 'hex'),
    legacy.updated_at, legacy.updated_at, 'processed', 1, now()
from (
    select days.*, bounds.starts_at,
        case when days.finalized_at is not null then bounds.ends_at
            else least(bounds.ends_at, greatest(days.updated_at, bounds.starts_at + interval '1 second'))
        end as observed_through,
        jsonb_build_object(
            'metric', 'steps', 'day', days.day::text, 'starts_at', bounds.starts_at,
            'ends_at', case when days.finalized_at is not null then bounds.ends_at
                else least(bounds.ends_at, greatest(days.updated_at, bounds.starts_at + interval '1 second'))
            end,
            'time_zone', days.time_zone, 'value', days.value, 'unit', 'steps',
            'legacy_table', 'metric_days'
        ) as payload
    from public.metric_days as days
    cross join lateral (
        select days.day::timestamp at time zone coalesce(days.time_zone, 'UTC') as starts_at,
            (days.day + 1)::timestamp at time zone coalesce(days.time_zone, 'UTC') as ends_at
    ) as bounds
    where days.metric = 'steps'
) as legacy
on conflict (source_id, record_type, record_key, record_kind, payload_hash) do nothing;

insert into private.activity_metrics (
    user_id, source_id, scope, scope_key, metric, starts_at, ends_at, observed_through, day,
    time_zone, value, unit, input_ids, calculation_version, updated_at
)
select distinct on (raw.source_id, raw.record_key)
    raw.user_id, raw.source_id, 'day', (raw.payload ->> 'day'), 'steps', raw.starts_at,
    (((raw.payload ->> 'day')::date + 1)::timestamp at time zone coalesce(raw.time_zone, 'UTC')),
    raw.ends_at, (raw.payload ->> 'day')::date, raw.time_zone,
    (raw.payload ->> 'value')::numeric, 'steps', array[raw.id], 1, raw.collected_at
from private.activity_raw as raw
where raw.payload ->> 'legacy_table' = 'metric_days'
order by raw.source_id, raw.record_key, raw.collected_at desc
on conflict (source_id, scope, scope_key, metric) do nothing;

create table private.ai_requests (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles(user_id) on delete cascade,
    workflow text not null check (workflow ~ '^[a-z][a-z0-9_]{0,63}$'),
    resource_id uuid,
    idempotency_key uuid not null,
    request_hash text not null check (request_hash ~ '^[a-f0-9]{64}$'),
    workflow_version jsonb not null,
    run_handle jsonb,
    status text not null default 'starting' check (
        status in ('starting', 'pending', 'running', 'completed', 'failed', 'cancelled', 'start_unconfirmed')
    ),
    result jsonb,
    error_code text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    lease_token uuid,
    lease_expires_at timestamptz,
    next_poll_at timestamptz not null default now(),
    unique (user_id, idempotency_key),
    check ((lease_token is null) = (lease_expires_at is null)),
    check (status not in ('pending', 'running', 'completed') or run_handle is not null),
    check ((status = 'completed') = (result is not null)),
    check ((status in ('failed', 'cancelled', 'start_unconfirmed')) = (error_code is not null)),
    check (jsonb_typeof(workflow_version) = 'object'),
    check (run_handle is null or jsonb_typeof(run_handle) = 'object'),
    check (result is null or jsonb_typeof(result) = 'object')
);

create index ai_requests_user_created_at on private.ai_requests (user_id, created_at);
create index ai_requests_unresolved on private.ai_requests (user_id, status)
    where status in ('starting', 'pending', 'running', 'start_unconfirmed');
create index ai_requests_terminal_updated_at on private.ai_requests (updated_at)
    where status in ('completed', 'failed', 'cancelled');

create table private.ai_caller_windows (
    user_id uuid primary key references public.profiles(user_id) on delete cascade,
    window_started_at timestamptz not null,
    calls integer not null check (calls between 1 and 61)
);

create table private.ai_provider_budget (
    provider text primary key check (provider = 'blend'),
    window_started_at timestamptz not null default now(),
    requests integer not null default 0 check (requests >= 0),
    starts_day date not null default (now() at time zone 'UTC')::date,
    starts integer not null default 0 check (starts >= 0),
    remaining integer check (remaining >= 0),
    reset_at timestamptz,
    blocked_until timestamptz
);

insert into private.ai_provider_budget (provider) values ('blend');

alter table private.ai_requests enable row level security;
alter table private.ai_caller_windows enable row level security;
alter table private.ai_provider_budget enable row level security;

revoke all on private.ai_requests, private.ai_caller_windows, private.ai_provider_budget
    from public, anon, authenticated, service_role, fitfight_backend_reader;

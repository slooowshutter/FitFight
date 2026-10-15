begin;

-- App errors that PostHog error tracking captured, copied here by a PostHog webhook so they are kept forever.
-- Each backend receives only its own environment's events. Clients have no access. Agents read via SQL.
create table private.app_error_logs (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    posthog_event_id uuid not null unique,
    occurred_at timestamptz not null,
    environment text,
    distinct_id text not null,
    app_version text,
    app_build text,
    error_type text,
    message text,
    posthog_issue_id uuid,
    properties jsonb not null
);
create index app_error_logs_occurred_at_idx on private.app_error_logs (occurred_at desc);
alter table private.app_error_logs enable row level security;
revoke all on private.app_error_logs from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.app_error_logs
    for each row execute function private.maintain_row_timestamps();

commit;

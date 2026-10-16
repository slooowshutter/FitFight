begin;

-- In-app alerts are defined in web/lib/alerts/in-app-alerts.ts. Each row is one thing a person did
-- with one: saw it, tapped a button, or closed it. An alert stops showing once it was tapped or closed.
create table private.alert_responses (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    alert_id text not null check (alert_id ~ '^[a-z0-9][a-z0-9-]{0,79}$'),
    response text not null check (response in ('shown', 'tapped', 'dismissed')),
    action text check (action ~ '^[a-z][a-z_]{0,39}$'),
    app_version text,
    app_build text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
create index alert_responses_user on private.alert_responses (user_id, alert_id);
alter table private.alert_responses enable row level security;
revoke all on private.alert_responses from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.alert_responses
    for each row execute function private.maintain_row_timestamps();

commit;

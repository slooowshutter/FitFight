begin;

-- Both hosted databases hold both rows. The backend reads the row for the Supabase
-- project it is configured with, so develop answers beta and main answers production.
create table private.environments (
    id uuid primary key default gen_random_uuid(),
    project_ref text not null unique,
    name text not null check (name in ('beta', 'production')),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);
alter table private.environments enable row level security;
revoke all on private.environments from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.environments
    for each row execute function private.maintain_row_timestamps();

insert into private.environments (project_ref, name) values
    ('zstzbfocunthczzubggz', 'beta'),
    ('pvqntpteehdvhqyctwum', 'production');

commit;

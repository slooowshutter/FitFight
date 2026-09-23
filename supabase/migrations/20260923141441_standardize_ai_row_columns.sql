begin;

set local lock_timeout = '5s';

-- Keep existing owner and compound keys for requests admitted before this migration.
alter table private.ai_caller_windows
    add column id uuid generated always as (user_id) stored not null,
    add column created_at timestamptz not null default now(),
    add column updated_at timestamptz not null default now();
create index on private.ai_caller_windows (id);

alter table private.ai_credit_balances
    add column id uuid generated always as (user_id) stored not null,
    add column created_at timestamptz not null default now();
create index on private.ai_credit_balances (id);

alter table private.ai_provider_budget
    add column id uuid not null default gen_random_uuid() unique,
    add column created_at timestamptz not null default now(),
    add column updated_at timestamptz not null default now();

alter table private.ai_library_images
    add column id uuid not null default gen_random_uuid() unique,
    add column updated_at timestamptz;
update private.ai_library_images set updated_at = created_at;
alter table private.ai_library_images
    alter column updated_at set default now(),
    alter column updated_at set not null;

alter table private.ai_http_logs
    add column created_at timestamptz,
    add column updated_at timestamptz;
update private.ai_http_logs
set created_at = observed_at, updated_at = observed_at;
alter table private.ai_http_logs
    alter column created_at set default now(),
    alter column created_at set not null,
    alter column updated_at set default now(),
    alter column updated_at set not null;

-- History rows cannot be updated, so an added default initializes older rows
-- without bypassing the immutability guard.
alter table private.ai_balance_events
    add column updated_at timestamptz not null default now();

create trigger maintain_row_timestamps before update on private.ai_requests
    for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.ai_caller_windows
    for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.ai_provider_budget
    for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.ai_credit_balances
    for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.ai_balance_events
    for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.ai_http_logs
    for each row execute function private.maintain_row_timestamps();
create trigger maintain_row_timestamps before update on private.ai_library_images
    for each row execute function private.maintain_row_timestamps();

commit;

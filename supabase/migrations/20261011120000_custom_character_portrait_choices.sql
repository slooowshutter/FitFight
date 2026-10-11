begin;

-- A purchase made by a current app draws three portraits. The owner selects one; the others stay.
-- action_key is the idempotency key of the portrait's current Blend attempt; a retry replaces it.
create table private.custom_character_portraits (
    id uuid primary key default gen_random_uuid(),
    purchase_id uuid not null references private.custom_character_purchases(id),
    slot smallint not null check (slot between 1 and 3),
    action_key uuid not null unique,
    selected_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (purchase_id, slot)
);
create unique index custom_character_portraits_one_selected on private.custom_character_portraits (purchase_id)
    where selected_at is not null;
alter table private.custom_character_portraits enable row level security;
revoke all on private.custom_character_portraits from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.custom_character_portraits
    for each row execute function private.maintain_row_timestamps();

-- Each "Your character is ready" push is sent at most once.
alter table private.custom_character_purchases
    add column portraits_notified_at timestamptz,
    add column poses_notified_at timestamptz;

-- Characters finished before this release must not receive a late push.
update private.custom_character_purchases purchase set poses_notified_at = now()
where exists (select 1 from private.ai_requests request
    where request.resource_id = purchase.id and request.workflow = 'fitness' and request.status = 'completed');

commit;

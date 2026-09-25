begin;

-- The existing Apple account token also binds repeatable custom-character charges.
create table private.custom_character_purchases (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references private.special_accounts(id),
    environment text not null check (environment in ('Sandbox', 'Production')),
    transaction_id text not null,
    original_transaction_id text not null,
    description text check (length(description) between 1 and 1000),
    avatar_action_key uuid,
    fitness_action_key uuid,
    revoked_at timestamptz,
    signed_at timestamptz not null,
    purchase_at timestamptz not null,
    evidence jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (environment, transaction_id),
    unique (environment, original_transaction_id),
    check ((description is null) = (avatar_action_key is null)),
    check (fitness_action_key is null or avatar_action_key is not null)
);
create index custom_character_purchases_account on private.custom_character_purchases (account_id, created_at desc);
alter table private.custom_character_purchases enable row level security;
revoke all on private.custom_character_purchases from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.custom_character_purchases
    for each row execute function private.maintain_row_timestamps();

alter table private.ai_requests add constraint ai_paid_character_resource
    foreign key (resource_id) references private.custom_character_purchases(id);
alter table private.ai_requests add constraint ai_paid_character_no_credits
    check (resource_id is null or (workflow in ('avatar', 'fitness') and credit_price = 0 and credit_state = 'none'));
create index ai_paid_character_requests on private.ai_requests (resource_id, workflow, created_at desc)
    where resource_id is not null;

commit;

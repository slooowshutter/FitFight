begin;

-- Each row gives one person free characters: 'signup' once per account, 'gift' from the admin.
-- A free character is a custom_character_purchases row with a free_claim_key instead of an Apple charge.
create table private.free_character_grants (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references public.profiles (user_id) on delete cascade,
    quantity integer not null check (quantity between 1 and 100),
    reason text not null check (reason ~ '^[a-z][a-z0-9_]{0,79}$'),
    granted_by uuid,
    operation_key uuid not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (operation_key, user_id)
);
create unique index free_character_grants_signup on private.free_character_grants (user_id) where reason = 'signup';
alter table private.free_character_grants enable row level security;
revoke all on private.free_character_grants from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.free_character_grants
    for each row execute function private.maintain_row_timestamps();

alter table private.custom_character_purchases
    add column free_claim_key uuid unique,
    alter column transaction_id drop not null,
    alter column original_transaction_id drop not null,
    alter column signed_at drop not null,
    alter column purchase_at drop not null,
    alter column evidence drop not null,
    add constraint custom_character_funding check (
        case when free_claim_key is null
            then transaction_id is not null and original_transaction_id is not null and signed_at is not null
                and purchase_at is not null and evidence is not null
            else transaction_id is null and original_transaction_id is null and signed_at is null
                and purchase_at is null and evidence is null and revoked_at is null
        end
    );

commit;

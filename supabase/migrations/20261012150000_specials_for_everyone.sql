-- Specials are no longer one of a kind: any account may own any number of Specials, each unlocked by one charge of
-- the consumable com.fitfight.mvp.special. Additive only: special_editions and special_transactions keep every row,
-- and an edition an account owned under the one-of-a-kind model stays owned.
begin;

create table private.special_purchases (
    id uuid primary key default gen_random_uuid(),
    account_id uuid not null references private.special_accounts(id),
    environment text not null check (environment in ('Sandbox', 'Production')),
    companion_id text not null check (companion_id like 'limited-%'),
    transaction_id text not null,
    original_transaction_id text not null,
    revoked_at timestamptz,
    signed_at timestamptz not null,
    purchase_at timestamptz not null,
    evidence jsonb not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (environment, transaction_id),
    unique (environment, original_transaction_id)
);
create index special_purchases_account on private.special_purchases (account_id, companion_id);
alter table private.special_purchases enable row level security;
revoke all on private.special_purchases from public, anon, authenticated, service_role, fitfight_backend_reader;
create trigger maintain_row_timestamps before update on private.special_purchases
    for each row execute function private.maintain_row_timestamps();

-- Integrity guard also covers older backend instances and direct profile writers.
create or replace function private.require_special_ownership()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.companion_id like 'limited-%' and (tg_op = 'INSERT' or new.companion_id is distinct from old.companion_id) then
        if not exists (
            select 1 from private.special_purchases as purchase
            join private.special_accounts as account on account.id = purchase.account_id
            where account.user_id = new.user_id and purchase.companion_id = new.companion_id
                and purchase.environment = account.environment and purchase.revoked_at is null
            for share of purchase
        ) and not exists (
            select 1 from private.special_editions as edition
            join private.special_accounts as account on account.id = edition.account_id
            where account.user_id = new.user_id and edition.companion_id = new.companion_id
                and edition.environment = account.environment and edition.state = 'owned'
            for share of edition
        ) then
            raise exception 'special_purchase_required' using errcode = 'P0001';
        end if;
    end if;
    return new;
end;
$$;
revoke all on function private.require_special_ownership() from public, anon, authenticated;

commit;

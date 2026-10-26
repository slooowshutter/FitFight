-- Specials are free (Marc, 24 Oct 2026): any account may wear any current Special without a charge. A retired Special,
-- never sold, still needs an edition or purchase the account owns. Additive only: every purchase row stays.
begin;

-- Integrity guard also covers older backend instances and direct profile writers.
create or replace function private.require_special_ownership()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    if new.companion_id like 'limited-%' and (tg_op = 'INSERT' or new.companion_id is distinct from old.companion_id)
        -- special_editions lists every Special; retired_at marks the first roster.
        and not exists (
            select 1 from private.special_editions as edition
            where edition.companion_id = new.companion_id and edition.retired_at is null
        ) then
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

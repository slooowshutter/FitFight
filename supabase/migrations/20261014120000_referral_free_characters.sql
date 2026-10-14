begin;

-- Free characters now come only from referrals and admin gifts (Marc, 14 Oct 2026). When a referred friend's first
-- Apple Health steps arrive, the referrer gets a 'referral' grant and the friend a 'referred' grant. Both use the
-- friend's user id as operation_key, so each referral gives at most one of each. New accounts get no 'signup' grant.
-- Marc took back every unused free character given before today: one 'taken_back' row per account with a negative
-- quantity. Grant rows are still never changed or removed.
alter table private.free_character_grants
    drop constraint free_character_grants_quantity_check,
    add constraint free_character_grants_quantity_check check (
        quantity between 1 and 100 or (reason = 'taken_back' and quantity < 0)
    );

insert into private.free_character_grants (user_id, quantity, reason, operation_key)
select remaining.user_id, -remaining.quantity, 'taken_back', gen_random_uuid()
from (
    select grants.user_id, sum(grants.quantity) - (
        select count(*) from private.custom_character_purchases as purchase
        join private.special_accounts as account on account.id = purchase.account_id
        where account.user_id = grants.user_id and purchase.free_claim_key is not null
    ) as quantity
    from private.free_character_grants as grants
    group by grants.user_id
) as remaining
where remaining.quantity > 0;

-- A free character can also unlock a Special: a special_purchases row with free_claim_key instead of an Apple charge.
alter table private.special_purchases
    add column free_claim_key uuid unique,
    alter column transaction_id drop not null,
    alter column original_transaction_id drop not null,
    alter column signed_at drop not null,
    alter column purchase_at drop not null,
    alter column evidence drop not null,
    add constraint special_purchase_funding check (
        case when free_claim_key is null
            then transaction_id is not null and original_transaction_id is not null and signed_at is not null
                and purchase_at is not null and evidence is not null
            else transaction_id is null and original_transaction_id is null and signed_at is null
                and purchase_at is null and evidence is null and revoked_at is null
        end
    );

commit;

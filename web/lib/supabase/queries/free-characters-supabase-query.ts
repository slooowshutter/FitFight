import type { Sql, TransactionSql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { readSpecialStore } from "@/lib/supabase/queries/specials-supabase-query";
import {
    freeCharacterReferralGrantsSchema,
    referralPayoutSchema,
} from "@/lib/types/ai/custom-character";
import type { LimitedCompanionId } from "@/lib/types/companions/companion";
import { specialClaimResultSchema } from "@/lib/types/companions/specials";

/**
 * Grants come from referrals and admin gifts; a 'taken_back' grant is negative. Each free character and each Special
 * unlocked for free uses one.
 */
export async function readFreeCharacters(sql: Sql | TransactionSql, userId: string) {
    // NOTE: Clamped, because a claim committed by an older backend while the take-back migration ran can leave -1.
    const [row] = await sql`select greatest(0,
        (select coalesce(sum(quantity), 0) from private.free_character_grants where user_id = ${userId})
        - (select count(*) from private.custom_character_purchases purchase
            join private.special_accounts account on account.id = purchase.account_id
            where account.user_id = ${userId} and purchase.free_claim_key is not null)
        - (select count(*) from private.special_purchases purchase
            join private.special_accounts account on account.id = purchase.account_id
            where account.user_id = ${userId} and purchase.free_claim_key is not null)) as remaining`;
    return Number(row.remaining);
}

/**
 * A referral pays out once the referred friend has Apple Health steps: one 'referral' character for the referrer and one
 * 'referred' character for the friend, both keyed by the friend's id, so a replay gives nothing. Without a user id it
 * pays every referral that is owed. Returns the referrers paid by this call, for their push. Only referrals recorded
 * since the program started (14 Oct 2026), within 7 days of the friend's signup, pay; older backends recorded any account.
 */
export async function grantReferralFreeCharacters(
    referredUserId: string | null,
    database: Sql = createDatabaseClient(),
) {
    return referralPayoutSchema.array().parse(await database`
        with owed as (
            select referral.referred_user_id, referral.referrer_user_id
            from private.referrals as referral
            join public.profiles as referrer on referrer.id = referral.referrer_user_id and referrer.deleted_at is null
            join public.profiles as friend on friend.id = referral.referred_user_id and friend.deleted_at is null
            where (${referredUserId}::uuid is null or referral.referred_user_id = ${referredUserId}::uuid)
                and referral.created_at >= '2026-10-14T00:00:00Z'
                and referral.created_at <= friend.created_at + interval '7 days'
                and not exists (select 1 from private.free_character_grants as given
                    where given.operation_key = referral.referred_user_id and given.user_id = referral.referrer_user_id)
                and exists (select 1 from private.activity_metrics as metric
                    join public.data_sources as source on source.id = metric.source_id and source.provider = 'apple_health'
                    where metric.user_id = referral.referred_user_id and metric.scope = 'day'
                        and metric.metric = 'steps' and metric.value > 0)
        ), granted as (
            insert into private.free_character_grants (user_id, quantity, reason, granted_by, operation_key)
            select referrer_user_id, 1, 'referral', referred_user_id, referred_user_id from owed
            union all
            select referred_user_id, 1, 'referred', referrer_user_id, referred_user_id from owed
            on conflict (operation_key, user_id) do nothing
            returning user_id, reason, operation_key
        )
        select granted.user_id as referrer_id,
            case when friend.handle_set_at is null then null else friend.handle end as friend_handle,
            coalesce(preferences.enabled, true) as notify
        from granted
        join public.profiles as friend on friend.id = granted.operation_key
        left join private.notification_preferences as preferences on preferences.user_id = granted.user_id
        where granted.reason = 'referral'
    `);
}

/** True while this account was referred and its own referral character waits for its first Apple Health steps. */
export async function readReferralPending(userId: string, database: Sql = createDatabaseClient()) {
    const [row] = await database`select
        exists (select 1 from private.referrals as referral
            join public.profiles as referrer on referrer.id = referral.referrer_user_id and referrer.deleted_at is null
            where referral.referred_user_id = ${userId})
        and not exists (select 1 from private.free_character_grants where user_id = ${userId} and reason = 'referred')
        as pending`;
    return row.pending === true;
}

/**
 * Unlocks a Special with one free character instead of an Apple charge. The client's key makes a retried request return
 * the same Special; a Special the account already owns uses nothing.
 */
export async function claimFreeSpecial(
    userId: string,
    claimKey: string,
    companionId: LimitedCompanionId,
    database: Sql = createDatabaseClient(),
) {
    const account = await readSpecialStore(userId, database);
    return database.begin(async (sql) => {
        await sql`select id from public.profiles where id = ${userId} for update`;
        const [existing] = await sql`select account_id, companion_id from private.special_purchases
            where free_claim_key = ${claimKey}`;
        if (existing) {
            if (existing.account_id !== account.app_account_token)
                throw new ApiError(409, "ai_request_conflict", "This free character belongs to another account");
            return specialClaimResultSchema.parse({ outcome: "owned", transaction_id: claimKey, companion_id: existing.companion_id });
        }
        const [owned] = await sql`
            select 1 from private.special_purchases
            where account_id = ${account.app_account_token} and environment = ${account.environment}
                and companion_id = ${companionId} and revoked_at is null
            union all
            select 1 from private.special_editions
            where account_id = ${account.app_account_token} and environment = ${account.environment}
                and companion_id = ${companionId} and state = 'owned'
            limit 1`;
        if (!owned) {
            if (await readFreeCharacters(sql, userId) < 1)
                throw new ApiError(409, "no_free_characters", "You have no free characters left");
            await sql`insert into private.special_purchases (account_id, environment, companion_id, free_claim_key)
                values (${account.app_account_token}, ${account.environment}, ${companionId}, ${claimKey})`;
        }
        return specialClaimResultSchema.parse({ outcome: "owned", transaction_id: claimKey, companion_id: companionId });
    });
}

/** The admin's list of referral characters, newest first. A deleted friend shows no username. */
export async function readReferralGrants(database: Sql = createDatabaseClient()) {
    const [total] = await database`select count(*)::int as count from private.free_character_grants where reason = 'referral'`;
    const grants = await database`
        select referrer.handle as referrer, friend.handle as friend, given.created_at
        from private.free_character_grants as given
        join public.profiles as referrer on referrer.id = given.user_id
        left join public.profiles as friend on friend.id = given.granted_by
        where given.reason = 'referral'
        order by given.created_at desc
        limit 100`;
    return freeCharacterReferralGrantsSchema.parse({ total: total.count, grants });
}

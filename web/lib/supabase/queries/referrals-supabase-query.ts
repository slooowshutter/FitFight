import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
    ClaimReferralRequest,
    ClaimReferralResponse,
} from "@/lib/types/referrals/referral";

export async function claimReferral(
    userId: string,
    input: ClaimReferralRequest,
    database: Sql = createDatabaseClient(),
): Promise<ClaimReferralResponse> {
    // First successful claim wins, including concurrent claims from different links. Only an account created at
    // most 7 days ago counts as a new friend.
    const [row] = await database`
        with recipient as (
            select id, created_at >= now() - interval '7 days' as is_new
            from public.profiles
            where id = ${userId} and deleted_at is null
        ), recorded as (
            insert into private.referrals (referred_user_id, referrer_user_id)
            select recipient.id, referrer.id
            from public.profiles as referrer
            join recipient on recipient.is_new
            where referrer.referral_code = ${input.code}
                and referrer.id <> recipient.id
                and referrer.deleted_at is null
            on conflict (referred_user_id) do nothing
            returning referred_user_id
        )
        select exists (select 1 from recorded) as recorded,
            exists (select 1 from recipient where not is_new) as account_not_new
    `;
    return { recorded: row.recorded, account_not_new: row.account_not_new };
}

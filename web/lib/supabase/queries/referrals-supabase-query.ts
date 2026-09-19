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
    // First successful claim wins, including concurrent claims from different links.
    const rows = await database`
        insert into private.referrals (referred_user_id, referrer_user_id)
        select recipient.id, referrer.id
        from public.profiles as referrer
        join public.profiles as recipient on recipient.id = ${userId}
        where referrer.referral_code = ${input.code}
            and referrer.id <> recipient.id
            and referrer.deleted_at is null
            and recipient.deleted_at is null
        on conflict (referred_user_id) do nothing
        returning referred_user_id
    `;
    return { recorded: rows.length === 1 };
}

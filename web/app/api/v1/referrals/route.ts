import { after } from "next/server";
import { rewardReferrals } from "@/lib/domain/referrals/referral-rewards";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { claimReferral } from "@/lib/supabase/queries/referrals-supabase-query";
import { claimReferralRequestSchema } from "@/lib/types/referrals/referral";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const parsed = claimReferralRequestSchema.safeParse(
        await readJson(request, 1024),
    );
    if (!parsed.success) {
        throw parsed.error;
    }
    const claim = await claimReferral(userId, parsed.data);
    // A friend who connected Apple Health before claiming is owed the referral characters now.
    if (claim.recorded) after(() => rewardReferrals(userId));
    return json(claim);
});

export const OPTIONS = corsPreflight;

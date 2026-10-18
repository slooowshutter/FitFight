import { ApiError, ERROR_CODES, apiRoute, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { mintProductionSignInToken } from "@/lib/supabase/queries/production-sign-in-supabase-query";
import { productionAccountByStagingAccount } from "@/lib/types/admin/fitfight-admin";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * The staging web app's Production switch: a one-time login to the admin's production account, so the admin never
 * signs in twice. Only the staging accounts in `productionAccountByStagingAccount` qualify.
 */
export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const productionUserId = productionAccountByStagingAccount[userId];
    if (!productionUserId) {
        throw new ApiError(
            403,
            ERROR_CODES.forbidden,
            "Only the FitFight admin can open Production",
        );
    }
    return json({
        token_hash: await mintProductionSignInToken(productionUserId),
    });
});

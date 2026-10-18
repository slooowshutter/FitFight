import { isLocalDevRequest } from "@/lib/dev/local-dev-request";
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
    // NOTE: `next dev` on this Mac only, even if the key ever reaches a deployed server: a staging login must not open
    // production anywhere a stolen staging session could use it.
    if (!isLocalDevRequest(request)) {
        throw new ApiError(
            503,
            ERROR_CODES.config,
            "Production opens only from localhost. Signing you in to production needs production's secret key, which is only in web/.env.local on your Mac (PRODUCTION_SUPABASE_SECRET_KEY), never on staging.fitfight.app. The Admin page still shows production numbers here.",
        );
    }
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

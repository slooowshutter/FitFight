import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json } from "@/lib/http";
import { readAdminViewer, verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readRecentSyncs } from "@/lib/supabase/queries/recent-syncs-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** The staging app shows this to the admin: testers who still sync here instead of production. */
export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    if (!isFitFightAdmin(await readAdminViewer(userId))) {
        throw new ApiError(403, ERROR_CODES.forbidden, "Only the FitFight admin can see who synced.");
    }
    return json(await readRecentSyncs());
});

export const OPTIONS = corsPreflight;

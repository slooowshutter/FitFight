import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { readAdminViewer, verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readFounderChallengers, readFounderId } from "@/lib/supabase/queries/founder-fight-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    if (!isFitFightAdmin(await readAdminViewer(userId))) {
        throw new ApiError(403, ERROR_CODES.forbidden, "Only the FitFight admin can see founder fights.");
    }
    const database = createDatabaseClient();
    return json(await readFounderChallengers(await readFounderId(database), database));
});

export const OPTIONS = corsPreflight;

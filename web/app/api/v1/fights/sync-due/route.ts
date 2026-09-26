import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
    closeDueFightsForUser,
    processDueNotifications,
} from "@/lib/supabase/queries/close-due-fights-supabase-query";
import { createDatabaseClient } from "@/lib/supabase/postgres";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const result = await closeDueFightsForUser(userId);
    const notifications = await processDueNotifications(
        new Date(),
        createDatabaseClient(),
    );
    return json({ ...result, notifications });
});

export const OPTIONS = corsPreflight;

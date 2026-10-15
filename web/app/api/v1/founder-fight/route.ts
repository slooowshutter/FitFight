import { apiRoute, corsPreflight, json } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createFounderFight, readFounderId } from "@/lib/supabase/queries/founder-fight-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Onboarding's one tap: start, or return, the caller's repeating 1v1 against the founder. */
export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const database = createDatabaseClient();
    return json(await createFounderFight(userId, await readFounderId(database), database));
});

export const OPTIONS = corsPreflight;

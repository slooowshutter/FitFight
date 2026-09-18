import { apiRoute, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readOwnRivalries } from "@/lib/supabase/queries/shared-profiles-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await readOwnRivalries(userId));
});

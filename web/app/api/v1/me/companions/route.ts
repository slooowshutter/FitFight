import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readCompanionPrompts } from "@/lib/supabase/queries/companions-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await readCompanionPrompts(userId));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

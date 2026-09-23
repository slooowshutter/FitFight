import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readSpecialStore } from "@/lib/supabase/queries/specials-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await readSpecialStore(userId));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readCustomCharacterStore } from "@/lib/supabase/queries/custom-characters-supabase-query";

export const runtime = "nodejs";
export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await readCustomCharacterStore(userId));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { listFriendSuggestions } from "@/lib/supabase/queries/friend-suggestions-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await listFriendSuggestions(userId));
});

export const OPTIONS = corsPreflight;

import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { listProfileFriends } from "@/lib/supabase/queries/profile-friends-supabase-query";
import { friendsQuerySchema } from "@/lib/types/friends/friendship";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const query = friendsQuerySchema.parse(Object.fromEntries(new URL(request.url).searchParams));
    return json(await listProfileFriends(userId, query));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

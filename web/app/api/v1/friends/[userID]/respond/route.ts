import { apiRoute, json, readJson, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { changeFriendship } from "@/lib/supabase/queries/profile-friends-supabase-query";
import { profileUserIDSchema } from "@/lib/types/profiles/shared-profile";
import { respondToFriendRequestSchema } from "@/lib/types/friends/friendship";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ userID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const targetId = profileUserIDSchema.parse(params.userID);
    const input = respondToFriendRequestSchema.parse(await readJson(request));
    return json(await changeFriendship(userId, targetId, input.action));
});

export const OPTIONS = corsPreflight;

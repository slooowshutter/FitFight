import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { changeFriendship } from "@/lib/supabase/queries/profile-friends-supabase-query";
import { profileUserIDSchema } from "@/lib/types/profiles/shared-profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ userID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    return json(await changeFriendship(userId, profileUserIDSchema.parse(params.userID), "request"));
});

export const OPTIONS = corsPreflight;

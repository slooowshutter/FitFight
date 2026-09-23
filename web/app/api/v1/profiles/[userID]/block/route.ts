import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { blockProfile } from "@/lib/supabase/queries/profile-friends-supabase-query";
import { profileUserIDSchema } from "@/lib/types/profiles/shared-profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ userID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    return json(await blockProfile(userId, profileUserIDSchema.parse(params.userID)));
});

export const OPTIONS = corsPreflight;

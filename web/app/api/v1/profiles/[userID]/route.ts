import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readSharedProfile } from "@/lib/supabase/queries/shared-profiles-supabase-query";
import { profileReadQuerySchema, profileUserIDSchema } from "@/lib/types/profiles/shared-profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ userID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const targetId = profileUserIDSchema.parse(params.userID);
    const query = profileReadQuerySchema.parse(Object.fromEntries(new URL(request.url).searchParams));
    return json(await readSharedProfile(userId, targetId, query.preview));
});

export const OPTIONS = corsPreflight;

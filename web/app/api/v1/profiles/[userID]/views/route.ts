import { apiRoute, json, readJson, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { recordProfileView } from "@/lib/supabase/queries/profile-events-supabase-query";
import { profileUserIDSchema, profileViewRequestSchema } from "@/lib/types/profiles/shared-profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ userID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const targetId = profileUserIDSchema.parse(params.userID);
    const input = profileViewRequestSchema.parse(await readJson(request));
    return json(await recordProfileView(userId, targetId, input));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

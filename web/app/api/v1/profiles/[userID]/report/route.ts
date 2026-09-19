import { apiRoute, json, readJson, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { reportProfile } from "@/lib/supabase/queries/profile-friends-supabase-query";
import { profileUserIDSchema, profileReportRequestSchema } from "@/lib/types/profiles/shared-profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ userID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const targetId = profileUserIDSchema.parse(params.userID);
    const input = profileReportRequestSchema.parse(await readJson(request));
    return json(await reportProfile(userId, targetId, input.reason));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

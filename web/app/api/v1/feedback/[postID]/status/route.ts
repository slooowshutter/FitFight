import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { changeFeedbackStatus } from "@/lib/supabase/queries/feedback-supabase-query";
import { changeFeedbackStatusRequestSchema } from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ postID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const postId = requireUuid(params.postID, "postID");
    const parsed = changeFeedbackStatusRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) throw parsed.error;
    return json(await changeFeedbackStatus(userId, postId, parsed.data));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

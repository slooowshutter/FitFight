import { apiRoute, corsPreflight, json, readJson, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createFeedbackComment } from "@/lib/supabase/queries/feedback-supabase-query";
import { createFeedbackCommentRequestSchema } from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const postId = requireUuid(params.postID, "postID");
  const parsed = createFeedbackCommentRequestSchema.safeParse(await readJson(request));
  if (!parsed.success) {
    throw parsed.error;
  }
  return json(await createFeedbackComment(userId, postId, parsed.data), 201);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

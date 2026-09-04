import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getFeedbackPost } from "@/lib/supabase/queries/feedback-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ postID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const postId = requireUuid(params.postID, "postID");
  return json(await getFeedbackPost(userId, postId));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

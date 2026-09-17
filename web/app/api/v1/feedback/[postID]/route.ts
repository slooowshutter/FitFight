import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { feedbackWorkflowAccess } from "@/lib/admin/feedback-workflow-access";
import {
    isFitFightAdmin,
    readAdminViewer,
} from "@/lib/admin/is-fitfight-admin";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getFeedbackPost } from "@/lib/supabase/queries/feedback-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ postID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const postId = requireUuid(params.postID, "postID");
    const detail = await getFeedbackPost(userId, postId);
    const viewer = await readAdminViewer(userId);
    const workflow = feedbackWorkflowAccess(userId);
    return json({
        post: { ...detail.post, metadata: {} },
        comments: detail.comments.map((comment) => ({
            ...comment,
            metadata: {},
        })),
        can_launch_fix: workflow.enabled ? workflow.isAdmin : isFitFightAdmin(viewer),
        can_manage_status: workflow.enabled && workflow.isAdmin,
    });
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

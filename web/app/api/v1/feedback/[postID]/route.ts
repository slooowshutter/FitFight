import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import {
    readAdminViewer,
    verifyUser,
} from "@/lib/supabase/queries/auth-supabase-query";
import {
    deleteFeedbackPost,
    getFeedbackPost,
} from "@/lib/supabase/queries/feedback-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ postID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const postId = requireUuid(params.postID, "postID");
    const detail = await getFeedbackPost(userId, postId);
    const viewer = await readAdminViewer(userId);
    return json({
        post: { ...detail.post, metadata: {} },
        comments: detail.comments.map((comment) => ({
            ...comment,
            metadata: {},
        })),
        can_launch_fix: isFitFightAdmin(viewer),
        can_delete: isFitFightAdmin(viewer),
    });
});

export const DELETE = apiRoute<{ postID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const postId = requireUuid(params.postID, "postID");
    await deleteFeedbackPost(userId, postId);
    return json({ deleted: true });
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

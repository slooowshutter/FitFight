import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import {
    readAdminViewer,
    verifyUser,
} from "@/lib/supabase/queries/auth-supabase-query";
import {
    deleteFeedbackPost,
    getFeedbackPost,
    updateFeedbackPost,
} from "@/lib/supabase/queries/feedback-supabase-query";
import { updateFeedbackPostRequestSchema } from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ postID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const postId = requireUuid(params.postID, "postID");
    const detail = await getFeedbackPost(userId, postId);
    const viewer = await readAdminViewer(userId);
    const admin = isFitFightAdmin(viewer);
    return json({
        post: { ...detail.post, metadata: {} },
        comments: detail.comments.map((comment) => ({
            ...comment,
            metadata: {},
        })),
        can_launch_fix: admin,
        can_delete: admin || detail.post.mine,
        can_edit: detail.post.mine,
    });
});

export const PATCH = apiRoute<{ postID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const postId = requireUuid(params.postID, "postID");
    const parsed = updateFeedbackPostRequestSchema.safeParse(
        await readJson(request),
    );
    if (!parsed.success) {
        throw parsed.error;
    }
    const updated = await updateFeedbackPost(userId, postId, parsed.data);
    return json({ post: { ...updated.post, metadata: {} } });
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

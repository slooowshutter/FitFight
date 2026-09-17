import {
    ApiError,
    ERROR_CODES,
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import { launchFeedbackFixAgent } from "@/lib/cursor/launch-feedback-fix-agent";
import { markAppFeedbackBacklogStatus } from "@/lib/notion/create-app-feedback-item";
import { notionAppFeedbackAgentStatus } from "@/lib/types/notion/product-backlog";
import {
    readAdminViewer,
    verifyUser,
} from "@/lib/supabase/queries/auth-supabase-query";
import { getFeedbackPost } from "@/lib/supabase/queries/feedback-supabase-query";
import {
    feedbackMetadataSchema,
    launchFeedbackFixRequestSchema,
    type FeedbackMetadata,
} from "@/lib/types/feedback/feedback";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export const POST = apiRoute<{ postID: string }>(
    async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const viewer = await readAdminViewer(userId);
        if (!isFitFightAdmin(viewer)) {
            throw new ApiError(
                403,
                ERROR_CODES.forbidden,
                "Only the FitFight admin can start a Cursor agent.",
            );
        }
        const postId = requireUuid(params.postID, "postID");
        const parsed = launchFeedbackFixRequestSchema.safeParse(
            await readJson(request),
        );
        if (!parsed.success) {
            throw parsed.error;
        }
        const version = request.headers.get("X-FitFight-Version")?.trim();
        const build = request.headers.get("X-FitFight-Build")?.trim();
        const fromHeaders = feedbackMetadataSchema.safeParse({
            ...(version ? { app_version: version } : {}),
            ...(build ? { app_build: build } : {}),
        });
        const senderMetadata: FeedbackMetadata = {
            ...(fromHeaders.success ? fromHeaders.data : {}),
            ...parsed.data.metadata,
        };
        const detail = await getFeedbackPost(userId, postId);
        const launched = await launchFeedbackFixAgent(
            detail,
            fetch,
            senderMetadata,
        );
        await markAppFeedbackBacklogStatus(
            detail.post.id,
            notionAppFeedbackAgentStatus,
        );
        return json(launched, 201);
    },
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

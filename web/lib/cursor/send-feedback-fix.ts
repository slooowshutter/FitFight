import { randomUUID } from "node:crypto";
import { feedbackWorkflowAccess } from "@/lib/admin/feedback-workflow-access";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { launchFeedbackFixAgent } from "@/lib/cursor/launch-feedback-fix-agent";
import { changeFeedbackStatus } from "@/lib/supabase/queries/feedback-supabase-query";
import type { FeedbackMetadata, FeedbackPostDetail } from "@/lib/types/feedback/feedback";

/** Only an explicit Send calls the provider. Its failure leaves the committed approval intact. */
export async function sendFeedbackFix(
    userId: string,
    detail: FeedbackPostDetail,
    senderMetadata: FeedbackMetadata,
    launch = launchFeedbackFixAgent,
    changeStatus = changeFeedbackStatus,
) {
    const access = feedbackWorkflowAccess(userId);
    if (!access.enabled) return launch(detail, fetch, senderMetadata);
    if (!access.isAdmin) {
        throw new ApiError(403, ERROR_CODES.forbidden, "Only Marc can start work on a request.");
    }
    const current = detail.post.workflow_status;
    if (current === undefined) {
        throw new ApiError(503, ERROR_CODES.config, "Request progress is not ready yet.");
    }
    await changeStatus(userId, detail.post.id, {
        expected_status: current,
        status: "approved",
        operation_id: randomUUID(),
    });
    const launched = await launch(detail, fetch, senderMetadata);
    await changeStatus(userId, detail.post.id, {
        expected_status: "approved",
        status: "building",
        operation_id: randomUUID(),
    });
    return launched;
}

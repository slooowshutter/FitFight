import { apiRoute, json, readJson, requireUuid } from "@/lib/http";
import { requireAiOperator } from "@/lib/domain/ai/operators";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { recoverAiRequest } from "@/lib/supabase/queries/ai-requests-supabase-query";
import { aiRecoverySchema } from "@/lib/types/ai/credits";
import {
    correlateAiRequest,
    observeAiHttp,
} from "@/lib/observability/ai-request-log";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = observeAiHttp(
    apiRoute<{ requestID: string }>(async (request, { params }) => {
        const { userId } = await verifyUser(request);
        correlateAiRequest({ user_id: userId });
        requireAiOperator(userId);
        const requestId = requireUuid(params.requestID, "requestID");
        const input = aiRecoverySchema.parse(await readJson(request, 2048));
        const saved = await recoverAiRequest(userId, requestId, input);
        correlateAiRequest({
            request_id: saved.id,
            workflow_id: saved.workflow_version.workflowId,
            version_id: saved.workflow_version.versionId,
            run_id: saved.run_handle?.runId ?? null,
        });
        return json({ request_id: saved.id, status: saved.status });
    }),
    "recover",
    "operator",
);

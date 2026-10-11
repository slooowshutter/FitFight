import { ApiError } from "@/lib/http";
import { readAiRun } from "@/lib/domain/ai/workflow-requests";
import { dueAiRequests } from "@/lib/supabase/queries/ai-requests-supabase-query";
import {
    deferCustomCharacterPurchase,
    dueCustomCharacterPurchases,
} from "@/lib/supabase/queries/custom-characters-supabase-query";
import { advancePaidCharacter, deferredCharacterStartCodes } from "@/lib/domain/ai/paid-character";
import {
    correlateAiRequest,
    observeAiCall,
} from "@/lib/observability/ai-request-log";
import type { AiReconciliationDependencies } from "@/lib/types/ai/service";

/**
 * At most four status reads per invocation. Unknown starts are never resubmitted or timed out into refunds.
 * A paid character whose run just settled advances in the same invocation instead of waiting for the next one.
 */
export async function reconcileAiRuns(
    deps: AiReconciliationDependencies = {
        due: dueAiRequests,
        read: readAiRun,
        paidDue: dueCustomCharacterPurchases,
        paidAdvance: advancePaidCharacter,
        paidDefer: deferCustomCharacterPurchase,
    },
) {
    const requests = await deps.due();
    let checked = 0;
    let settled = 0;
    const deadline = performance.now() + 40_000;
    for (const request of requests) {
        if (performance.now() >= deadline) break;
        const started = performance.now();
        correlateAiRequest({
            user_id: request.user_id,
            request_id: request.id,
            workflow_id: request.workflow_version.workflowId,
            version_id: request.workflow_version.versionId ?? null,
            run_id: request.run_handle?.runId ?? null,
        });
        try {
            const result = await deps.read(
                request.user_id,
                request.id,
                undefined,
                "reconciler",
            );
            checked++;
            if (["completed", "failed", "cancelled"].includes(result.status)) {
                settled++;
                if (request.resource_id !== null && deps.paidAdvance) {
                    try {
                        await deps.paidAdvance(request.user_id, request.resource_id, {});
                    } catch (error) {
                        // The paid pass below and the next run retry; one purchase must not stop the batch.
                        if (!(error instanceof ApiError)) throw error;
                    }
                }
            }
            observeAiCall({
                leg: "reconciler",
                operation: "observe_run",
                status: null,
                elapsed_ms: Math.round(performance.now() - started),
                outcome: result.status,
                code: "code" in result ? result.code : null,
                upstream_code: null,
            });
        } catch (error) {
            if (!(error instanceof ApiError)) throw error;
            observeAiCall({
                leg: "reconciler",
                operation: "observe_run",
                status: null,
                elapsed_ms: Math.round(performance.now() - started),
                outcome: "read_rejected",
                code: error.code,
                upstream_code: null,
            });
            if (["ai_busy", "ai_unavailable"].includes(error.code)) break;
            if (
                ![
                    "ai_status_unavailable",
                    "not_found",
                    "ai_invalid_result",
                ].includes(error.code)
            )
                throw error;
        }
    }
    if (deps.paidDue && deps.paidAdvance && performance.now() < deadline) {
        for (const purchase of await deps.paidDue()) {
            if (performance.now() >= deadline) break;
            try {
                await deps.paidAdvance(purchase.userId, purchase.id, {});
            } catch (error) {
                if (!(error instanceof ApiError)) throw error;
                // One purchase that keeps failing must not stop or starve the others.
                if (!deferredCharacterStartCodes.includes(error.code)) await deps.paidDefer?.(purchase.id);
            }
        }
    }
    correlateAiRequest({
        user_id: null,
        request_id: null,
        workflow_id: null,
        version_id: null,
        run_id: null,
    });
    return { checked, settled };
}

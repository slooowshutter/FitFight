import {
    observeAiHttp,
    correlateAiRequest,
} from "@/lib/observability/ai-request-log";
import { ApiError, apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { startAiRun } from "@/lib/domain/ai/workflow-requests";
import { createAiRunRequestSchema } from "@/lib/types/ai/workflow";
import { aiRequestReservationSchema } from "@/lib/types/ai/request";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = observeAiHttp(
    apiRoute(async (request) => {
        const { userId } = await verifyUser(request);
        correlateAiRequest({ user_id: userId });
        const key = aiRequestReservationSchema.shape.idempotencyKey.safeParse(
            request.headers.get("Idempotency-Key"),
        );
        if (!key.success) {
            throw new ApiError(
                400,
                "missing_idempotency_key",
                "A UUID Idempotency-Key is required.",
            );
        }
        const input = createAiRunRequestSchema.parse(
            await readJson(request, 32768),
        );
        const result = await startAiRun(userId, input, key.data);
        return json(
            result,
            ["pending", "running"].includes(result.status) ? 202 : 200,
        );
    }),
    "start",
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

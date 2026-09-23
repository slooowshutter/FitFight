import { observeAiCall } from "@/lib/observability/ai-request-log";
import { ApiError } from "@/lib/http";
import {
    blendApiKeySchema,
    blendErrorEnvelopeSchema,
    blendRunEnvelopeSchema,
    blendOutputSchema,
    blendStartResponseSchema,
    type BlendRateLimit,
    type BlendRunHandle,
    type BlendRunResponse,
    type BlendTransportResult,
    type BlendWorkflowVersion,
} from "@/lib/types/blend/workflow";

const BLEND_URL = "https://www.tryblend.ai/api/v1";
const HTTP_TIMEOUT_MS = 10_000;

async function blendRequest(
    path: string,
    method: "POST" | "GET",
    body: string | undefined,
    fetchImpl: typeof fetch,
): Promise<BlendTransportResult<unknown>> {
    const started = performance.now();
    let httpStatus: number | null = null;
    let upstreamCode: string | null = null;
    let failureCode: string | null = null;
    try {
        const key = blendApiKeySchema.safeParse(process.env.BLEND_API_KEY);
        if (!key.success) {
            throw new ApiError(
                503,
                "ai_unavailable",
                "This feature is temporarily unavailable on our side.",
            );
        }

        let response: Response;
        try {
            response = await fetchImpl(`${BLEND_URL}${path}`, {
                method,
                headers: {
                    Authorization: `Bearer ${key.data}`,
                    Accept: "application/json",
                    "Content-Type": "application/json",
                },
                body,
                redirect: "error",
                cache: "no-store",
                signal: AbortSignal.timeout(HTTP_TIMEOUT_MS),
            });
        } catch {
            // A lost start response cannot establish whether Blend accepted paid work.
            throw new ApiError(
                503,
                method === "POST"
                    ? "ai_start_unconfirmed"
                    : "ai_status_unavailable",
                method === "POST"
                    ? "We couldn't confirm whether this request started. Check again later."
                    : "We couldn't check the result. Check again.",
            );
        }

        httpStatus = response.status;
        const rateLimit: BlendRateLimit = {};
        const remaining = response.headers.get("X-RateLimit-Remaining");
        const reset = response.headers.get("X-RateLimit-Reset");
        const retryAfter = response.headers.get("Retry-After");
        if (
            remaining !== null &&
            /^\d+$/.test(remaining) &&
            Number.isSafeInteger(Number(remaining)) &&
            Number(remaining) <= 2_147_483_647
        ) {
            rateLimit.remaining = Number(remaining);
        }
        if (
            reset !== null &&
            /^\d+$/.test(reset) &&
            Number.isSafeInteger(Number(reset)) &&
            Number(reset) > 0 &&
            Number(reset) <= 8_640_000_000_000_000
        ) {
            rateLimit.resetAt = Number(reset);
        }
        if (
            retryAfter !== null &&
            /^\d+$/.test(retryAfter) &&
            Number.isSafeInteger(Number(retryAfter)) &&
            Number(retryAfter) > 0
        ) {
            rateLimit.retryAfterSeconds = Math.min(Number(retryAfter), 86_400);
        }

        let raw: unknown;
        try {
            raw = await response.json();
        } catch {
            raw = null;
        }
        if (response.status === (method === "POST" ? 202 : 200)) {
            return { data: raw, rateLimit };
        }

        const upstream = blendErrorEnvelopeSchema.safeParse(raw);
        const code = upstream.success ? upstream.data.error.code : undefined;
        upstreamCode = code ?? null;
        const detail = {
            upstream: { status: response.status, code },
            rateLimit,
        };
        if (response.status === 429) {
            throw new ApiError(
                503,
                "ai_busy",
                "AI is busy. Try again later.",
                detail,
                {
                    retry_after_seconds: rateLimit.retryAfterSeconds,
                },
            );
        }
        if ([400, 401, 402, 404].includes(response.status)) {
            throw new ApiError(
                503,
                "ai_unavailable",
                "This feature is temporarily unavailable on our side.",
                detail,
            );
        }
        throw new ApiError(
            503,
            method === "POST"
                ? "ai_start_unconfirmed"
                : "ai_status_unavailable",
            method === "POST"
                ? "We couldn't confirm whether this request started. Check again later."
                : "We couldn't check the result. Check again.",
            detail,
        );
    } catch (error) {
        if (error instanceof ApiError) failureCode = error.code;
        throw error;
    } finally {
        observeAiCall({
            leg: "blend",
            outcome: null,
            operation: method === "POST" ? "start" : "read",
            status: httpStatus,
            elapsed_ms: Math.round(performance.now() - started),
            code: failureCode,
            upstream_code: upstreamCode,
        });
    }
}

/** Call only after reserving admission. An uncertain start must never be replayed. */
export async function startBlendWorkflow(
    workflow: BlendWorkflowVersion,
    inputs: Record<string, unknown>,
    fetchImpl: typeof fetch = fetch,
): Promise<BlendTransportResult<BlendRunHandle>> {
    const response = await blendRequest(
        "/responses",
        "POST",
        JSON.stringify({ ...workflow, inputs, stream: false }),
        fetchImpl,
    );
    const parsed = blendStartResponseSchema.safeParse(response.data);
    if (
        !parsed.success ||
        (parsed.data.published_workflow_id != null &&
            parsed.data.published_workflow_id !== workflow.workflowId) ||
        (parsed.data.published_workflow_version_id != null &&
            parsed.data.published_workflow_version_id !== workflow.versionId)
    ) {
        throw new ApiError(
            503,
            "ai_start_unconfirmed",
            "We couldn't confirm whether this request started. Check again later.",
            { rateLimit: response.rateLimit },
        );
    }
    return {
        data: { ...workflow, runId: parsed.data.run_id },
        rateLimit: response.rateLimit,
    };
}

/** Reads an existing run; callers must authorize its owner and validate feature output. */
export async function readBlendWorkflowRun(
    run: BlendRunHandle,
    fetchImpl: typeof fetch = fetch,
): Promise<BlendTransportResult<BlendRunResponse>> {
    const response = await blendRequest(
        `/runs/${encodeURIComponent(run.runId)}`,
        "GET",
        undefined,
        fetchImpl,
    );
    const parsed = blendRunEnvelopeSchema.safeParse(response.data);
    if (
        !parsed.success ||
        parsed.data.id !== run.runId ||
        (parsed.data.published_workflow_id != null &&
            parsed.data.published_workflow_id !== run.workflowId) ||
        (parsed.data.published_workflow_version_id != null &&
            parsed.data.published_workflow_version_id !== run.versionId)
    ) {
        throw new ApiError(
            503,
            "ai_status_unavailable",
            "We couldn't check the result. Check again.",
            { rateLimit: response.rateLimit },
        );
    }
    const output = blendOutputSchema
        .nullish()
        .safeParse(
            ["failed", "cancelled"].includes(parsed.data.status)
                ? null
                : parsed.data.output,
        );
    if (!output.success) {
        throw new ApiError(
            502,
            parsed.data.status === "completed"
                ? "ai_invalid_result"
                : "ai_status_unavailable",
            parsed.data.status === "completed"
                ? "We couldn't read the generated result."
                : "We couldn't check the result. Check again.",
            {
                rateLimit: response.rateLimit,
                providerCompletedAt: parsed.data.completed_at,
            },
        );
    }
    return {
        data: { ...parsed.data, output: output.data },
        rateLimit: response.rateLimit,
    };
}

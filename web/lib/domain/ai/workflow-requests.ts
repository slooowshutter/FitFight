import { correlateAiRequest } from "@/lib/observability/ai-request-log";
import { createHash } from "node:crypto";
import { ApiError } from "@/lib/http";
import { startBlendWorkflow, readBlendWorkflowRun } from "@/lib/blend/client";
import {
    blendWorkflowConfiguration,
    blendProviderConfiguration,
} from "@/lib/blend/workflows";
import {
    reserveAiRequest,
    claimAiRequestPoll,
    finishAiRequestAttempt,
    markAiSubmission,
} from "@/lib/supabase/queries/ai-requests-supabase-query";
import { aiErrorMessages, aiErrorCodeSchema } from "@/lib/types/ai/error";
import {
    aiRunResponseSchema,
    blendAvatarOutputSchema,
    blendFitnessOutputSchema,
    blendGroupPhotoOutputSchema,
    legacyAvatarVersionId,
    type AiRunResponse,
    type CreateAiRunRequest,
} from "@/lib/types/ai/workflow";
import type { AiRequestRecord, AiRequestUpdate } from "@/lib/types/ai/request";
import type { AiRequestDependencies } from "@/lib/types/ai/service";
import { blendErrorDetailSchema } from "@/lib/types/blend/workflow";

const dependencies: AiRequestDependencies = {
    reserve: reserveAiRequest,
    claim: claimAiRequestPoll,
    finish: finishAiRequestAttempt,
    submit: markAiSubmission,
    start: startBlendWorkflow,
    read: readBlendWorkflowRun,
};

function requestResponse(request: AiRequestRecord): AiRunResponse {
    const parsed = aiRunResponseSchema.safeParse({
        request_id: request.id,
        workflow: request.workflow,
        status: request.status === "starting" ? "pending" : request.status,
        poll_after_seconds: Math.max(
            3,
            Math.ceil((request.next_poll_at.getTime() - Date.now()) / 1000),
        ),
        data: request.result,
        code: request.error_code,
        error:
            request.error_code === null
                ? null
                : aiErrorMessages[request.error_code],
    });
    if (!parsed.success) {
        throw new ApiError(
            502,
            "ai_invalid_result",
            aiErrorMessages.ai_invalid_result,
            {
                request_id: request.id,
                workflow_id: request.workflow_version.workflowId,
                version_id: request.workflow_version.versionId,
            },
            { request_id: request.id },
        );
    }
    return parsed.data;
}

/** The verified user owns the avatar; client parameters never select Blend configuration. */
export async function startAiRun(
    userId: string,
    input: CreateAiRunRequest,
    idempotencyKey: string,
    deps: AiRequestDependencies = dependencies,
): Promise<AiRunResponse> {
    let config = null;
    try {
        config = blendWorkflowConfiguration(input.workflow);
    } catch (error) {
        if (!(error instanceof ApiError) || error.code !== "ai_unavailable")
            throw error;
        // Recovery is still possible when new-start configuration has been removed.
    }
    if (config !== null)
        correlateAiRequest({
            user_id: userId,
            workflow_id: config.version.workflowId,
            version_id: config.version.versionId,
        });
    const reservation = await deps.reserve(
        userId,
        {
            workflow: input.workflow,
            resourceId: null,
            idempotencyKey,
            requestHash: createHash("sha256")
                .update(JSON.stringify(input))
                .digest("hex"),
            version: config?.enabled ? config.version : null,
            creditPrice: config?.enabled ? config.creditPrice : null,
            sourceRequestIds:
                input.workflow === "avatar"
                    ? []
                    : input.workflow === "fitness"
                      ? [input.parameters.avatar_request_id]
                      : input.parameters.characters.map(
                            (character) => character.avatar_request_id,
                        ),
        },
        config?.enabled ? config.limits : null,
    );
    const request = reservation.request;
    const diagnostic = {
        request_id: request.id,
        workflow_id: request.workflow_version.workflowId,
        version_id: request.workflow_version.versionId,
    };
    correlateAiRequest(
        {
            user_id: userId,
            ...diagnostic,
            run_id: request.run_handle?.runId ?? null,
        },
        reservation.shouldStart ? "submitted" : "recovered",
    );
    if (!reservation.shouldStart) return requestResponse(request);
    if (request.lease_token === null)
        throw new Error("AI start reservation has no lease");

    await deps.submit(userId, request.id, request.lease_token);

    let started;
    try {
        const inputs =
            input.workflow === "avatar"
                ? {
                      [request.workflow_version.versionId ===
                      legacyAvatarVersionId
                          ? "variable:prompt:user_request"
                          : "describe_your_animal"]:
                          input.parameters.description,
                  }
                : input.workflow === "fitness"
                  ? {
                        character_portrait: reservation.portraits,
                        identity_details: input.parameters.identity_details,
                    }
                  : {
                        character_portraits: reservation.portraits,
                        scene: input.parameters.scene,
                        cast_roster: input.parameters.characters
                            .map(
                                (character, index) =>
                                    `${index + 1}. ${character.identity_details}`,
                            )
                            .join("\n"),
                    };
        started = await deps.start(request.workflow_version, inputs);
    } catch (error) {
        if (!(error instanceof ApiError)) throw error;
        const parsedCode = aiErrorCodeSchema.safeParse(error.code);
        if (!parsedCode.success) throw error;
        const code = parsedCode.data;
        const detail = blendErrorDetailSchema.safeParse(error.detail);
        try {
            const rejected = await deps.finish(
                userId,
                request.id,
                request.lease_token,
                {
                    status:
                        code === "ai_start_unconfirmed"
                            ? "start_unconfirmed"
                            : "failed",
                    runHandle: null,
                    result: null,
                    errorCode: code,
                },
                detail.success && detail.data.rateLimit
                    ? detail.data.rateLimit
                    : {},
            );
            if (rejected === null)
                throw new Error("The AI start lease was superseded");
        } catch {
            // Recovery must keep the same request even when saving a rejection fails.
            throw new ApiError(
                503,
                "ai_start_unconfirmed",
                aiErrorMessages.ai_start_unconfirmed,
                diagnostic,
                { request_id: request.id },
            );
        }
        throw new ApiError(
            error.status,
            error.code,
            error.message,
            {
                ...diagnostic,
                ...blendErrorDetailSchema.parse(error.detail ?? {}),
            },
            {
                ...error.clientContext,
                request_id: request.id,
            },
        );
    }

    correlateAiRequest({ run_id: started.data.runId });
    let saved: AiRequestRecord | null;
    try {
        saved = await deps.finish(
            userId,
            request.id,
            request.lease_token,
            {
                status: "pending",
                runHandle: started.data,
                result: null,
                errorCode: null,
            },
            started.rateLimit,
        );
    } catch {
        // The reservation remains unresolved if Blend accepted before persistence failed.
        throw new ApiError(
            503,
            "ai_start_unconfirmed",
            aiErrorMessages.ai_start_unconfirmed,
            {
                ...diagnostic,
                run_id: started.data.runId,
            },
            { request_id: request.id },
        );
    }
    if (saved === null) {
        throw new ApiError(
            503,
            "ai_start_unconfirmed",
            aiErrorMessages.ai_start_unconfirmed,
            diagnostic,
            { request_id: request.id },
        );
    }
    return requestResponse(saved);
}

/** Reads through the owner's durable request record; polling never starts another workflow. */
export async function readAiRun(
    userId: string,
    requestId: string,
    deps: AiRequestDependencies = dependencies,
    source: "app" | "reconciler" = "app",
): Promise<AiRunResponse> {
    const config = blendProviderConfiguration();
    const claimed = await deps.claim(
        userId,
        requestId,
        config.limits,
        undefined,
        source,
    );
    const request = claimed.request;
    const diagnostic = {
        request_id: request.id,
        workflow_id: request.workflow_version.workflowId,
        version_id: request.workflow_version.versionId,
        run_id: request.run_handle?.runId ?? null,
    };
    correlateAiRequest({ user_id: userId, ...diagnostic }, "observed");
    if (!claimed.shouldPoll) return requestResponse(request);
    if (request.run_handle === null || request.lease_token === null) {
        throw new Error("AI poll reservation has no run or lease");
    }

    let response;
    try {
        response = await deps.read(request.run_handle);
    } catch (error) {
        if (!(error instanceof ApiError)) throw error;
        const detail = blendErrorDetailSchema.safeParse(error.detail);
        const invalidResult = error.code === "ai_invalid_result";
        const saved = await deps.finish(
            userId,
            request.id,
            request.lease_token,
            {
                status: invalidResult
                    ? "failed"
                    : request.status === "running"
                      ? "running"
                      : "pending",
                runHandle: request.run_handle,
                result: null,
                errorCode: invalidResult ? "ai_invalid_result" : null,
                providerCompletedAt: detail.success
                    ? detail.data.providerCompletedAt
                    : null,
            },
            detail.success && detail.data.rateLimit
                ? detail.data.rateLimit
                : {},
        );
        if (saved === null) {
            throw new ApiError(
                503,
                "ai_status_unavailable",
                aiErrorMessages.ai_status_unavailable,
                diagnostic,
                { request_id: request.id },
            );
        }
        if (invalidResult) return requestResponse(saved);
        throw new ApiError(
            error.status,
            error.code,
            error.message,
            {
                ...diagnostic,
                ...blendErrorDetailSchema.parse(error.detail ?? {}),
            },
            {
                ...error.clientContext,
                request_id: request.id,
            },
        );
    }

    const run = response.data;
    const update: AiRequestUpdate = {
        status: run.status,
        providerCompletedAt: run.completed_at,
        runHandle: request.run_handle,
        result: null,
        errorCode: null,
    };
    if (run.status === "failed" || run.status === "cancelled") {
        update.errorCode =
            run.status === "failed" ? "ai_failed" : "ai_cancelled";
    } else if (run.status === "completed") {
        const schema =
            request.workflow === "avatar"
                ? blendAvatarOutputSchema
                : request.workflow === "fitness"
                  ? blendFitnessOutputSchema
                  : blendGroupPhotoOutputSchema;
        const output = schema.safeParse(run.output);
        if (output.success) {
            update.result = output.data;
        } else {
            update.status = "failed";
            update.errorCode =
                run.output != null &&
                Object.values(run.output).some((items) =>
                    items.some((item) => item.status === "failed"),
                )
                    ? "ai_failed"
                    : "ai_invalid_result";
        }
    }
    const saved = await deps.finish(
        userId,
        request.id,
        request.lease_token,
        update,
        response.rateLimit,
    );
    if (saved === null) {
        throw new ApiError(
            503,
            "ai_status_unavailable",
            aiErrorMessages.ai_status_unavailable,
            diagnostic,
            { request_id: request.id },
        );
    }
    return requestResponse(saved);
}

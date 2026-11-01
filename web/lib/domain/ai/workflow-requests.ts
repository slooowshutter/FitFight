import { correlateAiRequest } from "@/lib/observability/ai-request-log";
import { createHash } from "node:crypto";
import { ApiError } from "@/lib/http";
import { readAiWorkflowRun, startAiWorkflow } from "@/lib/ai/runner";
import { blendWorkflowConfiguration } from "@/lib/blend/workflows";
import {
    reserveAiRequest,
    claimAiRequestPoll,
    finishAiRequestAttempt,
    markAiSubmission,
} from "@/lib/supabase/queries/ai-requests-supabase-query";
import { aiErrorMessages, aiErrorCodeSchema } from "@/lib/types/ai/error";
import {
    aiAvatarResultSchema,
    aiCompanionLinesResultSchema,
    aiFitnessResultSchema,
    aiPromptCheckResultSchema,
    aiRunResponseSchema,
    blendConfiguration,
    blendAvatarOutputSchema,
    blendCompanionLinesOutputSchema,
    blendFitnessOutputSchema,
    blendPromptCheckOutputSchema,
    blendGroupPhotoOutputSchema,
    legacyAvatarVersionId,
    type AiRunResponse,
    type CreateAiRunRequest,
} from "@/lib/types/ai/workflow";
import type { AiRequestRecord, AiRequestUpdate } from "@/lib/types/ai/request";
import type { AiRequestDependencies } from "@/lib/types/ai/service";
import { aiRunnerPrefix } from "@/lib/types/ai/step";
import { blendErrorDetailSchema, blendOutputSchema } from "@/lib/types/blend/workflow";

const dependencies: AiRequestDependencies = {
    reserve: reserveAiRequest,
    claim: claimAiRequestPoll,
    finish: finishAiRequestAttempt,
    submit: markAiSubmission,
    start: startAiWorkflow,
    read: readAiWorkflowRun,
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
                version_id: request.workflow_version.versionId ?? null,
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
    paidCharacterId: string | null = null,
): Promise<AiRunResponse> {
    let config = null;
    try {
        config = blendWorkflowConfiguration(input.workflow, paidCharacterId !== null);
    } catch (error) {
        if (!(error instanceof ApiError) || error.code !== "ai_unavailable")
            throw error;
        // Recovery is still possible when new-start configuration has been removed.
    }
    if (config !== null)
        correlateAiRequest({
            user_id: userId,
            workflow_id: config.version.workflowId,
            version_id: config.version.versionId ?? null,
        });
    const reservation = await deps.reserve(
        userId,
        {
            workflow: input.workflow,
            description:
                input.workflow === "fitness"
                    ? input.parameters.identity_details
                    : input.workflow === "group_photo"
                      ? input.parameters.scene
                      : input.parameters.description,
            resourceId: paidCharacterId,
            idempotencyKey,
            requestHash: createHash("sha256")
                .update(JSON.stringify(input))
                .digest("hex"),
            version: config?.version ?? null,
            creditPrice: config?.creditPrice ?? null,
            sourceRequestIds:
                input.workflow === "avatar" || input.workflow === "prompt_check"
                    ? []
                    : input.workflow === "group_photo"
                      ? input.parameters.characters.map(
                            (character) => character.avatar_request_id,
                        )
                      : [input.parameters.avatar_request_id],
        },
        config?.limits ?? null,
    );
    const request = reservation.request;
    const diagnostic = {
        request_id: request.id,
        workflow_id: request.workflow_version.workflowId,
        version_id: request.workflow_version.versionId ?? null,
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
        // NOTE: Blend sends a bare URL to its LLM nodes as application/octet-stream, which the provider rejects. Typed files keep the PNG media type.
        const portraits = reservation.portraits.map((url) => ({
            id: url,
            name: "portrait.png",
            url,
            size: 0,
            mimeType: "image/png",
            extension: "png",
            mediaCategory: "image",
        }));
        const inputs = request.workflow_version.workflowId.startsWith(aiRunnerPrefix)
            ? input.workflow === "avatar" || input.workflow === "prompt_check"
                ? input.parameters
                : input.workflow === "fitness"
                  ? { portraits: reservation.portraits, identity_details: input.parameters.identity_details }
                  : input.workflow === "companion_lines"
                    ? {
                          portraits: reservation.portraits,
                          description: input.parameters.description,
                          language: input.parameters.language,
                          avoid: input.parameters.avoid.map((option) => `${option.name}: ${option.line}`).join("\n"),
                      }
                    : {
                          portraits: reservation.portraits,
                          scene: input.parameters.scene,
                          cast_roster: input.parameters.characters
                              .map((character, index) => `${index + 1}. ${character.identity_details}`)
                              .join("\n"),
                      }
            : input.workflow === "avatar"
                ? {
                      [request.workflow_version.versionId ===
                      legacyAvatarVersionId
                          ? "variable:prompt:user_request"
                          : "describe_your_animal"]:
                          input.parameters.description,
                  }
                : input.workflow === "fitness"
                  ? {
                        character_portrait: portraits,
                        identity_details: input.parameters.identity_details,
                    }
                  : input.workflow === "companion_lines"
                    ? {
                          character_portrait: portraits,
                          description: input.parameters.description,
                          language: input.parameters.language,
                          avoid: input.parameters.avoid
                              .map((option) => `${option.name}: ${option.line}`)
                              .join("\n"),
                      }
                    : input.workflow === "prompt_check"
                      ? { description: input.parameters.description, language: input.parameters.language }
                    : {
                        character_portraits: portraits,
                        scene: input.parameters.scene,
                        cast_roster: input.parameters.characters
                            .map(
                                (character, index) =>
                                    `${index + 1}. ${character.identity_details}`,
                            )
                            .join("\n"),
                    };
        // A step can finish before the run handle is saved, so its deletion link travels with the workflow input.
        started = await deps.start(request.workflow_version, request.workflow_version.workflowId.startsWith(aiRunnerPrefix)
            ? { ...inputs, request_id: request.id }
            : inputs);
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
        // The reservation remains unresolved if the run started before persistence failed.
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
    const claimed = await deps.claim(
        userId,
        requestId,
        blendConfiguration.limits,
        undefined,
        source,
    );
    const request = claimed.request;
    const diagnostic = {
        request_id: request.id,
        workflow_id: request.workflow_version.workflowId,
        version_id: request.workflow_version.versionId ?? null,
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
                providerResponse:
                    invalidResult && detail.success
                        ? detail.data.providerResponse
                        : undefined,
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
                // The raw envelope belongs on the private request row only; this detail reaches the server error log.
                ...blendErrorDetailSchema.omit({ providerResponse: true }).parse(error.detail ?? {}),
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
        update.providerResponse = response.providerResponse;
    } else if (run.status === "completed") {
        // A FitFight workflow returns the result itself; a Blend run wraps it in labelled output items.
        const runner = request.run_handle.workflowId.startsWith(aiRunnerPrefix);
        const schema = runner
            ? request.workflow === "avatar" || request.workflow === "group_photo"
                ? aiAvatarResultSchema
                : request.workflow === "fitness"
                  ? aiFitnessResultSchema
                  : request.workflow === "companion_lines"
                    ? aiCompanionLinesResultSchema
                    : aiPromptCheckResultSchema
            : request.workflow === "avatar"
                ? blendAvatarOutputSchema
                : request.workflow === "fitness"
                  ? blendFitnessOutputSchema
                  : request.workflow === "companion_lines"
                    ? blendCompanionLinesOutputSchema
                    : request.workflow === "prompt_check"
                      ? blendPromptCheckOutputSchema
                      : blendGroupPhotoOutputSchema;
        const output = schema.safeParse(run.output);
        if (output.success) {
            update.result = output.data;
        } else {
            update.status = "failed";
            update.providerResponse = response.providerResponse;
            const items = blendOutputSchema.safeParse(run.output);
            update.errorCode =
                !runner && items.success &&
                Object.values(items.data).some((list) =>
                    list.some((item) => item.status === "failed"),
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

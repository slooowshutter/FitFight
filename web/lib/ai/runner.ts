import { ZodError } from "zod";
import { getRun, start } from "workflow/api";
import { readBlendWorkflowRun, startBlendWorkflow } from "@/lib/blend/client";
import { ApiError } from "@/lib/http";
import { avatar, companionLines, fitness, groupPhoto, promptCheck, raceStart, trail } from "@/lib/ai/workflows";
import {
    aiRunnerPrefix,
    aiRunnerWorkflowSchema,
    avatarInputSchema,
    companionLinesInputSchema,
    fitnessInputSchema,
    groupPhotoInputSchema,
    promptCheckInputSchema,
    raceStartInputSchema,
    trailInputSchema,
} from "@/lib/types/ai/step";
import type { AiRunState } from "@/lib/types/ai/request";
import { aiRunnerEnvironmentSchema } from "@/lib/types/ai/workflow";
import type { BlendRunHandle, BlendTransportResult, BlendWorkflowVersion } from "@/lib/types/blend/workflow";

/**
 * Starts a FitFight workflow, or a Blend one while Blend runs are still configured or in progress. Call only
 * after reserving admission: an uncertain start must never be replayed.
 */
export async function startAiWorkflow(
    workflow: BlendWorkflowVersion,
    inputs: Record<string, unknown>,
): Promise<BlendTransportResult<BlendRunHandle>> {
    if (!workflow.workflowId.startsWith(aiRunnerPrefix)) return startBlendWorkflow(workflow, inputs);
    if (!aiRunnerEnvironmentSchema.safeParse(process.env).success)
        throw new ApiError(503, "ai_unavailable", "This feature is temporarily unavailable on our side.");
    const name = aiRunnerWorkflowSchema.parse(workflow.workflowId.slice(aiRunnerPrefix.length));
    const run = await (async () => {
        try {
            switch (name) {
                case "avatar": return await start(avatar, [avatarInputSchema.parse(inputs)]);
                case "fitness": return await start(fitness, [fitnessInputSchema.parse(inputs)]);
                case "group_photo": return await start(groupPhoto, [groupPhotoInputSchema.parse(inputs)]);
                case "companion_lines": return await start(companionLines, [companionLinesInputSchema.parse(inputs)]);
                case "prompt_check": return await start(promptCheck, [promptCheckInputSchema.parse(inputs)]);
                case "trail": return await start(trail, [trailInputSchema.parse(inputs)]);
                case "race_start": return await start(raceStart, [raceStartInputSchema.parse(inputs)]);
            }
        } catch (error) {
            if (error instanceof ZodError) throw error;
            // A lost start cannot establish whether the run exists, so the paid work is held, never replayed.
            throw new ApiError(
                503,
                "ai_start_unconfirmed",
                "We couldn't confirm whether this request started. Check again later.",
            );
        }
    })();
    return { data: { ...workflow, runId: run.runId }, rateLimit: {} };
}

/** Reads a run's state. A completed run's output is its workflow's return value, checked by the caller. */
export async function readAiWorkflowRun(
    run: BlendRunHandle,
): Promise<BlendTransportResult<AiRunState> & { providerResponse?: unknown }> {
    if (!run.workflowId.startsWith(aiRunnerPrefix)) return readBlendWorkflowRun(run);
    try {
        const handle = getRun<unknown>(run.runId);
        const status = await handle.status;
        const completedAt = ["completed", "failed", "cancelled"].includes(status) ? await handle.completedAt : undefined;
        return {
            data: {
                id: run.runId,
                status,
                output: status === "completed" ? await handle.returnValue : null,
                completed_at: completedAt?.toISOString() ?? null,
            },
            rateLimit: {},
            providerResponse: { status },
        };
    } catch {
        throw new ApiError(503, "ai_status_unavailable", "We couldn't check the result. Check again.");
    }
}

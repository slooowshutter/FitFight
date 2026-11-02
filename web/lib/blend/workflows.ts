import { ApiError } from "@/lib/http";
import { aiRunnerPrefix } from "@/lib/types/ai/step";
import {
    aiRunnerEnvironmentSchema,
    blendConfiguration,
    blendEnvironmentSchema,
    aiWorkflowConfigurationSchema,
    type AiWorkflow,
} from "@/lib/types/ai/workflow";
import { blendWorkflowVersionSchema } from "@/lib/types/blend/workflow";

/**
 * Each workflow has an explicit version and a server-selected price. A FitFight workflow's version is the deployed
 * commit; it needs the AI workflows' OpenRouter key, and a Blend one needs Blend's.
 */
export function blendWorkflowConfiguration(workflow: AiWorkflow, paidCharacter = false) {
    const { runner, workflowId, versionId, creditPrice } = blendConfiguration.workflows[workflow];
    if (!(runner === "blend" ? blendEnvironmentSchema : aiRunnerEnvironmentSchema).safeParse(process.env).success)
        throw new ApiError(
            503,
            "ai_unavailable",
            "This feature is temporarily unavailable on our side.",
        );
    const provider = { limits: blendConfiguration.limits };
    const version = blendWorkflowVersionSchema.safeParse(runner === "blend"
        ? { workflowId, versionId }
        : { workflowId: `${aiRunnerPrefix}${workflow}`, versionId: process.env.VERCEL_GIT_COMMIT_SHA ?? "local" });
    if (!version.success)
        throw new ApiError(503, "ai_unavailable", "This feature is temporarily unavailable on our side.");
    // A prompt check is free text work done before buying, like a paid character's own runs.
    if (paidCharacter || workflow === "prompt_check") return { ...provider, version: version.data, creditPrice: 0 };
    const parsed = aiWorkflowConfigurationSchema.safeParse({
        version: version.data,
        creditPrice,
    });
    if (!parsed.success)
        throw new ApiError(
            503,
            "ai_unavailable",
            "This feature is temporarily unavailable on our side.",
        );
    return { ...provider, ...parsed.data };
}

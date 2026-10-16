import { ApiError } from "@/lib/http";
import {
    blendConfiguration,
    blendEnvironmentSchema,
    aiWorkflowConfigurationSchema,
    type AiWorkflow,
} from "@/lib/types/ai/workflow";
import { blendWorkflowVersionSchema } from "@/lib/types/blend/workflow";

/** Polling needs transport limits, but must not depend on the current publication or new-start price. */
export function blendProviderConfiguration() {
    if (!blendEnvironmentSchema.safeParse(process.env).success)
        throw new ApiError(
            503,
            "ai_unavailable",
            "This feature is temporarily unavailable on our side.",
        );
    return { limits: blendConfiguration.limits };
}

/** Each workflow has an explicit immutable publication and a server-selected price. */
export function blendWorkflowConfiguration(workflow: AiWorkflow, paidCharacter = false) {
    const provider = blendProviderConfiguration();
    const { workflowId, versionId, creditPrice } =
        blendConfiguration.workflows[workflow];
    const version = blendWorkflowVersionSchema.safeParse({ workflowId, versionId });
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

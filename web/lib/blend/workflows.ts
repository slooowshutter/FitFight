import { ApiError } from "@/lib/http";
import {
    blendEnvironmentSchema,
    aiWorkflowConfigurationSchema,
    aiWorkflowEnvironmentPrefixes,
    type AiWorkflow,
} from "@/lib/types/ai/workflow";

/** Polling needs transport limits, but must not depend on the current publication or new-start price. */
export function blendProviderConfiguration() {
    const parsed = blendEnvironmentSchema.safeParse(process.env);
    if (!parsed.success)
        throw new ApiError(
            503,
            "ai_unavailable",
            "This feature is temporarily unavailable on our side.",
        );
    const env = parsed.data;
    return {
        enabled: env.BLEND_ENABLED === "true",
        limits: {
            globalDailyStarts: env.BLEND_GLOBAL_DAILY_STARTS,
            globalConcurrentRuns: env.BLEND_GLOBAL_CONCURRENT_RUNS,
            providerRequestsPerMinute: env.BLEND_REQUESTS_PER_MINUTE,
        },
    };
}

/** Each workflow has an explicit immutable publication and a server-selected price. */
export function blendWorkflowConfiguration(workflow: AiWorkflow) {
    const provider = blendProviderConfiguration();
    const prefix = aiWorkflowEnvironmentPrefixes[workflow];
    const parsed = aiWorkflowConfigurationSchema.safeParse({
        version: {
            workflowId: process.env[`${prefix}_WORKFLOW_ID`],
            versionId: process.env[`${prefix}_VERSION_ID`],
        },
        creditPrice:
            workflow === "avatar" ? 1 : process.env[`${prefix}_CREDIT_PRICE`],
    });
    if (!parsed.success)
        throw new ApiError(
            503,
            "ai_unavailable",
            "This feature is temporarily unavailable on our side.",
        );
    return { ...provider, ...parsed.data };
}

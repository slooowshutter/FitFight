import { z } from "zod";

export const blendApiKeySchema = z.string().trim().startsWith("bai_").min(8);

export const blendWorkflowVersionSchema = z.object({
    workflowId: z.string().min(1).max(200),
    versionId: z.string().min(1).max(200),
});

export const blendRunHandleSchema = blendWorkflowVersionSchema.extend({
    runId: z.string().min(1).max(200),
});

export const blendStartResponseSchema = z.object({
    run_id: z.string().min(1).max(200),
    status: z.literal("pending"),
    created_at: z.string().datetime({ offset: true }),
    published_workflow_id: z.string().nullish(),
    published_workflow_version_id: z.string().nullish(),
});

export const blendRunStateValues = [
    "pending",
    "running",
    "completed",
    "failed",
    "cancelled",
] as const;

export const blendOutputItemStateValues = [
    "pending",
    "running",
    "completed",
    "failed",
] as const;

export const blendOutputPartSchema = z.discriminatedUnion("type", [
    z.object({ type: z.literal("text"), text: z.string() }),
    z.object({ type: z.literal("json"), data: z.unknown() }),
    z.object({ type: z.literal("image"), url: z.string().url() }),
    z.object({ type: z.literal("video"), url: z.string().url() }),
    z.object({
        type: z.literal("file"),
        url: z.string().url(),
        mime_type: z.string().optional(),
    }),
]);

export const blendOutputSchema = z.record(
    z.array(
        z.object({
            id: z.string(),
            item_index: z.number().int().nonnegative(),
            status: z.enum(blendOutputItemStateValues),
            parts: z.array(blendOutputPartSchema),
        }),
    ),
);

export const blendRunEnvelopeSchema = z.object({
    id: z.string().min(1).max(200),
    status: z.enum(blendRunStateValues),
    published_workflow_id: z.string().nullish(),
    published_workflow_version_id: z.string().nullish(),
    output: z.unknown(),
    completed_at: z.string().datetime({ offset: true }).nullish(),
});

export const blendRunResponseSchema = blendRunEnvelopeSchema.extend({
    output: blendOutputSchema.nullish(),
});

export const blendErrorCodeValues = [
    "invalid_api_key",
    "rate_limit_exceeded",
    "insufficient_credits",
    "not_found",
    "published_workflow_not_found",
    "published_workflow_version_not_found",
    "invalid_input_fields",
    "workflow_graph_corrupt",
] as const;

export const blendErrorEnvelopeSchema = z.object({
    error: z.object({
        code: z.enum(blendErrorCodeValues).optional(),
    }),
});

export const blendRateLimitSchema = z.object({
    remaining: z.number().int().nonnegative().optional(),
    resetAt: z.number().int().positive().optional(),
    retryAfterSeconds: z.number().int().positive().max(86_400).optional(),
});

export const blendErrorDetailSchema = z.object({
    rateLimit: blendRateLimitSchema.optional(),
    upstream: z
        .object({
            status: z.number().int(),
            code: z.enum(blendErrorCodeValues).optional(),
        })
        .optional(),
    providerCompletedAt: z.string().datetime({ offset: true }).nullish(),
});

export type BlendApiKey = z.infer<typeof blendApiKeySchema>;
export type BlendStartResponse = z.infer<typeof blendStartResponseSchema>;
export type BlendOutputPart = z.infer<typeof blendOutputPartSchema>;
export type BlendRunEnvelope = z.infer<typeof blendRunEnvelopeSchema>;
export type BlendErrorEnvelope = z.infer<typeof blendErrorEnvelopeSchema>;
export type BlendErrorDetail = z.infer<typeof blendErrorDetailSchema>;
export type BlendWorkflowVersion = z.infer<typeof blendWorkflowVersionSchema>;
export type BlendRunHandle = z.infer<typeof blendRunHandleSchema>;
export type BlendOutput = z.infer<typeof blendOutputSchema>;
export type BlendRunResponse = z.infer<typeof blendRunResponseSchema>;
export type BlendRateLimit = z.infer<typeof blendRateLimitSchema>;

export type BlendTransportResult<T> = {
    data: T;
    rateLimit: BlendRateLimit;
};

import { z } from "zod";

const amount = z.coerce.number().nullable();

/** One row of the AI section's model, step or person tables, as their queries return it. */
export const aiStepTableRowSchema = z.object({
    label: z.string(),
    model: z.string().nullable().optional(),
    calls: z.coerce.number().int(),
    failed: z.coerce.number().int(),
    median_ms: amount.optional().transform((value) => value ?? null),
    slow_ms: amount.optional().transform((value) => value ?? null),
    first_token_ms: amount.optional().transform((value) => value ?? null),
    tokens_in: amount.optional().transform((value) => value ?? null),
    tokens_out: amount.optional().transform((value) => value ?? null),
    per_call: amount.optional(),
    cost: amount,
    azure_calls: z.coerce.number().int().optional(),
    paid: amount.optional(),
    bought: z.coerce.number().int().optional(),
    free: z.coerce.number().int().optional(),
});

/** One model call of the AI section's call list. */
export const aiCallTableRowSchema = z.object({
    label: z.string(),
    started_at: z.coerce.date(),
    workflow: z.string(),
    step: z.string(),
    attempt: z.coerce.number().int(),
    model: z.string(),
    upstream: z.string().nullable(),
    status: z.string(),
    median_ms: z.coerce.number(),
    first_token_ms: amount,
    tokens_in: amount,
    tokens_out: amount,
    cost: amount,
    error: z.string().nullable(),
    handle: z.string().nullable(),
});

export type AiStepTableRow = z.infer<typeof aiStepTableRowSchema>;
export type AiCallTableRow = z.infer<typeof aiCallTableRowSchema>;

import { z } from "zod";
import { jsonValueSchema } from "@/lib/types/activity/activity-pipeline";

export const whoopEnvironmentSchema = z.object({
    clientSecret: z.string().min(1),
    tokenEncryptionKey: z
        .string()
        .base64()
        .refine(
            (value) => Buffer.from(value, "base64").byteLength === 32,
            "must be a base64-encoded 32-byte key",
        ),
});

export const whoopTokenResponseSchema = z.object({
    access_token: z.string().min(1),
    refresh_token: z.string().min(1),
    expires_in: z.number().int().positive(),
});

export const whoopTokenErrorSchema = z.object({
    error: z.string(),
});

export const whoopTokensSchema = z.object({
    access_token: z.string().min(1),
    refresh_token: z.string().min(1),
});

export const whoopProfileSchema = z.object({
    user_id: z.number().int().positive(),
});

export const whoopRecordSchema = z.record(jsonValueSchema);

export const whoopPageSchema = z.object({
    records: z.array(whoopRecordSchema),
    next_token: z.string().nullish(),
});

/** The fields FitFight reads from a stored WHOOP record. Everything else stays in the raw payload. */
export const whoopRecordFieldsSchema = z.object({
    id: z.union([z.string().min(1), z.number().int()]).optional(),
    sleep_id: z.string().min(1).optional(),
    start: z.string().datetime({ offset: true }).optional(),
    end: z.string().datetime({ offset: true }).nullish(),
});

export const whoopWebhookSchema = z.object({
    user_id: z.number().int().positive(),
    id: z.union([z.string().min(1), z.number().int()]),
    /** recovery, sleep or workout, then .updated or .deleted. Unknown future types still get a 2xx. */
    type: z.string().min(1),
    trace_id: z.string().optional(),
});

export const whoopConnectionRowSchema = z.object({
    user_id: z.string().uuid(),
    whoop_user_id: z.coerce.number().int().nullable(),
    tokens_ciphertext: z.string().nullable(),
    tokens_iv: z.string().nullable(),
    tokens_tag: z.string().nullable(),
    access_token_expires_at: z.date().nullable(),
    last_synced_at: z.date().nullable(),
    history_synced_at: z.date().nullable(),
});

/** What WHOOP's redirect handed the app. The app posts it with its own sign-in, binding it to that account. */
export const whoopFinishRequestSchema = z
    .object({
        code: z.string().min(1).max(2048),
        state: z.string().length(8),
    })
    .strict();

export const whoopConnectionResponseSchema = z.object({
    connected: z.boolean(),
    last_synced_at: z.string().datetime().nullable(),
    history_synced_at: z.string().datetime().nullable(),
});

export type WhoopEnvironment = z.infer<typeof whoopEnvironmentSchema>;
export type WhoopTokenResponse = z.infer<typeof whoopTokenResponseSchema>;
export type WhoopConnectionRow = z.infer<typeof whoopConnectionRowSchema>;
export type WhoopConnectionResponse = z.infer<
    typeof whoopConnectionResponseSchema
>;

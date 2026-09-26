import { z } from "zod";
import { applePurchaseEnvironmentSchema } from "@/lib/types/apple/special-purchase";
import { customCharacterProductId } from "@/lib/types/apple/custom-character-purchase";
import { aiRequestStateValues } from "@/lib/types/ai/request";

export const customCharacterConfigurationSchema = z.object({
    enabled: z.enum(["true", "false"]).default("false"),
});

export const customCharacterPurchaseRowSchema = z.object({
    id: z.string().uuid(),
    account_id: z.string().uuid(),
    environment: applePurchaseEnvironmentSchema,
    transaction_id: z.string(),
    original_transaction_id: z.string(),
    description: z.string().nullable(),
    avatar_action_key: z.string().uuid().nullable(),
    fitness_action_key: z.string().uuid().nullable(),
    revoked_at: z.coerce.date().nullable(),
    signed_at: z.coerce.date(),
    purchase_at: z.coerce.date(),
});

export const customCharacterProgressSchema = z.object({
    id: z.string().uuid(),
    description: z.string().nullable(),
    stage: z.enum(["portrait", "fitness"]).nullable(),
    status: z.enum(["ready", "generating", "retryable", "needs_support", "complete", "refunded"]),
    request_id: z.string().uuid().nullable(),
    poll_after_seconds: z.number().int().positive().nullable(),
});

export const customCharacterStoreSchema = z.object({
    app_account_token: z.string().uuid(),
    environment: applePurchaseEnvironmentSchema,
    purchases_enabled: z.boolean(),
    product_id: z.literal(customCharacterProductId),
    characters: z.array(customCharacterProgressSchema),
});

export const customCharacterClaimRequestSchema = z.object({
    signed_transaction: z.string().min(1).max(30_000),
}).strict();

export const customCharacterAdvanceRequestSchema = z.object({
    description: z.string().trim().min(1).max(1000).optional(),
    retry: z.boolean().optional(),
}).strict();

export const customCharacterPurchaseIdSchema = z.string().uuid();

export const customCharacterAttemptSchema = z.object({
    resource_id: z.string().uuid(),
    request_id: z.string().uuid(),
    workflow: z.enum(["avatar", "fitness"]),
    status: z.enum(aiRequestStateValues),
    next_poll_at: z.coerce.date(),
});

export const customCharacterClaimResultSchema = z.object({
    purchase_id: z.string().uuid(),
    refunded: z.boolean(),
});

export type CustomCharacterPurchaseRow = z.infer<typeof customCharacterPurchaseRowSchema>;
export type CustomCharacterProgress = z.infer<typeof customCharacterProgressSchema>;
export type CustomCharacterStore = z.infer<typeof customCharacterStoreSchema>;
export type CustomCharacterAdvanceRequest = z.infer<typeof customCharacterAdvanceRequestSchema>;
export type CustomCharacterAttempt = z.infer<typeof customCharacterAttemptSchema>;
export type CustomCharacterStage =
    | { kind: "existing"; requestId: string }
    | { kind: "avatar"; key: string; description: string }
    | { kind: "fitness"; key: string; description: string; avatarRequestId: string };

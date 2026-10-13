import { z } from "zod";
import { applePurchaseEnvironmentSchema } from "@/lib/types/apple/special-purchase";
import { customCharacterProductId } from "@/lib/types/apple/custom-character-purchase";
import { aiRequestStateValues } from "@/lib/types/ai/request";

export const customCharacterPurchaseRowSchema = z.object({
    id: z.string().uuid(),
    account_id: z.string().uuid(),
    environment: applePurchaseEnvironmentSchema,
    transaction_id: z.string().nullable(),
    original_transaction_id: z.string().nullable(),
    description: z.string().nullable(),
    avatar_action_key: z.string().uuid().nullable(),
    fitness_action_key: z.string().uuid().nullable(),
    revoked_at: z.coerce.date().nullable(),
    signed_at: z.coerce.date().nullable(),
    purchase_at: z.coerce.date().nullable(),
    free_claim_key: z.string().uuid().nullable(),
    portraits_notified_at: z.coerce.date().nullable(),
    poses_notified_at: z.coerce.date().nullable(),
});

export const customCharacterPortraitRowSchema = z.object({
    id: z.string().uuid(),
    purchase_id: z.string().uuid(),
    slot: z.number().int().min(1).max(3),
    action_key: z.string().uuid(),
    selected_at: z.coerce.date().nullable(),
});

/** `status` keeps the values older apps decode; `phase` adds the portrait choice. */
export const customCharacterPhaseValues = [
    "ready", "portraits", "choosing", "poses", "complete", "retryable", "needs_support", "refunded",
] as const;

export const customCharacterCandidateSchema = z.object({
    id: z.string().uuid(),
    slot: z.number().int().min(1).max(3),
    status: z.enum(["pending", "completed", "failed", "needs_support"]),
    image_url: z.string().url().nullable(),
    selected: z.boolean(),
});

export const customCharacterProgressSchema = z.object({
    id: z.string().uuid(),
    description: z.string().nullable(),
    stage: z.enum(["portrait", "fitness"]).nullable(),
    status: z.enum(["ready", "generating", "retryable", "needs_support", "complete", "refunded"]),
    request_id: z.string().uuid().nullable(),
    poll_after_seconds: z.number().int().positive().nullable(),
    phase: z.enum(customCharacterPhaseValues),
    portrait_url: z.string().url().nullable(),
    candidates: z.array(customCharacterCandidateSchema),
});

export const customCharacterStoreSchema = z.object({
    app_account_token: z.string().uuid(),
    environment: applePurchaseEnvironmentSchema,
    purchases_enabled: z.boolean(),
    product_id: z.literal(customCharacterProductId),
    /** Characters this person can still create without paying. */
    free_characters: z.number().int().nonnegative(),
    characters: z.array(customCharacterProgressSchema),
});

export const customCharacterClaimRequestSchema = z.object({
    signed_transaction: z.string().min(1).max(30_000),
    description: z.string().trim().min(1).max(1000).optional(),
}).strict();

export const customCharacterFreeClaimRequestSchema = z.object({
    description: z.string().trim().min(1).max(1000),
}).strict();

/** The Idempotency-Key header of a free claim or a gift. */
export const freeCharacterKeySchema = z.string().uuid().toLowerCase();

export const freeCharacterGiftRequestSchema = z.union([
    z.object({ quantity: z.number().int().min(1).max(100), username: z.string().trim().min(1).max(30) }).strict(),
    z.object({ quantity: z.number().int().min(1).max(100), everyone: z.literal(true) }).strict(),
]);

export const freeCharacterGiftResultSchema = z.object({
    people: z.number().int().nonnegative(),
    quantity: z.number().int().positive(),
});

export const customCharacterAdvanceRequestSchema = z.object({
    description: z.string().trim().min(1).max(1000).optional(),
    retry: z.boolean().optional(),
    choose_portrait: z.boolean().optional(),
}).strict();

export const customCharacterChooseRequestSchema = z.object({
    candidate_id: z.string().uuid(),
}).strict();

export const customCharacterPurchaseIdSchema = z.string().uuid();

export const customCharacterAttemptSchema = z.object({
    resource_id: z.string().uuid(),
    request_id: z.string().uuid(),
    workflow: z.enum(["avatar", "fitness"]),
    status: z.enum(aiRequestStateValues),
    next_poll_at: z.coerce.date(),
    idempotency_key: z.string().uuid(),
    image_url: z.string().url().nullable(),
});

export const customCharacterClaimResultSchema = z.object({
    purchase_id: z.string().uuid(),
    refunded: z.boolean(),
});

export type CustomCharacterPurchaseRow = z.infer<typeof customCharacterPurchaseRowSchema>;
export type CustomCharacterProgress = z.infer<typeof customCharacterProgressSchema>;
export type CustomCharacterStore = z.infer<typeof customCharacterStoreSchema>;
export type CustomCharacterAdvanceRequest = z.infer<typeof customCharacterAdvanceRequestSchema>;
export type FreeCharacterGiftRequest = z.infer<typeof freeCharacterGiftRequestSchema>;
export type CustomCharacterAttempt = z.infer<typeof customCharacterAttemptSchema>;
export type CustomCharacterStage =
    | { kind: "existing"; requestId: string }
    | { kind: "portraits"; description: string; starts: string[]; pending: string[] }
    | { kind: "avatar"; key: string; description: string }
    | { kind: "fitness"; key: string; description: string; avatarRequestId: string };

import { z } from "zod";
import { applePurchaseEnvironmentSchema } from "@/lib/types/apple/special-purchase";
import {
    limitedCompanionIdSchema,
    specialCompanionIdSchema,
} from "@/lib/types/companions/companion";

export const specialsConfigurationSchema = z.object({
    environment: applePurchaseEnvironmentSchema,
});
export const specialAccountSchema = z.object({
    id: z.string().uuid(),
    user_id: z.string().uuid().nullable(),
    environment: applePurchaseEnvironmentSchema,
});
export const specialEditionStateValues = [
    "available",
    "reserved",
    "owned",
    "revoked",
] as const;
export const specialEditionSchema = z.object({
    id: z.string().uuid(),
    environment: applePurchaseEnvironmentSchema,
    companion_id: specialCompanionIdSchema,
    account_id: z.string().uuid().nullable(),
    state: z.enum(specialEditionStateValues),
    attempt_id: z.string().uuid().nullable(),
    original_transaction_id: z.string().nullable(),
    /** A retired edition is never offered again; an account that already holds it keeps it. */
    retired_at: z.coerce.date().nullable(),
});
export const specialCheckoutRequestSchema = z.discriminatedUnion("action", [
    z
        .object({
            action: z.literal("reserve"),
            companion_id: limitedCompanionIdSchema,
            attempt_id: z.string().uuid(),
        })
        .strict(),
    z
        .object({
            action: z.literal("cancel"),
            companion_id: specialCompanionIdSchema,
            attempt_id: z.string().uuid(),
        })
        .strict(),
]);
export const specialClaimRequestSchema = z
    .object({
        companion_id: specialCompanionIdSchema,
        signed_transaction: z.string().min(1).max(30_000),
    })
    .strict();
/** A Special bought with the shared consumable; the buyer chose companion_id before paying. */
export const specialPurchaseRequestSchema = z
    .object({
        companion_id: limitedCompanionIdSchema,
        signed_transaction: z.string().min(1).max(30_000),
    })
    .strict();
/** A Special unlocked with one free character instead of an Apple charge. */
export const specialFreeClaimRequestSchema = z
    .object({ companion_id: limitedCompanionIdSchema })
    .strict();
export const specialOutcomeValues = ["owned", "refunded", "conflict"] as const;
export const specialClaimResultSchema = z.object({
    outcome: z.enum(specialOutcomeValues),
    transaction_id: z.string(),
    companion_id: specialCompanionIdSchema,
});
export const specialTransactionRecordSchema = specialClaimResultSchema.extend({
    account_id: z.string().uuid(),
    original_transaction_id: z.string(),
    signed_at: z.coerce.date(),
});
export const specialPurchaseRowSchema = z.object({
    id: z.string().uuid(),
    account_id: z.string().uuid(),
    companion_id: specialCompanionIdSchema,
    transaction_id: z.string(),
    original_transaction_id: z.string(),
    revoked_at: z.coerce.date().nullable(),
    signed_at: z.coerce.date(),
});
export const specialStoreSchema = z.object({
    app_account_token: z.string().uuid(),
    environment: applePurchaseEnvironmentSchema,
    purchases_enabled: z.boolean(),
    /** The one consumable every Special is bought with. */
    product_id: z.string(),
    editions: z.array(
        z.object({
            id: specialCompanionIdSchema,
            /** The legacy one-of-a-kind product, kept so older builds still decode; never sold again. */
            product_id: z.string(),
            /** Older builds also decode reserved, taken and refunded; the server no longer sends them. */
            status: z.enum(["available", "yours"]),
        }),
    ),
    conflicts: z.array(specialClaimResultSchema),
});
export const specialNotificationRequestSchema = z.object({
    signedPayload: z.string().min(1).max(100_000),
});
export const specialNotificationSchema = z.object({
    notificationUUID: z.string().uuid(),
    notificationType: z.string(),
    data: z.object({ signedTransactionInfo: z.string().optional() }).optional(),
});

export type SpecialsConfiguration = z.infer<typeof specialsConfigurationSchema>;
export type SpecialAccount = z.infer<typeof specialAccountSchema>;
export type SpecialEdition = z.infer<typeof specialEditionSchema>;
export type SpecialCheckoutRequest = z.infer<
    typeof specialCheckoutRequestSchema
>;
export type SpecialClaimRequest = z.infer<typeof specialClaimRequestSchema>;
export type SpecialPurchaseRequest = z.infer<typeof specialPurchaseRequestSchema>;
export type SpecialClaimResult = z.infer<typeof specialClaimResultSchema>;
export type SpecialTransactionRecord = z.infer<
    typeof specialTransactionRecordSchema
>;
export type SpecialPurchaseRow = z.infer<typeof specialPurchaseRowSchema>;
export type SpecialStore = z.infer<typeof specialStoreSchema>;
export type SpecialNotificationRequest = z.infer<
    typeof specialNotificationRequestSchema
>;

import { z } from "zod";
import { applePurchaseEnvironmentSchema } from "@/lib/types/apple/special-purchase";
import { limitedCompanionIdSchema } from "@/lib/types/companions/companion";

export const specialsConfigurationSchema = z.object({
    environment: applePurchaseEnvironmentSchema,
    enabled: z.enum(["true", "false"]),
    /** Comma-separated user IDs App Review signs in with; on production they buy on the Sandbox shelf. */
    reviewers: z
        .string()
        .default("")
        .transform((value) =>
            value
                .split(",")
                .map((id) => id.trim().toLowerCase())
                .filter(Boolean),
        )
        .pipe(z.array(z.string().uuid())),
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
    companion_id: limitedCompanionIdSchema,
    account_id: z.string().uuid().nullable(),
    state: z.enum(specialEditionStateValues),
    attempt_id: z.string().uuid().nullable(),
    original_transaction_id: z.string().nullable(),
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
            companion_id: limitedCompanionIdSchema,
            attempt_id: z.string().uuid(),
        })
        .strict(),
]);
export const specialClaimRequestSchema = z
    .object({
        companion_id: limitedCompanionIdSchema,
        signed_transaction: z.string().min(1).max(30_000),
    })
    .strict();
export const specialOutcomeValues = ["owned", "refunded", "conflict"] as const;
export const specialClaimResultSchema = z.object({
    outcome: z.enum(specialOutcomeValues),
    transaction_id: z.string(),
    companion_id: limitedCompanionIdSchema,
});
export const specialTransactionRecordSchema = specialClaimResultSchema.extend({
    account_id: z.string().uuid(),
    original_transaction_id: z.string(),
    signed_at: z.coerce.date(),
});
export const specialStoreSchema = z.object({
    app_account_token: z.string().uuid(),
    environment: applePurchaseEnvironmentSchema,
    purchases_enabled: z.boolean(),
    editions: z.array(
        z.object({
            id: limitedCompanionIdSchema,
            product_id: z.string(),
            status: z.enum([
                "available",
                "reserved",
                "yours",
                "taken",
                "refunded",
            ]),
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
export type SpecialClaimResult = z.infer<typeof specialClaimResultSchema>;
export type SpecialTransactionRecord = z.infer<
    typeof specialTransactionRecordSchema
>;
export type SpecialStore = z.infer<typeof specialStoreSchema>;
export type SpecialNotificationRequest = z.infer<
    typeof specialNotificationRequestSchema
>;

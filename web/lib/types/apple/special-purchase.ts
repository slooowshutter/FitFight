import { z } from "zod";
import {
    specialCompanionIdSchema,
    specialCompanionIdValues,
} from "@/lib/types/companions/companion";

export const applePurchaseEnvironmentValues = [
    "Production",
    "Sandbox",
] as const;
export const applePurchaseEnvironmentSchema = z.enum(
    applePurchaseEnvironmentValues,
);

/** Retired Specials stay mapped so refunds and restores of earlier Sandbox purchases still record. */
export const appleSpecialProductIds = new Map(
    specialCompanionIdValues.map((id) => [
        `com.fitfight.mvp.special.${id.slice("limited-".length).replaceAll("-", "_")}`,
        id,
    ]),
);

export const applePurchaseCredentialsSchema = z.object({
    keyId: z.string().regex(/^[A-Z0-9]{10}$/),
    issuerId: z.string().uuid(),
    privateKey: z.string().includes("BEGIN PRIVATE KEY"),
});

/** All three values come from server-owned account and inventory state. */
export const appleSpecialPurchaseContextSchema = z.object({
    environment: applePurchaseEnvironmentSchema,
    appAccountToken: z.string().uuid(),
    companionId: specialCompanionIdSchema,
});

export const appleSpecialTransactionSchema = z
    .object({
        transactionId: z.string().regex(/^\d{1,128}$/),
        originalTransactionId: z.string().regex(/^\d{1,128}$/),
        bundleId: z.literal("com.fitfight.mvp"),
        productId: z.string(),
        environment: applePurchaseEnvironmentSchema,
        type: z.literal("Non-Consumable"),
        inAppOwnershipType: z.literal("PURCHASED"),
        quantity: z.literal(1),
        appAccountToken: z
            .string()
            .uuid()
            .transform((value) => value.toLowerCase()),
        purchaseDate: z.number().int().nonnegative().safe(),
        signedDate: z.number().int().nonnegative().safe(),
        revocationDate: z.number().int().nonnegative().safe().optional(),
        revocationReason: z.number().int().optional(),
        revocationType: z.string().optional(),
        revocationPercentage: z.number().int().min(0).max(100_000).optional(),
        price: z.number().int().nonnegative().safe().optional(),
        currency: z
            .string()
            .regex(/^[A-Z]{3}$/)
            .optional(),
    })
    .transform((transaction, context) => {
        const companionId = appleSpecialProductIds.get(transaction.productId);
        if (!companionId) {
            context.addIssue({
                code: z.ZodIssueCode.custom,
                path: ["productId"],
                message: "Not a FitFight Special product",
            });
            return z.NEVER;
        }
        return { ...transaction, companionId };
    });

export type ApplePurchaseEnvironment = z.infer<
    typeof applePurchaseEnvironmentSchema
>;
export type ApplePurchaseCredentials = z.infer<
    typeof applePurchaseCredentialsSchema
>;
export type AppleSpecialPurchaseContext = z.infer<
    typeof appleSpecialPurchaseContextSchema
>;
/** Verified payment evidence, including refunds; this is not an ownership grant. */
export type AppleSpecialTransaction = z.infer<
    typeof appleSpecialTransactionSchema
>;

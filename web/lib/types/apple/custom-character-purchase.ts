import { z } from "zod";
import { applePurchaseEnvironmentSchema } from "@/lib/types/apple/special-purchase";

export const customCharacterProductId = "com.fitfight.mvp.custom_character";

export const appleCustomCharacterTransactionSchema = z.object({
    transactionId: z.string().regex(/^\d{1,128}$/),
    originalTransactionId: z.string().regex(/^\d{1,128}$/),
    bundleId: z.literal("com.fitfight.mvp"),
    productId: z.literal(customCharacterProductId),
    environment: applePurchaseEnvironmentSchema,
    type: z.literal("Consumable"),
    inAppOwnershipType: z.literal("PURCHASED"),
    quantity: z.literal(1),
    appAccountToken: z.string().uuid().transform((value) => value.toLowerCase()),
    purchaseDate: z.number().int().nonnegative().safe(),
    signedDate: z.number().int().nonnegative().safe(),
    revocationDate: z.number().int().nonnegative().safe().optional(),
    revocationReason: z.number().int().optional(),
    revocationType: z.string().optional(),
    revocationPercentage: z.number().int().min(0).max(100_000).optional(),
    price: z.number().int().nonnegative().safe().optional(),
    currency: z.string().regex(/^[A-Z]{3}$/).optional(),
});

export type AppleCustomCharacterTransaction = z.infer<typeof appleCustomCharacterTransactionSchema>;

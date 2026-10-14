import { z } from "zod";
import { appleConsumableTransactionSchema } from "@/lib/types/apple/special-purchase";

export const customCharacterProductId = "com.fitfight.mvp.custom_character";

export const appleCustomCharacterTransactionSchema = appleConsumableTransactionSchema.extend({
    productId: z.literal(customCharacterProductId),
});

export type AppleCustomCharacterTransaction = z.infer<typeof appleCustomCharacterTransactionSchema>;

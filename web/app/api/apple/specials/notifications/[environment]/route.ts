import { apiRoute, ApiError, json, readJson } from "@/lib/http";
import { verifySpecialNotification } from "@/lib/apple/special-purchase";
import {
    recordSpecialPurchase,
    recordSpecialTransaction,
} from "@/lib/supabase/queries/specials-supabase-query";
import { recordCustomCharacterTransaction } from "@/lib/supabase/queries/custom-characters-supabase-query";
import { customCharacterProductId } from "@/lib/types/apple/custom-character-purchase";
import { specialNotificationRequestSchema } from "@/lib/types/companions/specials";

export const runtime = "nodejs";
export const POST = apiRoute<{ environment: string }>(
    async (request, { params }) => {
        const path = params.environment;
        if (path !== "sandbox" && path !== "production")
            throw new ApiError(404, "not_found", "Unknown Apple environment");
        const environment = path === "sandbox" ? "Sandbox" : "Production";
        if (environment !== process.env.APPLE_IAP_ENVIRONMENT)
            throw new ApiError(400, "validation", "Wrong Apple environment");
        const input = specialNotificationRequestSchema.parse(
            await readJson(request, 110_000),
        );
        const { transaction } = await verifySpecialNotification(
            input.signedPayload,
            environment,
        );
        if (transaction?.type === "Non-Consumable")
            await recordSpecialTransaction(transaction);
        else if (transaction?.productId === customCharacterProductId)
            await recordCustomCharacterTransaction(transaction);
        else if (transaction)
            await recordSpecialPurchase(transaction, undefined);
        return json({ received: true });
    },
);

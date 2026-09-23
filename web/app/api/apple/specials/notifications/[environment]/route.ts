import { apiRoute, ApiError, json, readJson } from "@/lib/http";
import { verifySpecialNotification } from "@/lib/apple/special-purchase";
import { recordSpecialTransaction } from "@/lib/supabase/queries/specials-supabase-query";
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
        if (transaction) await recordSpecialTransaction(transaction);
        return json({ received: true });
    },
);

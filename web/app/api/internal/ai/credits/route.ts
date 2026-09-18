import { apiRoute, json, readJson } from "@/lib/http";
import { requireAiOperator } from "@/lib/domain/ai/operators";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { adjustAiCredits } from "@/lib/supabase/queries/ai-credits-supabase-query";
import { aiCreditAdjustmentSchema } from "@/lib/types/ai/credits";
import {
    correlateAiRequest,
    observeAiHttp,
} from "@/lib/observability/ai-request-log";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = observeAiHttp(
    apiRoute(async (request) => {
        const { userId } = await verifyUser(request);
        correlateAiRequest({ user_id: userId });
        requireAiOperator(userId);
        const input = aiCreditAdjustmentSchema.parse(
            await readJson(request, 2048),
        );
        const event = await adjustAiCredits(userId, input);
        return json({ event_id: event.id, sequence: event.sequence });
    }),
    "credits",
    "operator",
);

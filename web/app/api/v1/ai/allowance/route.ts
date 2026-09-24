import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readAiAllowance } from "@/lib/supabase/queries/ai-credits-supabase-query";
import {
    correlateAiRequest,
    observeAiHttp,
} from "@/lib/observability/ai-request-log";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = observeAiHttp(
    apiRoute(async (request) => {
        const { userId } = await verifyUser(request);
        correlateAiRequest({ user_id: userId });
        return json(await readAiAllowance(userId));
    }),
    "allowance",
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

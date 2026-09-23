import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readAiLibrary } from "@/lib/supabase/queries/ai-library-supabase-query";
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
        return json(await readAiLibrary(userId));
    }),
    "library",
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

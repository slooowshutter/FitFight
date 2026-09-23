import {
    observeAiHttp,
    correlateAiRequest,
} from "@/lib/observability/ai-request-log";
import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readAiRun } from "@/lib/domain/ai/workflow-requests";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = observeAiHttp(
    apiRoute<{ requestID: string }>(async (request, { params }) => {
        const { userId } = await verifyUser(request);
        correlateAiRequest({ user_id: userId });
        const requestID = requireUuid(params.requestID, "requestID");
        correlateAiRequest({ request_id: requestID });
        return json(await readAiRun(userId, requestID));
    }),
    "read",
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

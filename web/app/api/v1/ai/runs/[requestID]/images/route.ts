import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { saveAiImages } from "@/lib/supabase/queries/ai-library-supabase-query";
import { saveAiImagesSchema } from "@/lib/types/ai/library";
import {
    correlateAiRequest,
    observeAiHttp,
} from "@/lib/observability/ai-request-log";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = observeAiHttp(
    apiRoute<{ requestID: string }>(async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const requestId = requireUuid(params.requestID, "requestID");
        correlateAiRequest({ user_id: userId, request_id: requestId });
        const input = saveAiImagesSchema.parse(await readJson(request));
        await saveAiImages(userId, requestId, input);
        return json({ saved: true });
    }),
    "save_images",
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

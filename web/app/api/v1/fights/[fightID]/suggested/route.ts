import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { processNotificationOutboxAfterResponse } from "@/lib/notifications/process-notification-outbox-after-response";
import { setFightSuggested } from "@/lib/supabase/queries/suggest-fight-supabase-query";
import { suggestFightRequestSchema } from "@/lib/types/fights/suggest-fight";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const PATCH = apiRoute<{ fightID: string }>(
    async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const fightId = requireUuid(params.fightID, "fightID");
        const parsed = suggestFightRequestSchema.safeParse(
            await readJson(request),
        );
        if (!parsed.success) {
            throw parsed.error;
        }
        const result = await setFightSuggested(
            userId,
            fightId,
            parsed.data.suggested,
        );
        processNotificationOutboxAfterResponse();
        return json(result);
    },
);

export const OPTIONS = corsPreflight;

import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { processNotificationOutboxAfterResponse } from "@/lib/notifications/process-notification-outbox-after-response";
import { updateFight } from "@/lib/supabase/queries/update-fight-supabase-query";
import { updateFightRequestSchema } from "@/lib/types/fights/update-fight";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const PATCH = apiRoute<{ fightID: string }>(
    async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const fightId = requireUuid(params.fightID, "fightID");
        const input = updateFightRequestSchema.parse(await readJson(request));
        const sql = createDatabaseClient();
        const fight = await updateFight(
            userId,
            fightId,
            input,
            undefined,
            undefined,
            sql,
        );
        processNotificationOutboxAfterResponse();
        return json(fight);
    },
);

export const OPTIONS = corsPreflight;

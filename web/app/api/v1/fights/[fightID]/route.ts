import { after } from "next/server";
import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { processNotificationOutbox } from "@/lib/supabase/queries/process-notification-outbox-supabase-query";
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
        after(async () => {
            await processNotificationOutbox(new Date(), createDatabaseClient());
        });
        return json(fight);
    },
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

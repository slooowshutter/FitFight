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
        after(async () => {
            await processNotificationOutbox(new Date(), createDatabaseClient());
        });
        return json(result);
    },
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

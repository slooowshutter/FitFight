import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { updateFight } from "@/lib/supabase/queries/update-fight-supabase-query";
import { updateFightRequestSchema } from "@/lib/types/fights/update-fight";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const PATCH = apiRoute<{ fightID: string }>(
    async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const fightId = requireUuid(params.fightID, "fightID");
        const input = updateFightRequestSchema.parse(await readJson(request));
        return json(await updateFight(userId, fightId, input));
    },
);

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

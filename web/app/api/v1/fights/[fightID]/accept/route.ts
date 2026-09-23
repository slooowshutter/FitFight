import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    requireUuid,
} from "@/lib/http";
import { acceptFightParticipation } from "@/lib/supabase/queries/accept-fight-participation-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { membershipAcceptRequestSchema } from "@/lib/types/fights/join-start";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ fightID: string }>(
    async (request, { params }) => {
        const { userId } = await verifyUser(request);
        const fightId = requireUuid(params.fightID, "fightID");
        const parsed = membershipAcceptRequestSchema.safeParse(
            await readJson(request),
        );
        if (!parsed.success) {
            throw parsed.error;
        }
        const fight = await acceptFightParticipation(
            userId,
            fightId,
            parsed.data.personalTarget,
            parsed.data.start,
            new Date(),
        );
        return json(fight);
    },
);

export const OPTIONS = corsPreflight;

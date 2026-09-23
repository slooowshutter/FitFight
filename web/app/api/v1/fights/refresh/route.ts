import {
    apiRoute,
    corsPreflight,
    json,
    readJson,
    measureRequestStage,
} from "@/lib/http";
import { ensureAppWideFightInvite } from "@/lib/supabase/queries/app-wide-fight-invite-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { closeDueFightsForUser } from "@/lib/supabase/queries/close-due-fights-supabase-query";
import { readFightSnapshot } from "@/lib/supabase/queries/fight-snapshot-supabase-query";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { fightSnapshotRequestSchema } from "@/lib/types/fights/fight-snapshot";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request, { timing }) => {
    const { userId } = await measureRequestStage(timing, "auth", () =>
        verifyUser(request),
    );
    const { time_zone: timeZone } = fightSnapshotRequestSchema.parse(
        await readJson(request),
    );
    const sql = createDatabaseClient();
    await measureRequestStage(timing, "app_wide_invite", () =>
        ensureAppWideFightInvite(userId, undefined, undefined, sql),
    );
    await measureRequestStage(timing, "maintenance", () =>
        closeDueFightsForUser(userId),
    );
    return json(
        await measureRequestStage(timing, "db", () =>
            readFightSnapshot(userId, timeZone),
        ),
    );
}, "fights_refresh");

export const OPTIONS = corsPreflight;

import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { departureFightSchema } from "@/lib/types/fights/membership-departure";
import { lockFightSeries } from "./fight-series-lock-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

/** Starting cannot revive a round stopped by its owner or an administrator. */
export async function startFight(
    userId: string, fightId: string, when: "now" | "scheduled" = "now",
    database: Sql = createDatabaseClient(),
) {
    await database.begin(async (sql) => {
        await lockFightSeries(sql, fightId);
        const [row] = await sql`select id, owner_id, state::text, series_id from public.fights where id = ${fightId} for update`;
        if (!row) throw new ApiError(404, "not_found", "Fight not found");
        const fight = departureFightSchema.parse(row);
        if (fight.owner_id !== userId) throw new ApiError(403, "forbidden", "Only the owner can do this");
        if (["cancelled", "final", "awaiting_final_sync"].includes(fight.state)) throw new ApiError(409, "fight_not_startable", "Fight cannot be started");
        if (fight.state === "live") return;
        await sql`update public.fights set state = case
            when ${when} = 'scheduled' and starts_at > now() then 'scheduled'::public.fight_state
            else 'live'::public.fight_state end where id = ${fightId}`;
    });
    await recalculateFight(fightId, new Date(), database);
    const [updated] = await database`select state::text from public.fights where id = ${fightId}`;
    return { id: fightId, state: departureFightSchema.shape.state.parse(updated.state) };
}

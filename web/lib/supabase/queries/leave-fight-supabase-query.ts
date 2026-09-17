import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { joiningFightRowSchema } from "@/lib/types/fights/joinable-fight";
import { departFightMemberships } from "./membership-departure-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

export async function leaveFight(userId: string, fightId: string, database: Sql = createDatabaseClient()) {
    const result = await departFightMemberships(userId, fightId, userId, database);
    for (const changedId of result.changed) await recalculateFight(changedId, new Date(), database);
    const [updated] = await database`select state::text from public.fights where id = ${fightId}`;
    return { id: fightId, state: joiningFightRowSchema.shape.state.parse(updated.state) };
}

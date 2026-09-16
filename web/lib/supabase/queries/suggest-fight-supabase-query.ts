import type { Sql } from "postgres";
import { canAdministerFights } from "@/lib/admin/can-administer-fights";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { administeredFightSchema, administeredSeriesSchema } from "@/lib/types/admin/fight-administration";
import type { SuggestFightResponse } from "@/lib/types/fights/suggest-fight";

export async function setFightSuggested(userId: string, fightId: string, suggested: boolean, database: Sql = createDatabaseClient()): Promise<SuggestFightResponse> {
    if (!canAdministerFights(userId)) throw new ApiError(403, "forbidden", "Only Marc can suggest a fight");
    return database.begin(async (sql) => {
        const [row] = await sql`select id, state::text, series_id, ends_at from public.fights where id = ${fightId} for update`;
        if (!row) throw new ApiError(404, "not_found", "Fight not found");
        const fight = administeredFightSchema.parse(row);
        if (!fight.series_id) throw new ApiError(409, "conflict", "This fight cannot be suggested");
        const [seriesRow] = await sql`select id, visibility::text, paused_at, current_fight_id from public.fight_series where id = ${fight.series_id} for update`;
        const series = administeredSeriesSchema.parse(seriesRow);
        if (suggested && (series.visibility !== "joinable" || series.paused_at !== null || series.current_fight_id !== fight.id
            || !["live", "scheduled", "inviting"].includes(fight.state) || fight.ends_at.getTime() <= Date.now())) {
            throw new ApiError(409, "conflict", "Only an active public fight can be suggested");
        }
        await sql`update public.fight_series set suggested = ${suggested}, suggested_at = ${suggested ? new Date() : null} where id = ${series.id}`;
        await sql`insert into private.fight_admin_actions(actor_id, fight_id, changes) values (${userId}, ${fightId}, ${sql.json({ suggested })})`;
        return { suggested };
    });
}

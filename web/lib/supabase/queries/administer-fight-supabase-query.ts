import { lockFightSeries } from "./fight-series-lock-supabase-query";
import type { Sql } from "postgres";
import { canAdministerFights } from "@/lib/admin/can-administer-fights";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { administeredFightSchema, administeredSeriesSchema, type AdministerFightRequest } from "@/lib/types/admin/fight-administration";

export async function administerFight(userId: string, fightId: string, input: AdministerFightRequest, database: Sql = createDatabaseClient()) {
    if (!canAdministerFights(userId)) throw new ApiError(403, "forbidden", "Only Marc can administer a fight");
    return database.begin(async (sql) => {
        await lockFightSeries(sql, fightId);
        const [row] = await sql`select id, state::text, series_id, ends_at from public.fights where id = ${fightId} for update`;
        if (!row) throw new ApiError(404, "not_found", "Fight not found");
        const fight = administeredFightSchema.parse(row);
        if (!fight.series_id) throw new ApiError(409, "conflict", "This fight has no series");
        const [seriesRow] = await sql`select id, visibility::text, paused_at, current_fight_id from public.fight_series where id = ${fight.series_id} for update`;
        const series = administeredSeriesSchema.parse(seriesRow);
        if (input.action === "stop_round" && ["final", "cancelled"].includes(fight.state)) {
            throw new ApiError(409, "conflict", "A finalized or cancelled round cannot be stopped");
        }
        if ((input.visibility !== undefined || input.recurring !== undefined) && series.current_fight_id !== fight.id) {
            throw new ApiError(409, "conflict", "Open the current round to edit its series");
        }
        if (input.visibility !== undefined) {
            await sql`update public.fight_series set visibility = ${input.visibility} where id = ${series.id}`;
        }
        if (input.recurring !== undefined) {
            await sql`update public.fight_series set recurring = ${input.recurring} where id = ${series.id}`;
        }
        if (input.action === "stop_round" || input.action === "pause_series") {
            await sql`update public.fight_series set suggested = false, suggested_at = null, paused_at = coalesce(paused_at, now()) where id = ${series.id}`;
        }
        if (input.action === "stop_round") {
            await sql`update public.fights set state = 'cancelled' where id = ${fightId}`;
            await sql`update public.fight_invites set revoked_at = coalesce(revoked_at, now()) where fight_id = ${fightId} and accepted_at is null`;
        }
        await sql`insert into private.fight_admin_actions(actor_id, fight_id, changes) values (${userId}, ${fightId}, ${sql.json(input)})`;
        return { id: fightId, state: input.action === "stop_round" ? "cancelled" : fight.state };
    });
}

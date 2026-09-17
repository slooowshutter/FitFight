import { profileCountRowSchema } from "@/lib/types/profiles/shared-profile";
import { lockFightSeries } from "./fight-series-lock-supabase-query";
import type { Sql } from "postgres";
import { canAdministerFights } from "@/lib/admin/can-administer-fights";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { administeredFightSchema } from "@/lib/types/admin/fight-administration";
import { suggestedSeriesRowSchema } from "@/lib/types/fights/suggest-fight";
import type { SuggestFightResponse } from "@/lib/types/fights/suggest-fight";
import { inviteEveryoneToOpenFight } from "./app-wide-fight-invite-supabase-query";
import { enqueueFightInviteNotifications } from "./notification-intents-supabase-query";
import { processNotificationOutbox } from "./process-notification-outbox-supabase-query";

export async function setFightSuggested(userId: string, fightId: string, suggested: boolean, database: Sql = createDatabaseClient()): Promise<SuggestFightResponse> {
    if (!canAdministerFights(userId)) throw new ApiError(403, "forbidden", "Only Marc can suggest a fight");
    let invited = false;
    const now = new Date();
    const result = await database.begin(async (sql) => {
        await lockFightSeries(sql, fightId);
        const [row] = await sql`select id, state::text, series_id, ends_at from public.fights where id = ${fightId} for update`;
        if (!row) throw new ApiError(404, "not_found", "Fight not found");
        const fight = administeredFightSchema.parse(row);
        if (!fight.series_id) throw new ApiError(409, "conflict", "This fight cannot be suggested");
        const [seriesRow] = await sql`
            select series.id, series.visibility::text, series.paused_at, series.current_fight_id,
                series.owner_id, series.join_code, series.name, series.suggested,
                coalesce(nullif(trim(regexp_replace(owner.display_name, '\\s+', ' ', 'g')), ''), owner.handle) as actor_name
            from public.fight_series as series
            join public.profiles as owner on owner.user_id = series.owner_id
            where series.id = ${fight.series_id} for update of series
        `;
        const series = suggestedSeriesRowSchema.parse(seriesRow);
        if (suggested && (series.visibility !== "joinable" || series.paused_at !== null || series.current_fight_id !== fight.id
            || !["live", "scheduled", "inviting"].includes(fight.state) || fight.ends_at.getTime() <= Date.now())) {
            throw new ApiError(409, "conflict", "Only an active public fight can be suggested");
        }
        if (suggested) {
            const [capacity] = await sql`select count(*)::int n from public.fight_members where fight_id = ${fightId} and state in ('accepted', 'deferred')`;
            if (profileCountRowSchema.parse(capacity).n >= 50) throw new ApiError(409, "conflict", "This fight is full");
        }
        await sql`update public.fight_series set suggested = ${suggested}, suggested_at = ${suggested ? new Date() : null} where id = ${series.id}`;
        await sql`insert into private.fight_admin_actions(actor_id, fight_id, changes) values (${userId}, ${fightId}, ${sql.json({ suggested })})`;
        if (suggested && !series.suggested && (fight.state === "live" || fight.state === "scheduled" || fight.state === "inviting")) {
            const invitedIds = await inviteEveryoneToOpenFight(
                { ...series, paused_at: null },
                { id: fight.id, state: fight.state, ends_at: fight.ends_at.toISOString() },
                sql,
            );
            if (invitedIds.length > 0) {
                await enqueueFightInviteNotifications(sql, {
                    fightId, fightName: series.name, actorName: series.actor_name, userIds: invitedIds, now,
                });
                invited = true;
            }
        }
        return { suggested };
    });
    if (invited) await processNotificationOutbox(now, database);
    return result;
}

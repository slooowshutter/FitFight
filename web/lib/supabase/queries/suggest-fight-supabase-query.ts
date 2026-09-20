import type { Sql } from "postgres";
import { canAdministerFights } from "@/lib/admin/can-administer-fights";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { administeredFightSchema, suggestedSeriesSchema, suggestedFightOwnerSchema } from "@/lib/types/admin/fight-administration";
import type { SuggestFightResponse } from "@/lib/types/fights/suggest-fight";
import { profileCountRowSchema } from "@/lib/types/profiles/shared-profile";
import { inviteEveryoneToOpenFight } from "./app-wide-fight-invite-supabase-query";
import { lockFightSeries } from "./fight-series-lock-supabase-query";
import { enqueueFightInviteNotifications } from "./notification-intents-supabase-query";

export async function setFightSuggested(userId: string, fightId: string, suggested: boolean, database: Sql = createDatabaseClient()): Promise<SuggestFightResponse> {
    if (!canAdministerFights(userId)) throw new ApiError(403, "forbidden", "Only Marc can suggest a fight");
    return database.begin(async (sql) => {
        await lockFightSeries(sql, fightId);
        const [row] = await sql`select id, state::text, series_id, ends_at from public.fights where id = ${fightId} for update`;
        if (!row) throw new ApiError(404, "not_found", "Fight not found");
        const fight = administeredFightSchema.parse(row);
        if (!fight.series_id) throw new ApiError(409, "conflict", "This fight cannot be suggested");
        const [seriesRow] = await sql`select id, visibility::text, paused_at, current_fight_id, owner_id, name, join_code, suggested from public.fight_series where id = ${fight.series_id} for update`;
        const series = suggestedSeriesSchema.parse(seriesRow);
        const now = new Date();
        if (suggested && (series.visibility !== "joinable" || series.paused_at !== null || series.current_fight_id !== fight.id
            || !["live", "scheduled", "inviting"].includes(fight.state) || fight.ends_at.getTime() <= now.getTime())) {
            throw new ApiError(409, "conflict", "Only an active public fight can be suggested");
        }
        if (suggested) {
            const [capacity] = await sql`select count(*)::int n from public.fight_members where fight_id = ${fightId} and state in ('accepted', 'deferred')`;
            if (profileCountRowSchema.parse(capacity).n >= 50) throw new ApiError(409, "conflict", "This fight is full");
        }
        await sql`update public.fight_series set suggested = ${suggested}, suggested_at = ${suggested ? now : null} where id = ${series.id}`;
        await sql`insert into private.fight_admin_actions(actor_id, fight_id, changes) values (${userId}, ${fightId}, ${sql.json({ suggested })})`;
        if (suggested && !series.suggested) {
            const invitedIds = await inviteEveryoneToOpenFight(
                { ...series, paused_at: series.paused_at?.toISOString() ?? null },
                { ...fight, ends_at: fight.ends_at.toISOString() },
                sql,
            );
            if (invitedIds.length > 0) {
                const [ownerRow] = await sql`select handle, display_name from public.profiles where id = ${series.owner_id}`;
                const owner = suggestedFightOwnerSchema.parse(ownerRow);
                const displayName = owner.display_name.replace(/\s+/g, " ").trim();
                await enqueueFightInviteNotifications(sql, {
                    fightId: fight.id,
                    fightName: series.name,
                    actorName: displayName.length > 0 ? displayName : owner.handle,
                    userIds: invitedIds,
                    now,
                });
            }
        }
        return { suggested };
    });
}

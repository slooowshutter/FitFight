import type { Sql } from "postgres";
import { rollingWindow } from "@/lib/domain/fights/join-code";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { recurringRoundSchema, recurringSeriesSchema } from "@/lib/types/fights/recurring-round";
import { lockFightSeries } from "./fight-series-lock-supabase-query";

/** Creates a round and copies its accepted series roster in one transaction. */
export async function mintNextRecurringFight(
    previousFightId: string,
    _admin = createAdminClient(),
    now: Date = new Date(),
    database: Sql = createDatabaseClient(),
): Promise<string | null> {
    return database.begin(async (sql) => {
        await lockFightSeries(sql, previousFightId);
        const [row] = await sql`select id, series_id, starts_at::text, ends_at::text, state::text from public.fights where id = ${previousFightId} for update`;
        if (!row) return null;
        const previous = recurringRoundSchema.parse(row);
        if (!previous.series_id || Date.parse(previous.ends_at) > now.getTime() || previous.state === "cancelled") return null;
        const [seriesRow] = await sql`select recurring, paused_at, current_fight_id from public.fight_series where id = ${previous.series_id}`;
        const series = recurringSeriesSchema.parse(seriesRow);
        if (!series.recurring || series.paused_at) return null;
        const window = rollingWindow(previous.starts_at, previous.ends_at);
        const [existing] = await sql`select id from public.fights where series_id = ${previous.series_id} and starts_at = ${window.startsAt}`;
        if (existing) {
            const existingId = recurringRoundSchema.shape.id.parse(existing.id);
            if (series.current_fight_id === previous.id) {
                await sql`update public.fight_series set current_fight_id = ${existingId} where id = ${previous.series_id}`;
            }
            return existingId;
        }
        if (series.current_fight_id !== previous.id) return null;
        const [inserted] = await sql`
            insert into public.fights(owner_id, name, state, starts_at, ends_at, time_zone, metric,
                outcome_rule, goal_policy, default_goal_value, stake_kind, stake_minor, currency, action_text, series_id)
            select owner_id, name, 'live', ${window.startsAt}, ${window.endsAt}, time_zone, 'steps',
                outcome_rule, goal_policy, default_goal_value, stake_kind, stake_minor, currency, action_text, series_id
            from public.fights where id = ${previous.id} returning id
        `;
        const nextId = recurringRoundSchema.shape.id.parse(inserted.id);
        await sql`
            insert into public.data_sources(user_id, provider, source_label, connection_route, capabilities, status, consent_version, connected_at)
            select user_id, 'apple_health', 'Apple Health', 'healthkit', array['steps'], 'healthy', 1, ${now}
            from public.fight_series_members where series_id = ${previous.series_id} and state = 'accepted'
            on conflict (user_id, provider, connection_route) do nothing
        `;
        await sql`
            insert into public.fight_members(fight_id, user_id, state, accepted_at, selected_source_id, source_label)
            select ${nextId}, member.user_id, 'accepted', ${now}, source.id, source.source_label
            from public.fight_series_members member
            join public.data_sources source on source.user_id = member.user_id and source.provider = 'apple_health' and source.connection_route = 'healthkit'
            where member.series_id = ${previous.series_id} and member.state = 'accepted'
        `;
        await sql`update public.fight_series set current_fight_id = ${nextId} where id = ${previous.series_id}`;
        return nextId;
    });
}

export async function mintDueRecurringFights(
    admin = createAdminClient(),
    now: Date = new Date(),
): Promise<string[]> {
    const { data, error } = await admin
        .from("fight_series")
        .select("id, current_fight_id")
        .eq("recurring", true)
        .is("paused_at", null);
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not load recurring series",
        );
    }
    const minted: string[] = [];
    for (const row of data ?? []) {
        const currentId = row.current_fight_id as string | null;
        if (!currentId) {
            continue;
        }
        const nextId = await mintNextRecurringFight(currentId, admin, now);
        if (nextId && nextId !== currentId) {
            minted.push(nextId);
        }
    }
    return minted;
}

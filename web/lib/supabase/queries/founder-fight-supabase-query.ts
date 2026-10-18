import type { Sql } from "postgres";
import { z } from "zod";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { FightRow } from "@/lib/types/database";
import {
    FOUNDER_FIGHT_DAYS,
    FOUNDER_FIGHT_TIME_ZONE,
    founderChallengersSchema,
    founderUserIds,
    type FounderChallengers,
} from "@/lib/types/fights/founder-fight";
import { publishCivilDayScores } from "./activity-pipeline-supabase-query";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { allocateJoinCode } from "./create-fight-supabase-query";
import { readEnvironment } from "./environment-supabase-query";
import { fightSummary } from "./fight-access-supabase-query";

/** The founder of the environment named by NEXT_PUBLIC_SUPABASE_URL. */
export async function readFounderId(database: Sql = createDatabaseClient()): Promise<string> {
    const projectURL = z.string().url().safeParse(process.env.NEXT_PUBLIC_SUPABASE_URL);
    if (!projectURL.success) {
        throw new ApiError(500, ERROR_CODES.config, "Supabase project is not configured");
    }
    const environment = await readEnvironment(new URL(projectURL.data).hostname.split(".")[0], database);
    return founderUserIds[environment];
}

/** One repeating 1v1 series per user against the founder; calling again returns its current round. */
export async function createFounderFight(
    userId: string,
    founderId: string,
    database: Sql = createDatabaseClient(),
) {
    if (userId === founderId) {
        throw new ApiError(400, ERROR_CODES.validation, "You cannot fight yourself");
    }
    const admin = createAdminClient();
    const source = await ensureAppleHealthSource(userId, { admin });
    const joinCode = await allocateJoinCode(admin);
    const fight = await database.begin(async (sql) => {
        // Read only: the founder's source reports his own syncs, never a challenger's signup.
        const [founderSource] = await sql<{ id: string; source_label: string }[]>`
            select id, source_label from public.data_sources
            where user_id = ${founderId} and provider = 'apple_health' and connection_route = 'healthkit'
        `;
        if (!founderSource) {
            throw new ApiError(503, ERROR_CODES.config, "The founder has not connected Apple Health");
        }
        const [series] = await sql<{ id: string }[]>`
            insert into public.fight_series (
                owner_id, host_id, join_code, visibility, recurring, duration_seconds, name, time_zone
            )
            values (
                ${userId}, ${founderId}, ${joinCode}, 'invite_only', true,
                ${FOUNDER_FIGHT_DAYS * 86_400}, 'Fight Marc', ${FOUNDER_FIGHT_TIME_ZONE}
            )
            on conflict (owner_id, host_id) where host_id is not null do nothing
            returning id
        `;
        if (!series) {
            const [existing] = await sql<Pick<FightRow, "id" | "state">[]>`
                select fight.id, fight.state::text as state
                from public.fight_series as series
                join public.fights as fight on fight.id = series.current_fight_id
                where series.owner_id = ${userId} and series.host_id = ${founderId}
            `;
            return existing;
        }
        const [inserted] = await sql<Pick<FightRow, "id" | "state">[]>`
            insert into public.fights (
                owner_id, host_id, name, state, starts_at, ends_at, time_zone, metric,
                outcome_rule, goal_policy, stake_kind, series_id
            )
            select ${userId}, ${founderId}, 'Fight Marc', 'live',
                today.starts_on at time zone ${FOUNDER_FIGHT_TIME_ZONE},
                (today.starts_on + make_interval(days => ${FOUNDER_FIGHT_DAYS})) at time zone ${FOUNDER_FIGHT_TIME_ZONE},
                ${FOUNDER_FIGHT_TIME_ZONE}, 'steps', 'highest_total', 'shared', 'action', ${series.id}
            from (select date_trunc('day', now() at time zone ${FOUNDER_FIGHT_TIME_ZONE}) as starts_on) as today
            returning id, state::text as state
        `;
        await sql`update public.fight_series set current_fight_id = ${inserted.id} where id = ${series.id}`;
        await sql`
            insert into public.fight_members (
                fight_id, user_id, state, accepted_at, selected_source_id, source_label
            )
            values
                (${inserted.id}, ${userId}, 'accepted', now(), ${source.id}, ${source.sourceLabel}),
                (${inserted.id}, ${founderId}, 'accepted', now(), ${founderSource.id}, ${founderSource.source_label})
        `;
        await sql`
            insert into public.fight_series_members (series_id, user_id, state, joined_at)
            values (${series.id}, ${userId}, 'accepted', now()), (${series.id}, ${founderId}, 'accepted', now())
        `;
        await publishCivilDayScores(sql, founderId, founderSource.id, inserted.id);
        return inserted;
    });
    return fightSummary(fight);
}

/** Every challenger's current round and the founder's record against them, newest first. */
export async function readFounderChallengers(
    founderId: string,
    database: Sql = createDatabaseClient(),
): Promise<FounderChallengers> {
    const challengers = await database`
        select challenger.id as user_id, challenger.handle, challenger.display_name,
            fight.id as fight_id,
            case when series.paused_at is null then fight.state::text else 'left' end as state,
            least(
                floor(extract(epoch from now() - fight.starts_at) / 86400)::integer + 1,
                round(extract(epoch from fight.ends_at - fight.starts_at) / 86400)::integer
            ) as day,
            round(extract(epoch from fight.ends_at - fight.starts_at) / 86400)::integer as days,
            coalesce(them.current_value, them.final_value, 0)::text as steps,
            coalesce(host.current_value, host.final_value, 0)::text as founder_steps,
            record.wins, record.losses, record.draws
        from public.fight_series as series
        join public.fights as fight on fight.id = series.current_fight_id
        join public.profiles as challenger on challenger.id = series.owner_id and challenger.deleted_at is null
        left join public.fight_members as them on them.fight_id = fight.id and them.user_id = series.owner_id
        left join public.fight_members as host on host.fight_id = fight.id and host.user_id = series.host_id
        cross join lateral (
            select count(*) filter (where round_host.rank < round_them.rank)::integer as wins,
                count(*) filter (where round_host.rank > round_them.rank)::integer as losses,
                count(*) filter (where round_host.rank = round_them.rank)::integer as draws
            from public.fights as round
            join public.fight_members as round_host on round_host.fight_id = round.id
                and round_host.user_id = round.host_id and round_host.state = 'accepted'
            join public.fight_members as round_them on round_them.fight_id = round.id
                and round_them.user_id = series.owner_id and round_them.state = 'accepted'
            where round.series_id = series.id and round.state = 'final'
        ) as record
        where series.host_id = ${founderId}
        order by series.created_at desc, series.id
    `;
    return founderChallengersSchema.parse({ challengers });
}

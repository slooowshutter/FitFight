import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { fightNeedsCloserTick } from "@/lib/scoring/fight-clock";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    fightMaintenanceCandidateSchema,
    userFightMaintenanceSchema,
    type FightMaintenanceCandidate,
} from "@/lib/types/fights/fight-snapshot";
import {
    mintDueRecurringFights,
    mintNextRecurringFight,
} from "./mint-recurring-fight-supabase-query";
import { processNotificationOutbox } from "./process-notification-outbox-supabase-query";
import { enqueueScheduledNotifications } from "./scheduled-notifications-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const BATCH = 25;
/** The cron route allows 60 s and first spends up to 20 s on received activity. */
const CLOSE_BUDGET_MS = 30_000;

export type CloseDueResult = {
    checked: number;
    closed: number;
    fightIds: string[];
    notifications: Awaited<ReturnType<typeof processNotificationOutbox>>;
};

function dueIds(rows: FightMaintenanceCandidate[], nowMs: number): string[] {
    return rows
        .filter((row) =>
            fightNeedsCloserTick({
                state: row.state,
                nowMs,
                startsAtMs: Date.parse(row.starts_at),
                endsAtMs: Date.parse(row.ends_at),
            }),
        )
        .map((row) => row.id);
}

async function recalculateIds(
    fightIds: string[],
    now: Date,
    database?: Sql,
): Promise<string[]> {
    const closed: string[] = [];
    for (const fightId of fightIds.slice(0, BATCH)) {
        await recalculateFight(fightId, now, database);
        closed.push(fightId);
    }
    return closed;
}

/** Server job: process only due transitions, using `now` so tests can pin time. */
export async function closeDueFights(
    admin: SupabaseClient = createAdminClient(),
    now: Date = new Date(),
    database: Sql = createDatabaseClient(),
): Promise<CloseDueResult> {
    // Every friend round ends at the same moment, so keep closing batches until none is due or the
    // budget runs out. A fight already tried this run is not picked again, even if it stayed due.
    const startedAt = Date.now();
    const fightIds: string[] = [];
    let checked = 0;
    while (Date.now() - startedAt < CLOSE_BUDGET_MS) {
        const rows = fightMaintenanceCandidateSchema.pick({ id: true }).array().parse(await database`
            with candidates as (
                select id,
                    case state
                        when 'scheduled' then starts_at
                        when 'live' then ends_at
                        when 'awaiting_final_sync' then ends_at
                            + final_sync_grace_seconds * interval '1 second'
                    end as next_transition_at
                from public.fights
                where state in ('scheduled', 'live', 'awaiting_final_sync')
                    and not (id = any(${database.array(fightIds)}::uuid[]))
            )
            select id
            from candidates
            where next_transition_at <= ${now.toISOString()}::timestamptz
            order by next_transition_at, id
            limit ${BATCH}
        `);
        checked += rows.length;
        fightIds.push(...await recalculateIds(rows.map((row) => row.id), now, database));
        if (rows.length < BATCH) break;
    }
    await mintDueRecurringFights(admin, now);
    await enqueueScheduledNotifications(database, now);
    const notifications = await processNotificationOutbox(now, database);
    return {
        checked,
        closed: fightIds.length,
        fightIds,
        notifications,
    };
}

/** Reminders, digests, and pushes for every account. No Fight snapshot reads them. */
export async function processDueNotifications(
    now: Date,
    database: Sql,
): Promise<CloseDueResult["notifications"]> {
    await enqueueScheduledNotifications(database, now);
    return processNotificationOutbox(now, database);
}

/** Opening the app: close this user's due fights even if cron has not run. */
export async function closeDueFightsForUser(
    userId: string,
    admin: SupabaseClient = createAdminClient(),
    now: Date = new Date(),
    database: Sql = createDatabaseClient(),
): Promise<Omit<CloseDueResult, "notifications">> {
    const [row] = await database`
        select coalesce((
            select jsonb_agg(jsonb_build_object(
                'id', fight.id, 'state', fight.state,
                'starts_at', fight.starts_at, 'ends_at', fight.ends_at
            ) order by fight.ends_at, fight.id)
            from public.fights fight
            join public.fight_members member on member.fight_id = fight.id
            where member.user_id = ${userId} and member.state = 'accepted'
                and fight.state in ('live', 'scheduled', 'awaiting_final_sync')
                and fight.host_id is distinct from ${userId}
        ), '[]'::jsonb) as candidates,
        coalesce((
            select jsonb_agg(series.current_fight_id order by current_fight.ends_at, series.id)
            from public.fight_series series
            join public.fights current_fight on current_fight.id = series.current_fight_id
            where series.recurring and series.paused_at is null
                and current_fight.ends_at <= ${now.toISOString()}
                and series.host_id is distinct from ${userId}
                and (series.owner_id = ${userId} or exists (
                    select 1 from public.fight_series_members member
                    where member.series_id = series.id and member.user_id = ${userId}
                        and member.state = 'accepted'
                ))
        ), '[]'::jsonb) as recurring
    `;
    const { candidates, recurring } = userFightMaintenanceSchema.parse(row);
    const fightIds = await recalculateIds(
        dueIds(candidates, now.getTime()),
        now,
        database,
    );
    for (const previousFightId of recurring.slice(0, BATCH)) {
        await mintNextRecurringFight(previousFightId, now, database);
    }
    return {
        checked: candidates.length,
        closed: fightIds.length,
        fightIds,
    };
}

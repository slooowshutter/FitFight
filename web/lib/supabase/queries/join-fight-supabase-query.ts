import { recordSharedFightParticipation } from "./profile-events-supabase-query";
import { profileCountRowSchema } from "@/lib/types/profiles/shared-profile";
import { lockFightSeries } from "./fight-series-lock-supabase-query";
import type { Sql } from "postgres";
import { isJoinCode, normalizeJoinCode } from "@/lib/domain/fights/join-code";
import {
    canDeferFightJoin,
    fightJoinMemberState,
} from "@/lib/domain/fights/join-start";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
    FightRow,
    FightSeriesRow,
    ProfileRow,
} from "@/lib/types/database";
import type {
    JoinFightRequest,
    JoinableFightSummary,
} from "@/lib/types/fights/joinable-fight";
import {
    joinableFightListFightSchema,
    joinableFightListSeriesSchema,
} from "@/lib/types/fights/joinable-fight-list";
import { joiningFightRowSchema, joiningSeriesRowSchema, joiningMemberRowSchema } from "@/lib/types/fights/joinable-fight";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { loadSeries } from "./fight-access-supabase-query";
import { mintNextRecurringFight } from "./mint-recurring-fight-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

export const JOINABLE_MEMBER_CAP = 50;
const JOIN_ATTEMPTS_PER_USER_HOUR = 10;
const JOIN_ATTEMPTS_PER_IP_HOUR = 30;
const JOINABLE_FIGHT_SELECT =
    "id,state,starts_at,ends_at,time_zone,action_text,roster:fight_members(count),membership:fight_members(user_id)";

async function recordJoinAttempt(
    userId: string,
    clientIp: string | null,
    sql: Sql,
) {
    const [userCount] = await sql<{ n: number }[]>`
        select count(*)::int as n
        from private.fight_join_attempts
        where user_id = ${userId}
            and created_at >= now() - interval '1 hour'
    `;
    if (userCount.n >= JOIN_ATTEMPTS_PER_USER_HOUR) {
        throw new ApiError(
            429,
            ERROR_CODES.join_rate_limited,
            "Too many join attempts",
        );
    }
    if (clientIp) {
        const [ipCount] = await sql<{ n: number }[]>`
            select count(*)::int as n
            from private.fight_join_attempts
            where client_ip = ${clientIp}
                and created_at >= now() - interval '1 hour'
        `;
        if (ipCount.n >= JOIN_ATTEMPTS_PER_IP_HOUR) {
            throw new ApiError(
                429,
                ERROR_CODES.join_rate_limited,
                "Too many join attempts",
            );
        }
    }
    await sql`
        insert into private.fight_join_attempts (user_id, client_ip)
        values (${userId}, ${clientIp})
    `;
}

async function currentJoinableFight(
    series: FightSeriesRow,
    admin = createAdminClient(),
    now: Date = new Date(),
): Promise<FightRow | null> {
    if (!series.current_fight_id) {
        return null;
    }
    const { data, error } = await admin
        .from("fights")
        .select("*")
        .eq("id", series.current_fight_id)
        .maybeSingle();
    if (error) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight");
    }
    let fight = data as FightRow | null;
    if (!fight) {
        return null;
    }
    if (
        series.recurring &&
        !series.paused_at &&
        Date.parse(fight.ends_at) <= now.getTime()
    ) {
        const nextId = await mintNextRecurringFight(fight.id, now);
        if (nextId && nextId !== fight.id) {
            const { data: nextData, error: nextError } = await admin
                .from("fights")
                .select("*")
                .eq("id", nextId)
                .maybeSingle();
            if (nextError) {
                throw new ApiError(
                    500,
                    ERROR_CODES.db_error,
                    "Could not load next fight",
                );
            }
            fight = nextData as FightRow | null;
        }
    }
    return fight;
}

async function ownerHandle(
    ownerId: string,
    admin = createAdminClient(),
): Promise<string> {
    const { data, error } = await admin
        .from("profiles")
        .select("user_id, handle, display_name, time_zone")
        .eq("user_id", ownerId)
        .maybeSingle();
    if (error) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not load owner");
    }
    const profile = data as ProfileRow | null;
    return profile?.handle ?? "user";
}

const ROSTER_STATES = ["accepted", "deferred"] as const;

async function rosterMemberCount(
    fightId: string,
    admin = createAdminClient(),
): Promise<number> {
    const { count, error } = await admin
        .from("fight_members")
        .select("fight_id", { count: "exact", head: true })
        .eq("fight_id", fightId)
        .in("state", [...ROSTER_STATES]);
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not count members",
        );
    }
    return count ?? 0;
}

async function isRosterMember(
    fightId: string,
    userId: string,
    admin = createAdminClient(),
): Promise<boolean> {
    const { data, error } = await admin
        .from("fight_members")
        .select("fight_id")
        .eq("fight_id", fightId)
        .eq("user_id", userId)
        .in("state", [...ROSTER_STATES])
        .maybeSingle();
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not load membership",
        );
    }
    return Boolean(data);
}

async function toSummary(
    series: FightSeriesRow,
    fight: FightRow,
    userId: string,
    admin = createAdminClient(),
    now: Date = new Date(),
): Promise<JoinableFightSummary> {
    if (!series.join_code) {
        throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    const [handle, memberCount, alreadyMember] = await Promise.all([
        ownerHandle(series.owner_id, admin),
        rosterMemberCount(fight.id, admin),
        isRosterMember(fight.id, userId, admin),
    ]);
    return {
        fightId: fight.id,
        seriesId: series.id,
        name: series.name,
        joinCode: series.join_code,
        ownerHandle: handle,
        actionText: fight.action_text,
        startsAt: fight.starts_at,
        endsAt: fight.ends_at,
        memberCount,
        recurring: series.recurring,
        alreadyMember,
        canJoinNext:
            !alreadyMember &&
            canDeferFightJoin({
                recurring: series.recurring,
                paused: Boolean(series.paused_at),
                startsAt: fight.starts_at,
                timeZone: fight.time_zone,
                now,
            }),
    };
}

export async function listJoinableFights(
    userId: string,
    admin = createAdminClient(),
    now: Date = new Date(),
    suggestedOnly = false,
): Promise<JoinableFightSummary[]> {
    let request = admin
        .from("fight_series")
        .select(
            `id,name,join_code,recurring,paused_at,owner:profiles!owner_id(handle),fight:fights!current_fight_id(${JOINABLE_FIGHT_SELECT})`,
        )
        .eq("visibility", "joinable")
        .is("paused_at", null)
        .in("fight.roster.state", [...ROSTER_STATES])
        .in("fight.membership.state", [...ROSTER_STATES])
        .eq("fight.membership.user_id", userId);
    request = suggestedOnly
        ? request
              .eq("suggested", true)
              .order("suggested_at", { ascending: false })
              .limit(8)
        : request.order("created_at", { ascending: false }).limit(50);
    const { data, error } = await request;
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not list joinable fights",
        );
    }
    const summaries: JoinableFightSummary[] = [];
    for (const row of joinableFightListSeriesSchema.array().parse(data)) {
        let fight = row.fight;
        if (!fight) continue;
        if (
            row.recurring &&
            !row.paused_at &&
            Date.parse(fight.ends_at) <= now.getTime()
        ) {
            const nextId = await mintNextRecurringFight(fight.id, now);
            if (nextId && nextId !== fight.id) {
                const { data: nextData, error: nextError } = await admin
                    .from("fights")
                    .select(JOINABLE_FIGHT_SELECT)
                    .eq("id", nextId)
                    .in("roster.state", [...ROSTER_STATES])
                    .in("membership.state", [...ROSTER_STATES])
                    .eq("membership.user_id", userId)
                    .maybeSingle();
                if (nextError) {
                    throw new ApiError(
                        500,
                        ERROR_CODES.db_error,
                        "Could not load next fight",
                    );
                }
                fight = joinableFightListFightSchema.nullable().parse(nextData);
            }
        }
        if (!fight) continue;
        if (
            fight.state === "final" ||
            fight.state === "cancelled" ||
            fight.state === "awaiting_final_sync"
        ) {
            continue;
        }
        if (!row.join_code) {
            throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
        }
        const alreadyMember = fight.membership.length > 0;
        if (suggestedOnly && (Date.parse(fight.ends_at) <= now.getTime() || (!alreadyMember && fight.roster[0].count >= JOINABLE_MEMBER_CAP))) continue;
        summaries.push({
            fightId: fight.id,
            seriesId: row.id,
            name: row.name,
            joinCode: row.join_code,
            ownerHandle: row.owner?.handle ?? "user",
            actionText: fight.action_text,
            startsAt: fight.starts_at,
            endsAt: fight.ends_at,
            memberCount: fight.roster[0].count,
            recurring: row.recurring,
            alreadyMember,
            canJoinNext:
                !alreadyMember &&
                canDeferFightJoin({
                    recurring: row.recurring,
                    paused: Boolean(row.paused_at),
                    startsAt: fight.starts_at,
                    timeZone: fight.time_zone,
                    now,
                }),
        });
    }
    return summaries;
}

export async function getJoinableFightByCode(
    userId: string,
    rawCode: string,
    admin = createAdminClient(),
    now: Date = new Date(),
): Promise<JoinableFightSummary> {
    const code = normalizeJoinCode(rawCode);
    if (!isJoinCode(code)) {
        throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    const { data, error } = await admin
        .from("fight_series")
        .select("*")
        .eq("join_code", code)
        .maybeSingle();
    if (error) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
    }
    const series = data as FightSeriesRow | null;
    if (!series || !series.join_code || series.paused_at) {
        throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    const fight = await currentJoinableFight(series, admin, now);
    if (!fight) {
        throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    if (
        fight.state === "final" ||
        fight.state === "cancelled" ||
        fight.state === "awaiting_final_sync"
    ) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "Fight is no longer joinable",
        );
    }
    return toSummary(series, fight, userId, admin, now);
}

export async function joinFight(
    userId: string,
    input: JoinFightRequest,
    clientIp: string | null = null,
    admin = createAdminClient(),
    now: Date = new Date(),
    sql: Sql = createDatabaseClient(),
) {
    await recordJoinAttempt(userId, clientIp, sql);

    let series: FightSeriesRow;
    if (input.code) {
        const code = normalizeJoinCode(input.code);
        if (!isJoinCode(code)) {
            throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
        }
        const { data, error } = await admin
            .from("fight_series")
            .select("*")
            .eq("join_code", code)
            .maybeSingle();
        if (error) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not load series",
            );
        }
        if (!data) {
            throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
        }
        series = data as FightSeriesRow;
    } else {
        const { data: fightData, error: fightError } = await admin
            .from("fights")
            .select("*")
            .eq("id", input.fightId)
            .maybeSingle();
        if (fightError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not load fight",
            );
        }
        const listed = fightData as FightRow | null;
        if (!listed?.series_id) {
            throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
        }
        series = await loadSeries(listed.series_id, admin);
    }

    if (series.paused_at || !series.join_code) {
        throw new ApiError(
            403,
            ERROR_CODES.fight_not_joinable,
            "This fight cannot be joined",
        );
    }

    const fight = await currentJoinableFight(series, admin, now);
    if (!fight) {
        throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
    }
    if (["final", "cancelled", "awaiting_final_sync"].includes(fight.state)) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "Fight is no longer joinable",
        );
    }

    const source = await ensureAppleHealthSource(userId, { admin });
    const summary = await sql.begin(async (transaction) => {
        await lockFightSeries(transaction, fight.id);
        const [lockedFight] = await transaction`
            select id, state::text, starts_at, ends_at, time_zone, series_id
            from public.fights where id = ${fight.id} for update
        `;
        const current = joiningFightRowSchema.parse(lockedFight);
        const [lockedSeries] = await transaction`
            select id, visibility::text, recurring, paused_at, current_fight_id, join_code
            from public.fight_series where id = ${current.series_id} for update
        `;
        const currentSeries = joiningSeriesRowSchema.parse(lockedSeries);
        if (currentSeries.paused_at || currentSeries.current_fight_id !== current.id || !currentSeries.join_code
            || (!input.code && currentSeries.visibility !== "joinable")
            || (input.code && normalizeJoinCode(input.code) !== currentSeries.join_code)) {
            throw new ApiError(403, ERROR_CODES.fight_not_joinable, "This fight cannot be joined");
        }
        if (["final", "cancelled", "awaiting_final_sync"].includes(current.state) || current.ends_at <= now) {
            throw new ApiError(409, ERROR_CODES.conflict, "Fight is no longer joinable");
        }
        const members = joiningMemberRowSchema.array().parse(await transaction`
            select state::text from public.fight_members where fight_id = ${current.id} and user_id = ${userId} for update
        `);
        if (members[0]?.state === "accepted" || members[0]?.state === "deferred") return { id: current.id, state: current.state };
        const [count] = await transaction`select count(*)::int n from public.fight_members where fight_id = ${current.id} and state in ('accepted', 'deferred')`;
        if (profileCountRowSchema.parse(count).n >= JOINABLE_MEMBER_CAP) throw new ApiError(409, ERROR_CODES.fight_full, "This fight is full");
        const memberState = fightJoinMemberState(input.start, canDeferFightJoin({
            recurring: currentSeries.recurring, paused: currentSeries.paused_at !== null,
            startsAt: current.starts_at.toISOString(), timeZone: current.time_zone, now,
        }));
        if (!memberState) throw new ApiError(409, ERROR_CODES.conflict, "This fight does not have a next round to join");
        await transaction`
            insert into public.fight_members(fight_id, user_id, state, accepted_at, selected_source_id, source_label, acceptance_copy_version)
            values (${current.id}, ${userId}, ${memberState}, ${now}, ${source.id}, ${source.sourceLabel}, 1)
            on conflict (fight_id, user_id) do update set state = excluded.state, accepted_at = excluded.accepted_at,
                selected_source_id = excluded.selected_source_id, source_label = excluded.source_label, acceptance_copy_version = 1
        `;
        await transaction`
            insert into public.fight_series_members(series_id, user_id, state, joined_at)
            values (${current.series_id}, ${userId}, 'accepted', ${now})
            on conflict (series_id, user_id) do update set state = 'accepted', joined_at = excluded.joined_at
        `;
        if (memberState === "accepted") await recordSharedFightParticipation(transaction, current.id, userId);
        return { id: current.id, state: current.state };
    });
    await recalculateFight(summary.id, now, sql);
    const [updated] = await sql`select state::text from public.fights where id = ${summary.id}`;
    return { id: summary.id, state: joiningFightRowSchema.shape.state.parse(updated.state) };
}

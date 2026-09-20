import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql, TransactionSql } from "postgres";
import {
    APP_WIDE_JOIN_CODE,
    normalizeJoinCode,
} from "@/lib/domain/fights/join-code";
import { newInviteToken } from "@/lib/domain/invites/token";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
    FightMemberRow,
    FightRow,
    FightSeriesRow,
    FightState,
    ProfileRow,
} from "@/lib/types/database";
import { currentJoinableFight } from "./join-fight-supabase-query";
import { enqueueFightInviteNotifications } from "./notification-intents-supabase-query";

const CLOSED_FIGHT_STATES = new Set<FightState>([
    "draft",
    "final",
    "cancelled",
    "awaiting_final_sync",
]);

function isUniqueViolation(error: { code?: string } | null): boolean {
    return error?.code === "23505";
}

async function loadAppWideSeries(
    admin: SupabaseClient,
): Promise<FightSeriesRow[]> {
    const code = normalizeJoinCode(APP_WIDE_JOIN_CODE);
    const [coded, suggested] = await Promise.all([
        admin
            .from("fight_series")
            .select("*")
            .eq("join_code", code)
            .maybeSingle(),
        admin
            .from("fight_series")
            .select("*")
            .eq("suggested", true)
            .is("paused_at", null),
    ]);
    if (coded.error || suggested.error) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not load series");
    }
    const found = new Map<string, FightSeriesRow>();
    const codedSeries = coded.data as FightSeriesRow | null;
    if (codedSeries) {
        found.set(codedSeries.id, codedSeries);
    }
    for (const row of (suggested.data ?? []) as FightSeriesRow[]) {
        found.set(row.id, row);
    }
    return [...found.values()];
}

async function inviteUserToOpenFight(
    userId: string,
    series: FightSeriesRow,
    fight: FightRow,
    admin: SupabaseClient,
    sql: Sql | undefined,
    now: Date,
): Promise<"invited" | "already" | "closed"> {
    if (!series.join_code || series.paused_at) {
        return "closed";
    }
    if (series.owner_id === userId || CLOSED_FIGHT_STATES.has(fight.state)) {
        return series.owner_id === userId ? "already" : "closed";
    }

    const { data: existingMember, error: memberLookupError } = await admin
        .from("fight_members")
        .select("fight_id, user_id, state")
        .eq("fight_id", fight.id)
        .eq("user_id", userId)
        .maybeSingle();
    if (memberLookupError) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not load membership",
        );
    }
    const member = existingMember as Pick<FightMemberRow, "state"> | null;
    if (member) {
        switch (member.state) {
            case "accepted":
            case "deferred":
            case "invited":
            case "declined":
            case "withdrawn":
            case "disqualified":
                return "already";
            default: {
                const _exhaustive: never = member.state;
                return _exhaustive;
            }
        }
    }

    const { error: insertMemberError } = await admin
        .from("fight_members")
        .insert({
            fight_id: fight.id,
            user_id: userId,
            state: "invited",
        });
    if (isUniqueViolation(insertMemberError)) {
        return "already";
    }
    if (insertMemberError) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not create membership",
        );
    }

    if (fight.series_id) {
        const { data: seriesMember, error: seriesLookupError } = await admin
            .from("fight_series_members")
            .select("series_id, user_id, state")
            .eq("series_id", fight.series_id)
            .eq("user_id", userId)
            .maybeSingle();
        if (seriesLookupError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not load series membership",
            );
        }
        if (!seriesMember) {
            const { error: seriesMemberError } = await admin
                .from("fight_series_members")
                .insert({
                    series_id: fight.series_id,
                    user_id: userId,
                    state: "invited",
                });
            if (seriesMemberError && !isUniqueViolation(seriesMemberError)) {
                throw new ApiError(
                    500,
                    ERROR_CODES.db_error,
                    "Could not create membership",
                );
            }
        }
    }

    const { tokenHash } = newInviteToken();
    const { error: inviteError } = await admin.from("fight_invites").insert({
        fight_id: fight.id,
        invited_user_id: userId,
        token_hash: tokenHash,
        expires_at: fight.ends_at,
    });
    if (inviteError && !isUniqueViolation(inviteError)) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not create invite",
        );
    }

    if (sql) {
        const { data: owner, error: ownerError } = await admin
            .from("profiles")
            .select("user_id:id, handle, display_name, time_zone")
            .eq("id", series.owner_id)
            .is("deleted_at", null)
            .maybeSingle();
        if (ownerError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not load owner",
            );
        }
        const profile = owner as ProfileRow | null;
        await enqueueFightInviteNotifications(sql, {
            fightId: fight.id,
            fightName: series.name,
            actorName: profile?.handle ?? "",
            userIds: [userId],
            now,
        });
    }
    return "invited";
}

/**
 * Invite the signed-in user to PGG7 and every currently suggested fight.
 * Missing or closed fights are a no-op.
 */
export async function ensureAppWideFightInvite(
    userId: string,
    admin: SupabaseClient = createAdminClient(),
    now: Date = new Date(),
    sql?: Sql,
): Promise<"invited" | "already" | "missing" | "closed"> {
    const seriesList = await loadAppWideSeries(admin);
    if (seriesList.length === 0) {
        return "missing";
    }

    let invited = false;
    let already = false;
    let closed = false;
    for (const series of seriesList) {
        if (!series.join_code || series.paused_at) {
            closed = true;
            continue;
        }
        const fight = await currentJoinableFight(series, admin, now);
        if (!fight) {
            closed = true;
            continue;
        }
        const result = await inviteUserToOpenFight(
            userId,
            series,
            fight,
            admin,
            sql,
            now,
        );
        switch (result) {
            case "invited":
                invited = true;
                break;
            case "already":
                already = true;
                break;
            case "closed":
                closed = true;
                break;
            default: {
                const _exhaustive: never = result;
                return _exhaustive;
            }
        }
    }
    if (invited) return "invited";
    if (already) return "already";
    if (closed) return "closed";
    return "missing";
}

export async function inviteEveryoneToOpenFight(
    series: Pick<FightSeriesRow, "id" | "owner_id" | "join_code" | "paused_at">,
    fight: Pick<FightRow, "id" | "state" | "ends_at">,
    sql: Sql | TransactionSql = createDatabaseClient(),
): Promise<string[]> {
    if (
        !series.join_code ||
        series.paused_at ||
        CLOSED_FIGHT_STATES.has(fight.state)
    ) {
        return [];
    }
    const members = await sql<{ user_id: string }[]>`
        insert into public.fight_members (fight_id, user_id, state)
        select ${fight.id}, profile.id, 'invited'
        from public.profiles as profile
        where profile.deleted_at is null
            and profile.id <> ${series.owner_id}
            and not exists (
                select 1
                from public.fight_members as member
                where member.fight_id = ${fight.id}
                    and member.user_id = profile.id
            )
        on conflict (fight_id, user_id) do nothing
        returning user_id
    `;
    if (members.length === 0) {
        return [];
    }
    const userIds = members.map((member) => member.user_id);
    await sql`
        insert into public.fight_series_members (series_id, user_id, state)
        select ${series.id}, profile.id, 'invited'
        from public.profiles as profile
        where profile.id in ${sql(userIds)}
        on conflict (series_id, user_id) do nothing
    `;
    await sql`
        insert into public.fight_invites (
            fight_id, invited_user_id, token_hash, expires_at
        )
        select ${fight.id}, profile.id,
            encode(sha256(gen_random_bytes(32)), 'hex'),
            ${fight.ends_at}::timestamptz
        from public.profiles as profile
        where profile.id in ${sql(userIds)}
    `;
    return userIds;
}

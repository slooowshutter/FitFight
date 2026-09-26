import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type { FightRow, ProfileRow } from "@/lib/types/database";
import type { CreateFightInput } from "@/lib/types/fights/create-fight";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { lookupProfileByHandle } from "./create-invite-supabase-query";
import { fightSummary } from "./fight-access-supabase-query";
import { enqueueFightInviteNotifications } from "./notification-intents-supabase-query";

export function storedFightIdentity(
    name: string | undefined,
    actionText: string | undefined,
): { name: string; actionText: string | null } {
    const title = name?.trim() ?? "";
    const action = actionText?.trim() ?? "";
    return {
        name: title || action || "Steps Fight",
        actionText: action.length > 0 ? action : null,
    };
}

const IDEMPOTENCY_WINDOW_MS = 2 * 60 * 1000;
const JOIN_CODE_ATTEMPTS = 8;

async function allocateJoinCode(admin: SupabaseClient): Promise<string> {
    for (let attempt = 0; attempt < JOIN_CODE_ATTEMPTS; attempt += 1) {
        const code = randomJoinCode();
        const { data, error } = await admin
            .from("fight_series")
            .select("id")
            .eq("join_code", code)
            .maybeSingle();
        if (error) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not allocate join code",
            );
        }
        if (!data) {
            return code;
        }
    }
    throw new ApiError(
        500,
        ERROR_CODES.db_error,
        "Could not allocate join code",
    );
}

export async function createFight(
    userId: string,
    input: CreateFightInput,
    database: Sql = createDatabaseClient(),
) {
    if (input.metric && input.metric !== "steps") {
        throw new ApiError(
            400,
            ERROR_CODES.invalid_metric,
            "metric must be steps",
        );
    }

    const admin = createAdminClient();
    const { data: profileData, error: profileError } = await admin
        .from("profiles")
        .select("user_id:id, handle, display_name, time_zone")
        .eq("id", userId)
        .maybeSingle();
    if (profileError) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not load profile");
    }
    const profile = profileData as ProfileRow | null;
    if (!profile) {
        throw new ApiError(
            400,
            ERROR_CODES.profile_missing,
            "Profile is missing",
        );
    }

    const startsAt = new Date(input.startsAt).toISOString();
    const endsAt = new Date(input.endsAt).toISOString();
    const since = new Date(Date.now() - IDEMPOTENCY_WINDOW_MS).toISOString();
    const stored = storedFightIdentity(input.name, input.actionText);

    const { data: existingData, error: existingError } = await admin
        .from("fights")
        .select("id, state")
        .eq("owner_id", userId)
        .eq("name", stored.name)
        .eq("starts_at", startsAt)
        .eq("ends_at", endsAt)
        .gte("created_at", since)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();
    if (existingError) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not check existing fight",
        );
    }
    if (existingData) {
        return fightSummary(existingData as Pick<FightRow, "id" | "state">);
    }

    const handles = (input.inviteHandles ?? [])
        .map((handle) => handle.trim())
        .filter((handle) => handle.length > 0);
    const inviteeIds = new Set<string>();
    for (const handle of handles) {
        const invitee = await lookupProfileByHandle(admin, handle);
        if (invitee.user_id === userId) {
            throw new ApiError(
                400,
                ERROR_CODES.validation,
                "Cannot invite yourself",
            );
        }
        inviteeIds.add(invitee.user_id);
    }
    const invitees = [...inviteeIds];
    const state = input.start === "now" ? "live" : "scheduled";
    const source = await ensureAppleHealthSource(userId, { admin });
    const joinCode = await allocateJoinCode(admin);
    const durationSeconds = Math.round(
        (Date.parse(endsAt) - Date.parse(startsAt)) / 1000,
    );
    const ownerName = profile.display_name?.replace(/\s+/g, " ").trim();

    // One transaction: a failure can no longer leave a series without its round, a
    // round without its owner, or only some of the invitations.
    const inserted = await database.begin(async (sql) => {
        const [series] = await sql<{ id: string }[]>`
            insert into public.fight_series (
                owner_id, join_code, visibility, recurring, duration_seconds,
                name, action_text, time_zone
            )
            values (
                ${userId}, ${joinCode}, ${input.visibility}, ${input.recurring}, ${durationSeconds},
                ${stored.name}, ${stored.actionText}, ${input.timeZone}
            )
            returning id
        `;
        const [fight] = await sql<Pick<FightRow, "id" | "state">[]>`
            insert into public.fights (
                owner_id, name, state, starts_at, ends_at, time_zone, metric,
                outcome_rule, goal_policy, default_goal_value, stake_kind,
                stake_minor, currency, action_text, series_id
            )
            values (
                ${userId}, ${stored.name}, ${state}, ${startsAt}, ${endsAt}, ${input.timeZone}, 'steps',
                ${input.outcomeRule}, ${input.goalPolicy}, ${input.defaultGoalValue ?? null}, ${input.stakeKind},
                ${input.stakeMinor ?? null},
                ${input.stakeKind === "money" ? input.currency : (input.currency ?? null)},
                ${stored.actionText}, ${series.id}
            )
            returning id, state::text as state
        `;
        await sql`
            update public.fight_series set current_fight_id = ${fight.id} where id = ${series.id}
        `;
        const now = new Date().toISOString();
        await sql`
            insert into public.fight_members (
                fight_id, user_id, state, accepted_at, selected_source_id, source_label
            )
            values (${fight.id}, ${userId}, 'accepted', ${now}, ${source.id}, ${source.sourceLabel})
        `;
        await sql`
            insert into public.fight_series_members (series_id, user_id, state, joined_at)
            values (${series.id}, ${userId}, 'accepted', ${now})
        `;
        if (invitees.length > 0) {
            await sql`
                insert into public.fight_members (fight_id, user_id, state)
                select ${fight.id}, profile.user_id, 'invited'
                from public.profiles as profile
                where profile.user_id in ${sql(invitees)}
            `;
            await sql`
                insert into public.fight_series_members (series_id, user_id, state)
                select ${series.id}, profile.user_id, 'invited'
                from public.profiles as profile
                where profile.user_id in ${sql(invitees)}
            `;
            // New Fights are joined by id, so the invite token itself is never shown.
            await sql`
                insert into public.fight_invites (fight_id, invited_user_id, token_hash, expires_at)
                select ${fight.id}, profile.user_id,
                    encode(sha256(gen_random_bytes(32)), 'hex'), ${endsAt}::timestamptz
                from public.profiles as profile
                where profile.user_id in ${sql(invitees)}
            `;
            await enqueueFightInviteNotifications(sql, {
                fightId: fight.id,
                fightName: stored.name,
                actorName: ownerName ? ownerName : profile.handle,
                userIds: invitees,
            });
        }
        return fight;
    });

    return fightSummary(inserted as Pick<FightRow, "id" | "state">);
}

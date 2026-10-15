import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { APP_WIDE_JOIN_CODE } from "@/lib/domain/fights/join-code";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightState } from "@/lib/types/database";
import { departFightMemberships } from "./membership-departure-supabase-query";
import type { UpdateFightRequest } from "@/lib/types/fights/update-fight";
import { storedFightIdentity } from "./create-fight-supabase-query";
import { createInvite } from "./create-invite-supabase-query";
import { fightSummary, loadFight } from "./fight-access-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const OPEN_STATES: FightState[] = [
    "live",
    "scheduled",
    "inviting",
    "awaiting_final_sync",
];
export async function updateFight(
    userId: string,
    fightId: string,
    input: UpdateFightRequest,
    admin: SupabaseClient = createAdminClient(),
    now: Date = new Date(),
    sql?: Sql,
) {
    const fight = await loadFight(fightId, admin);
    if (fight.friends) {
        // Either friend may change the loser action of their round.
        const { data, error } = await admin
            .from("fight_members")
            .select("user_id")
            .eq("fight_id", fightId)
            .eq("user_id", userId)
            .eq("state", "accepted")
            .maybeSingle();
        if (error) {
            throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
        }
        if (!data) {
            throw new ApiError(403, ERROR_CODES.forbidden, "Only the two friends can do this");
        }
    } else if (fight.owner_id !== userId) {
        throw new ApiError(403, ERROR_CODES.forbidden, "Only the owner can do this");
    }
    switch (fight.state) {
        case "draft":
        case "inviting":
        case "scheduled":
        case "live":
            break;
        case "awaiting_final_sync":
        case "final":
        case "cancelled":
            throw new ApiError(
                409,
                ERROR_CODES.conflict,
                "This fight can no longer be edited",
            );
        default: {
            const _exhaustive: never = fight.state;
            throw new ApiError(
                409,
                ERROR_CODES.conflict,
                "This fight can no longer be edited",
            );
        }
    }

    if (fight.host_id) {
        // A founder fight keeps its schedule and stays private. Edit screens send these on every save.
        input = {
            ...input,
            visibility: undefined,
            recurring: undefined,
            startsAt: undefined,
            endsAt: undefined,
            timeZone: undefined,
        };
    }
    if (fight.friends) {
        // A friend round keeps its name, month, repetition, privacy and pair. Only the action changes.
        input = { actionText: input.actionText };
    }

    const removeIds = [...new Set(input.removeUserIds ?? [])];
    const inviteHandles = [
        ...new Set(
            (input.inviteHandles ?? [])
                .map((handle) => handle.trim())
                .filter(Boolean),
        ),
    ];
    if (removeIds.includes(fight.owner_id)) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "The owner cannot be removed from this fight",
        );
    }

    const nextStarts = input.startsAt
        ? new Date(input.startsAt)
        : new Date(fight.starts_at);
    const nextEnds = input.endsAt
        ? new Date(input.endsAt)
        : new Date(fight.ends_at);
    if (input.timeZone !== undefined && (fight.state !== "scheduled" || Date.parse(fight.starts_at) <= now.getTime())) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "Time zone can only change before the fight begins",
        );
    }
    if (input.startsAt !== undefined && fight.state !== "scheduled") {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "Start time can only change before the fight begins",
        );
    }
    if (nextEnds.getTime() <= nextStarts.getTime()) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "The end must be after the start",
        );
    }
    if (nextEnds.getTime() <= now.getTime()) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "The end must be in the future",
        );
    }
    if (input.startsAt !== undefined && nextStarts.getTime() <= now.getTime()) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "Choose a start time in the future",
        );
    }

    const identityChanged =
        input.name !== undefined || input.actionText !== undefined;
    const stored = identityChanged
        ? storedFightIdentity(
              input.name !== undefined ? input.name : fight.name,
              input.actionText !== undefined
                  ? input.actionText
                  : (fight.action_text ?? undefined),
          )
        : null;
    const windowChanged =
        nextStarts.getTime() !== Date.parse(fight.starts_at) ||
        nextEnds.getTime() !== Date.parse(fight.ends_at);

    // Before every other write, so a taken code leaves the fight unchanged.
    if (input.joinCode !== undefined && fight.series_id) {
        // Signup and the admin dashboard find the app-wide fight by its code:
        // it never moves, and nobody else takes it.
        if (input.joinCode === APP_WIDE_JOIN_CODE) {
            throw new ApiError(
                409,
                ERROR_CODES.join_code_taken,
                "That code is taken",
            );
        }
        const { data, error } = await admin
            .from("fight_series")
            .update({ join_code: input.joinCode })
            .eq("id", fight.series_id)
            .neq("join_code", APP_WIDE_JOIN_CODE)
            .select("id");
        if (error?.code === "23505") {
            throw new ApiError(
                409,
                ERROR_CODES.join_code_taken,
                "That code is taken",
            );
        }
        if (error) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not update fight",
            );
        }
        if (data.length === 0) {
            throw new ApiError(
                403,
                ERROR_CODES.forbidden,
                "The Everybody fight keeps its code",
            );
        }
    }

    const fightPatch: Record<string, unknown> = {};
    if (stored) {
        fightPatch.name = stored.name;
        fightPatch.action_text = stored.actionText;
    }
    if (input.startsAt !== undefined) {
        fightPatch.starts_at = nextStarts.toISOString();
    }
    if (input.endsAt !== undefined) {
        fightPatch.ends_at = nextEnds.toISOString();
    }
    if (input.timeZone !== undefined) {
        fightPatch.time_zone = input.timeZone;
    }
    if (Object.keys(fightPatch).length > 0) {
        const { error } = await admin
            .from("fights")
            .update(fightPatch)
            .eq("id", fightId);
        if (error) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not update fight",
            );
        }
    }

    if (fight.series_id) {
        const seriesPatch: Record<string, unknown> = {};
        if (stored) {
            seriesPatch.name = stored.name;
            seriesPatch.action_text = stored.actionText;
        }
        if (input.visibility !== undefined) {
            seriesPatch.visibility = input.visibility;
        }
        if (input.recurring !== undefined) {
            seriesPatch.recurring = input.recurring;
        }
        if (input.timeZone !== undefined) {
            seriesPatch.time_zone = input.timeZone;
        }
        if (windowChanged) {
            seriesPatch.duration_seconds = Math.round(
                (nextEnds.getTime() - nextStarts.getTime()) / 1000,
            );
        }
        if (Object.keys(seriesPatch).length > 0) {
            const { error } = await admin
                .from("fight_series")
                .update(seriesPatch)
                .eq("id", fight.series_id);
            if (error) {
                throw new ApiError(
                    500,
                    ERROR_CODES.db_error,
                    "Could not update fight",
                );
            }
        }
    }

    const changedMemberships = new Set<string>();
    for (const removeId of removeIds) {
        const result = await departFightMemberships(userId, fightId, removeId);
        for (const changedId of result.changed) changedMemberships.add(changedId);
    }
    for (const changedId of changedMemberships) await recalculateFight(changedId, now);

    for (const handle of inviteHandles) {
        await createInvite(userId, fightId, handle, admin, sql);
    }

    if (windowChanged) {
        const latest = await loadFight(fightId, admin);
        if (OPEN_STATES.includes(latest.state)) {
            await recalculateFight(fightId, now);
        }
    }

    return fightSummary(await loadFight(fightId, admin));
}

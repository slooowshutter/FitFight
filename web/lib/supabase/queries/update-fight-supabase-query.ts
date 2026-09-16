import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type {
    FightMemberRow,
    FightMemberState,
    FightState,
} from "@/lib/types/database";
import type { UpdateFightRequest } from "@/lib/types/fights/update-fight";
import { storedFightIdentity } from "./create-fight-supabase-query";
import { createInvite } from "./create-invite-supabase-query";
import {
    fightSummary,
    loadFight,
    loadOwnedFight,
    loadSeries,
} from "./fight-access-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const OPEN_STATES: FightState[] = [
    "live",
    "scheduled",
    "inviting",
    "awaiting_final_sync",
];
const ACTIVE_MEMBER_STATES: FightMemberState[] = [
    "invited",
    "accepted",
    "deferred",
];

export async function updateFight(
    userId: string,
    fightId: string,
    input: UpdateFightRequest,
    admin: SupabaseClient = createAdminClient(),
    now: Date = new Date(),
    sql?: Sql,
) {
    const fight = await loadOwnedFight(fightId, userId, admin);
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

    const kickedAccepted = new Set<string>();
    for (const removeId of removeIds) {
        const { data: memberData, error: memberError } = await admin
            .from("fight_members")
            .select("fight_id, user_id, state")
            .eq("fight_id", fightId)
            .eq("user_id", removeId)
            .maybeSingle();
        if (memberError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not load membership",
            );
        }
        const member = memberData as Pick<
            FightMemberRow,
            "user_id" | "state"
        > | null;
        if (!member || member.state === "withdrawn") {
            continue;
        }
        if (!ACTIVE_MEMBER_STATES.includes(member.state)) {
            continue;
        }
        if (member.state === "accepted") {
            kickedAccepted.add(removeId);
        }
        const { error: withdrawError } = await admin
            .from("fight_members")
            .update({ state: "withdrawn" })
            .eq("fight_id", fightId)
            .eq("user_id", removeId);
        if (withdrawError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not remove that person",
            );
        }
        const { error: revokeError } = await admin
            .from("fight_invites")
            .update({ revoked_at: now.toISOString() })
            .eq("fight_id", fightId)
            .eq("invited_user_id", removeId)
            .is("revoked_at", null);
        if (revokeError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not revoke that invite",
            );
        }
        if (fight.series_id) {
            const { error: seriesMemberError } = await admin
                .from("fight_series_members")
                .update({ state: "withdrawn" })
                .eq("series_id", fight.series_id)
                .eq("user_id", removeId);
            if (seriesMemberError) {
                throw new ApiError(
                    500,
                    ERROR_CODES.db_error,
                    "Could not remove that person",
                );
            }
            const series = await loadSeries(fight.series_id, admin);
            const currentId = series.current_fight_id;
            if (currentId && currentId !== fightId) {
                const { error: currentError } = await admin
                    .from("fight_members")
                    .update({ state: "withdrawn" })
                    .eq("fight_id", currentId)
                    .eq("user_id", removeId)
                    .in("state", ACTIVE_MEMBER_STATES);
                if (currentError) {
                    throw new ApiError(
                        500,
                        ERROR_CODES.db_error,
                        "Could not remove that person",
                    );
                }
                const current = await loadFight(currentId, admin);
                if (OPEN_STATES.includes(current.state)) {
                    await recalculateFight(currentId, now);
                }
            }
        }
    }

    for (const handle of inviteHandles) {
        await createInvite(userId, fightId, handle, admin, sql);
    }

    if (kickedAccepted.size > 0 || windowChanged) {
        const latest = await loadFight(fightId, admin);
        if (OPEN_STATES.includes(latest.state)) {
            await recalculateFight(fightId, now);
        }
    }

    return fightSummary(await loadFight(fightId, admin));
}

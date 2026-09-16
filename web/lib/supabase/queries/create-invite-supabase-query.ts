import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { newInviteToken, normalizeHandle } from "@/lib/domain/invites/token";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightMemberRow, ProfileRow } from "@/lib/types/database";
import { loadOwnedFight } from "./fight-access-supabase-query";
import { enqueueFightInviteNotifications } from "./notification-intents-supabase-query";

const HANDLE_FORMAT = /^[a-z0-9_]{2,30}$/;

export async function lookupProfileByHandle(
    admin: SupabaseClient,
    rawHandle: string,
): Promise<ProfileRow> {
    const handle = normalizeHandle(rawHandle);
    if (!HANDLE_FORMAT.test(handle)) {
        throw new ApiError(400, ERROR_CODES.validation, "Invalid handle");
    }
    const { data: profileData, error: profileError } = await admin
        .from("profiles")
        .select("user_id, handle, display_name, time_zone")
        .eq("handle", handle)
        .is("deleted_at", null)
        .maybeSingle();
    if (profileError) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not look up handle",
        );
    }
    const profile = profileData as ProfileRow | null;
    if (!profile) {
        throw new ApiError(
            404,
            ERROR_CODES.handle_not_found,
            "Handle not found",
        );
    }
    return profile;
}

export async function createInvite(
    ownerId: string,
    fightId: string,
    rawHandle: string,
    admin: SupabaseClient = createAdminClient(),
    sql?: Sql,
) {
    const fight = await loadOwnedFight(fightId, ownerId, admin);

    if (["awaiting_final_sync", "final", "cancelled"].includes(fight.state)) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "Cannot invite after the fight has closed",
        );
    }

    const profile = await lookupProfileByHandle(admin, rawHandle);
    if (profile.user_id === ownerId) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "Cannot invite yourself",
        );
    }

    const { data: existingMember, error: memberLookupError } = await admin
        .from("fight_members")
        .select("fight_id, user_id, state")
        .eq("fight_id", fightId)
        .eq("user_id", profile.user_id)
        .maybeSingle();
    if (memberLookupError) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not load membership",
        );
    }
    const member = existingMember as Pick<FightMemberRow, "state"> | null;
    const alreadyInvited = member?.state === "invited";
    if (member) {
        switch (member.state) {
            case "accepted":
            case "deferred":
                throw new ApiError(
                    409,
                    ERROR_CODES.already_member,
                    "User is already in this fight",
                );
            case "invited":
                break;
            case "declined":
            case "withdrawn":
            case "disqualified": {
                const { error: restoreError } = await admin
                    .from("fight_members")
                    .update({ state: "invited", accepted_at: null })
                    .eq("fight_id", fightId)
                    .eq("user_id", profile.user_id);
                if (restoreError) {
                    throw new ApiError(
                        500,
                        ERROR_CODES.db_error,
                        "Could not create membership",
                    );
                }
                break;
            }
            default: {
                const _exhaustive: never = member.state;
                throw new ApiError(
                    409,
                    ERROR_CODES.already_member,
                    "User is already in this fight",
                );
            }
        }
    } else {
        const { error: insertMemberError } = await admin
            .from("fight_members")
            .insert({
                fight_id: fightId,
                user_id: profile.user_id,
                state: "invited",
            });
        if (insertMemberError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not create membership",
            );
        }
    }

    const { token, tokenHash } = newInviteToken();
    const { error: inviteError } = await admin.from("fight_invites").insert({
        fight_id: fightId,
        invited_user_id: profile.user_id,
        token_hash: tokenHash,
        expires_at: fight.ends_at,
    });
    if (inviteError) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not create invite",
        );
    }

    if (fight.series_id) {
        const { error: seriesMemberError } = await admin
            .from("fight_series_members")
            .upsert({
                series_id: fight.series_id,
                user_id: profile.user_id,
                state: "invited",
            });
        if (seriesMemberError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not create membership",
            );
        }
    }

    if (fight.state === "draft") {
        const { error: stateError } = await admin
            .from("fights")
            .update({ state: "inviting" })
            .eq("id", fightId);
        if (stateError) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not update fight state",
            );
        }
    }

    if (sql && !alreadyInvited) {
        const { data: owner } = await admin
            .from("profiles")
            .select("handle, display_name")
            .eq("user_id", ownerId)
            .maybeSingle();
        const display = owner?.display_name?.replace(/\s+/g, " ").trim();
        await enqueueFightInviteNotifications(sql, {
            fightId,
            fightName: fight.name,
            actorName:
                display && display.length > 0
                    ? display
                    : (owner?.handle ?? "user"),
            userIds: [profile.user_id],
        });
    }

    return { token, invitedUserId: profile.user_id };
}

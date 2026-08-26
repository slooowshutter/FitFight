import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "../../db/supabaseAdmin";
import type { FightMemberRow, ProfileRow } from "../../db/types";
import { ApiError, ERROR_CODES } from "../../http";
import { loadOwnedFight } from "../fights/access";
import { newInviteToken, normalizeHandle } from "./token";

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
    throw new ApiError(500, ERROR_CODES.db_error, "Could not look up handle");
  }
  const profile = profileData as ProfileRow | null;
  if (!profile) {
    throw new ApiError(404, ERROR_CODES.handle_not_found, "Handle not found");
  }
  return profile;
}

export async function createInvite(ownerId: string, fightId: string, rawHandle: string) {
  const admin = createAdminClient();
  const fight = await loadOwnedFight(fightId, ownerId, admin);

  if (["awaiting_final_sync", "final", "cancelled"].includes(fight.state)) {
    throw new ApiError(409, ERROR_CODES.conflict, "Cannot invite after the fight has closed");
  }

  const profile = await lookupProfileByHandle(admin, rawHandle);
  if (profile.user_id === ownerId) {
    throw new ApiError(400, ERROR_CODES.validation, "Cannot invite yourself");
  }

  const { data: existingMember, error: memberLookupError } = await admin
    .from("fight_members")
    .select("fight_id, user_id, state")
    .eq("fight_id", fightId)
    .eq("user_id", profile.user_id)
    .maybeSingle();
  if (memberLookupError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  const member = existingMember as Pick<FightMemberRow, "state"> | null;
  if (member && member.state === "accepted") {
    throw new ApiError(409, ERROR_CODES.already_member, "User is already in this fight");
  }
  if (!member) {
    const { error: insertMemberError } = await admin.from("fight_members").insert({
      fight_id: fightId,
      user_id: profile.user_id,
      state: "invited",
    });
    if (insertMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not create membership");
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
    throw new ApiError(500, ERROR_CODES.db_error, "Could not create invite");
  }

  if (fight.state === "draft") {
    const { error: stateError } = await admin
      .from("fights")
      .update({ state: "inviting" })
      .eq("id", fightId);
    if (stateError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not update fight state");
    }
  }

  return { token, invitedUserId: profile.user_id };
}

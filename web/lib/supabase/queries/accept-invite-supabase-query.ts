import { hashInviteToken } from "@/lib/domain/invites/token";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightInviteRow, FightMemberRow } from "@/lib/types/database";
import { ensureAppleHealthSource } from "./apple-health-source-supabase-query";
import { fightSummary, loadFight } from "./fight-access-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

export async function acceptInvite(
  userId: string,
  rawToken: string,
  personalTarget?: number,
) {
  const token = decodeURIComponent(rawToken).trim();
  if (!token) {
    throw new ApiError(400, ERROR_CODES.validation, "Missing invite token");
  }

  const admin = createAdminClient();
  const tokenHash = hashInviteToken(token);
  const { data: inviteData, error: inviteError } = await admin
    .from("fight_invites")
    .select("id, fight_id, invited_user_id, token_hash, expires_at, revoked_at, accepted_at")
    .eq("token_hash", tokenHash)
    .maybeSingle();
  if (inviteError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load invite");
  }
  const invite = inviteData as FightInviteRow | null;
  if (!invite) {
    throw new ApiError(404, ERROR_CODES.not_found, "Invite not found");
  }
  if (invite.revoked_at) {
    throw new ApiError(410, ERROR_CODES.invite_revoked, "Invite was revoked");
  }
  if (new Date(invite.expires_at).getTime() <= Date.now()) {
    throw new ApiError(410, ERROR_CODES.invite_expired, "Invite expired");
  }
  if (invite.invited_user_id && invite.invited_user_id !== userId) {
    throw new ApiError(403, ERROR_CODES.invite_wrong_user, "This invite belongs to another user");
  }

  const fight = await loadFight(invite.fight_id, admin);
  if (fight.state === "cancelled" || fight.state === "final") {
    throw new ApiError(409, ERROR_CODES.conflict, "Fight is no longer joinable");
  }

  const source = await ensureAppleHealthSource(userId, { admin });
  const nowIso = new Date().toISOString();
  const memberPatch = {
    state: "accepted" as const,
    accepted_at: nowIso,
    selected_source_id: source.id,
    source_label: source.sourceLabel,
    personal_target: personalTarget ?? null,
    target_origin: personalTarget !== undefined ? "user" : null,
    acceptance_copy_version: 1,
  };

  const { data: existingMember, error: memberLookupError } = await admin
    .from("fight_members")
    .select("fight_id, user_id, state")
    .eq("fight_id", invite.fight_id)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberLookupError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  const member = existingMember as Pick<FightMemberRow, "state"> | null;

  if (member?.state === "accepted" && invite.accepted_at) {
    return fightSummary(fight);
  }

  if (member) {
    const { error: updateMemberError } = await admin
      .from("fight_members")
      .update(memberPatch)
      .eq("fight_id", invite.fight_id)
      .eq("user_id", userId);
    if (updateMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not accept invite");
    }
  } else {
    const { error: insertMemberError } = await admin.from("fight_members").insert({
      fight_id: invite.fight_id,
      user_id: userId,
      ...memberPatch,
    });
    if (insertMemberError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not accept invite");
    }
  }

  const { error: inviteUpdateError } = await admin
    .from("fight_invites")
    .update({ accepted_at: nowIso })
    .eq("id", invite.id);
  if (inviteUpdateError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not mark invite accepted");
  }

  if (["live", "scheduled", "awaiting_final_sync"].includes(fight.state)) {
    await recalculateFight(fight.id, admin);
  }

  return fightSummary(await loadFight(fight.id, admin));
}

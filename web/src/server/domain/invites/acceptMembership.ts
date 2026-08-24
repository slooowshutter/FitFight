import { createAdminClient } from "../../db/supabaseAdmin";
import type { FightMemberRow } from "../../db/types";
import { ApiError, ERROR_CODES } from "../../http";
import { recalculateFight } from "../../scoring/recalculateFight";
import { fightSummary, loadFight } from "../fights/access";
import { ensureAppleHealthSource } from "../sources/ensureAppleHealthSource";

/** In-app accept: the signed-in User is already an invited member. No raw token. */
export async function acceptMembership(
  userId: string,
  fightId: string,
  personalTarget?: number,
) {
  const admin = createAdminClient();
  const fight = await loadFight(fightId, admin);
  if (fight.state === "cancelled" || fight.state === "final") {
    throw new ApiError(409, ERROR_CODES.conflict, "Fight is no longer joinable");
  }

  const { data: existingMember, error: memberLookupError } = await admin
    .from("fight_members")
    .select("fight_id, user_id, state")
    .eq("fight_id", fightId)
    .eq("user_id", userId)
    .maybeSingle();
  if (memberLookupError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load membership");
  }
  const member = existingMember as Pick<FightMemberRow, "state"> | null;
  if (!member) {
    throw new ApiError(403, ERROR_CODES.forbidden, "You were not invited to this fight");
  }
  if (member.state === "accepted") {
    return fightSummary(fight);
  }
  if (member.state !== "invited") {
    throw new ApiError(409, ERROR_CODES.conflict, "This membership cannot be accepted");
  }

  const source = await ensureAppleHealthSource(userId, { admin });
  const nowIso = new Date().toISOString();
  const { error: updateMemberError } = await admin
    .from("fight_members")
    .update({
      state: "accepted",
      accepted_at: nowIso,
      selected_source_id: source.id,
      source_label: source.sourceLabel,
      personal_target: personalTarget ?? null,
      target_origin: personalTarget !== undefined ? "user" : null,
      acceptance_copy_version: 1,
    })
    .eq("fight_id", fightId)
    .eq("user_id", userId);
  if (updateMemberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not accept fight");
  }

  await admin
    .from("fight_invites")
    .update({ accepted_at: nowIso })
    .eq("fight_id", fightId)
    .eq("invited_user_id", userId)
    .is("accepted_at", null);

  if (["live", "scheduled", "awaiting_final_sync"].includes(fight.state)) {
    await recalculateFight(fight.id, admin);
  }

  return fightSummary(await loadFight(fight.id, admin));
}

import { createAdminClient } from "../../db/supabaseAdmin";
import { ApiError, ERROR_CODES } from "../../http";
import { fightSummary, loadOwnedFight } from "./access";

export async function cancelFight(userId: string, fightId: string) {
  const admin = createAdminClient();
  const fight = await loadOwnedFight(fightId, userId, admin);

  if (fight.state === "final") {
    throw new ApiError(409, ERROR_CODES.fight_not_cancellable, "Final fights cannot be cancelled");
  }
  if (fight.state === "cancelled") {
    return fightSummary(fight);
  }

  const { data: updated, error } = await admin
    .from("fights")
    .update({ state: "cancelled" })
    .eq("id", fightId)
    .select("id, state")
    .single();
  if (error || !updated) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not cancel fight");
  }
  return fightSummary(updated);
}

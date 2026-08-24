import { createAdminClient } from "../../db/supabaseAdmin";
import { ApiError, ERROR_CODES } from "../../http";
import { fightSummary, loadOwnedFight } from "./access";

export async function startFight(
  userId: string,
  fightId: string,
  when: "now" | "scheduled" = "now",
) {
  const admin = createAdminClient();
  const fight = await loadOwnedFight(fightId, userId, admin);

  if (fight.state === "cancelled" || fight.state === "final") {
    throw new ApiError(409, ERROR_CODES.fight_not_startable, "Fight cannot be started");
  }
  if (fight.state === "awaiting_final_sync") {
    throw new ApiError(409, ERROR_CODES.fight_not_startable, "Fight has already ended");
  }
  if (fight.state === "live") {
    return fightSummary(fight);
  }

  const startsInFuture = new Date(fight.starts_at).getTime() > Date.now();
  const nextState = when === "scheduled" && startsInFuture ? "scheduled" : "live";

  const { data: updated, error } = await admin
    .from("fights")
    .update({ state: nextState })
    .eq("id", fightId)
    .select("id, state")
    .single();
  if (error || !updated) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not start fight");
  }
  return fightSummary(updated);
}

import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { fightSummary, loadOwnedFight } from "./fight-access-supabase-query";

export async function cancelFight(userId: string, fightId: string) {
  const admin = createAdminClient();
  const fight = await loadOwnedFight(fightId, userId, admin);

  if (fight.state === "cancelled") {
    return fightSummary(fight);
  }

  const { data: updated, error } = await admin
    .from("fights")
    .update({ state: "cancelled" })
    .eq("id", fightId)
    .in("state", ["draft", "inviting", "scheduled", "live", "awaiting_final_sync"])
    .select("id, state")
    .maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not cancel fight");
  }
  if (!updated) {
    throw new ApiError(409, ERROR_CODES.fight_not_cancellable, "Final fights cannot be cancelled");
  }
  return fightSummary(updated);
}

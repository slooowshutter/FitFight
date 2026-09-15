import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { fightSummary, loadOwnedFight } from "./fight-access-supabase-query";

export async function cancelFight(
  userId: string,
  fightId: string,
  admin: SupabaseClient = createAdminClient(),
  now: Date = new Date(),
) {
  const fight = await loadOwnedFight(fightId, userId, admin);

  switch (fight.state) {
    case "final":
      throw new ApiError(409, ERROR_CODES.fight_not_cancellable, "Final fights cannot be cancelled");
    case "cancelled":
      return fightSummary(fight);
    case "draft":
    case "inviting":
    case "scheduled":
    case "live":
    case "awaiting_final_sync":
      break;
    default: {
      const _exhaustive: never = fight.state;
      throw new ApiError(409, ERROR_CODES.fight_not_cancellable, "Final fights cannot be cancelled");
    }
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

  if (fight.series_id) {
    const { error: seriesError } = await admin
      .from("fight_series")
      .update({ paused_at: now.toISOString() })
      .eq("id", fight.series_id)
      .is("paused_at", null);
    if (seriesError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not cancel fight");
    }
  }

  return fightSummary(updated);
}

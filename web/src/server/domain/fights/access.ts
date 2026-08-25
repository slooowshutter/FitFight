import type { SupabaseClient } from "@supabase/supabase-js";
import { createAdminClient } from "../../db/supabaseAdmin";
import type { FightRow } from "../../db/types";
import { ApiError, ERROR_CODES } from "../../http";

export async function loadFight(
  fightId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<FightRow> {
  const { data, error } = await admin.from("fights").select("*").eq("id", fightId).maybeSingle();
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight");
  }
  if (!data) {
    throw new ApiError(404, ERROR_CODES.not_found, "Fight not found");
  }
  return data as FightRow;
}

export async function loadOwnedFight(
  fightId: string,
  userId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<FightRow> {
  const fight = await loadFight(fightId, admin);
  if (fight.owner_id !== userId) {
    throw new ApiError(403, ERROR_CODES.forbidden, "Only the owner can do this");
  }
  return fight;
}

export function fightSummary(fight: Pick<FightRow, "id" | "state">) {
  return { id: fight.id, state: fight.state };
}

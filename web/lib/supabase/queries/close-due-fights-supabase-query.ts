import type { SupabaseClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { fightNeedsCloserTick } from "@/lib/scoring/fight-clock";
import { createAdminClient } from "@/lib/supabase/admin";
import type { FightState } from "@/lib/types/database";
import { mintDueRecurringFights } from "./mint-recurring-fight-supabase-query";
import {
  listFightsToRecalculate,
  recalculateFight,
} from "./recalculate-fight-supabase-query";

const DUE_STATES = ["live", "scheduled", "awaiting_final_sync"] as const;
const BATCH = 25;

type CloseCandidate = {
  id: string;
  state: FightState;
  starts_at: string;
  ends_at: string;
};

export type CloseDueResult = {
  checked: number;
  closed: number;
  fightIds: string[];
};

function dueIds(rows: CloseCandidate[], nowMs: number): string[] {
  return rows
    .filter((row) =>
      fightNeedsCloserTick({
        state: row.state,
        nowMs,
        startsAtMs: Date.parse(row.starts_at),
        endsAtMs: Date.parse(row.ends_at),
      }),
    )
    .map((row) => row.id);
}

async function recalculateIds(
  fightIds: string[],
  admin: SupabaseClient,
  now: Date,
): Promise<string[]> {
  const closed: string[] = [];
  for (const fightId of fightIds.slice(0, BATCH)) {
    await recalculateFight(fightId, admin, now);
    closed.push(fightId);
  }
  return closed;
}

/** Server job: walk fights whose clock can move, using `now` so tests fake time. */
export async function closeDueFights(
  admin: SupabaseClient = createAdminClient(),
  now: Date = new Date(),
): Promise<CloseDueResult> {
  const { data, error } = await admin
    .from("fights")
    .select("id, state, starts_at, ends_at")
    .in("state", [...DUE_STATES])
    .order("ends_at", { ascending: true })
    .limit(200);
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fights to close");
  }
  const rows = (data ?? []) as CloseCandidate[];
  const fightIds = await recalculateIds(dueIds(rows, now.getTime()), admin, now);
  await mintDueRecurringFights(admin, now);
  return { checked: rows.length, closed: fightIds.length, fightIds };
}

/** Opening the app: close this user's due fights even if cron has not run. */
export async function closeDueFightsForUser(
  userId: string,
  admin: SupabaseClient = createAdminClient(),
  now: Date = new Date(),
): Promise<CloseDueResult> {
  const ids = await listFightsToRecalculate(userId, admin);
  if (ids.length === 0) {
    await mintDueRecurringFights(admin, now);
    return { checked: 0, closed: 0, fightIds: [] };
  }
  const { data, error } = await admin
    .from("fights")
    .select("id, state, starts_at, ends_at")
    .in("id", ids);
  if (error) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fights to close");
  }
  const rows = (data ?? []) as CloseCandidate[];
  const fightIds = await recalculateIds(dueIds(rows, now.getTime()), admin, now);
  await mintDueRecurringFights(admin, now);
  return { checked: rows.length, closed: fightIds.length, fightIds };
}

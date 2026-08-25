import type { FightState } from "../db/types";

export type FightClockInput = {
  state: FightState;
  nowMs: number;
  endsAtMs: number;
  graceEndsMs: number;
  allSourcesCompleteThroughEnd: boolean;
};

/** Pure clock. Tests pass a fake `now`. Recalc uses this so a 7-day fight does not need 7 days. */
export function nextFightState(input: FightClockInput): FightState {
  const { state, nowMs, endsAtMs, graceEndsMs, allSourcesCompleteThroughEnd } = input;
  if (
    state === "draft" ||
    state === "final" ||
    state === "cancelled" ||
    state === "inviting" ||
    state === "scheduled"
  ) {
    return state;
  }

  let next: FightState = state;
  if (state === "live" && nowMs > endsAtMs) {
    next = "awaiting_final_sync";
  }

  const inFinalSync = next === "awaiting_final_sync";
  if (inFinalSync && (nowMs > graceEndsMs || allSourcesCompleteThroughEnd)) {
    return "final";
  }
  return next;
}

export function observationOverlapsWindow(
  startsAt: string,
  endsAt: string,
  windowStartsAt: string,
  windowEndsAt: string,
): boolean {
  return startsAt < windowEndsAt && endsAt > windowStartsAt;
}

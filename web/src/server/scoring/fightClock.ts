import type { FightState } from "../db/types";

export type FightClockInput = {
  state: FightState;
  nowMs: number;
  startsAtMs: number;
  endsAtMs: number;
  graceEndsMs: number;
  allSourcesCompleteThroughEnd: boolean;
};

export type FightDueInput = {
  state: FightState;
  nowMs: number;
  startsAtMs: number;
  endsAtMs: number;
};

/** Pure clock. Tests pass a fake `now`. A 7-day fight does not need 7 days to verify. */
export function nextFightState(input: FightClockInput): FightState {
  const {
    state,
    nowMs,
    startsAtMs,
    endsAtMs,
    graceEndsMs,
    allSourcesCompleteThroughEnd,
  } = input;
  if (state === "draft" || state === "final" || state === "cancelled" || state === "inviting") {
    return state;
  }

  let next: FightState = state;
  if (state === "scheduled" && nowMs >= startsAtMs) {
    next = "live";
  }
  if ((next === "live" || state === "live") && nowMs > endsAtMs) {
    next = "awaiting_final_sync";
  }

  if (next === "awaiting_final_sync" && (nowMs > graceEndsMs || allSourcesCompleteThroughEnd)) {
    return "final";
  }
  return next;
}

/** True when a closer tick can change this fight. Mid-window live fights stay put. */
export function fightNeedsCloserTick(input: FightDueInput): boolean {
  const { state, nowMs, startsAtMs, endsAtMs } = input;
  if (state === "draft" || state === "final" || state === "cancelled" || state === "inviting") {
    return false;
  }
  if (state === "scheduled") {
    return nowMs >= startsAtMs;
  }
  if (state === "live") {
    return nowMs > endsAtMs;
  }
  return state === "awaiting_final_sync";
}

export function observationOverlapsWindow(
  startsAt: string,
  endsAt: string,
  windowStartsAt: string,
  windowEndsAt: string,
): boolean {
  return startsAt < windowEndsAt && endsAt > windowStartsAt;
}

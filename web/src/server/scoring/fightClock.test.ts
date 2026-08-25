import assert from "node:assert/strict";
import { test } from "node:test";
import { fightNeedsCloserTick, nextFightState, observationOverlapsWindow } from "./fightClock";

const hour = 60 * 60 * 1000;
const day = 24 * hour;
const starts = Date.parse("2026-08-24T22:00:00.000Z");
const ends = Date.parse("2026-08-31T22:00:00.000Z");
const grace = ends + day;

function clock(
  state: Parameters<typeof nextFightState>[0]["state"],
  nowMs: number,
  extra: Partial<Parameters<typeof nextFightState>[0]> = {},
) {
  return nextFightState({
    state,
    nowMs,
    startsAtMs: starts,
    endsAtMs: ends,
    graceEndsMs: grace,
    allSourcesCompleteThroughEnd: false,
    ...extra,
  });
}

test("live fight stays live before ends_at", () => {
  assert.equal(clock("live", ends - hour), "live");
});

test("live fight moves to awaiting_final_sync the second the window closes", () => {
  assert.equal(clock("live", ends + 1), "awaiting_final_sync");
});

test("grace window stays open until every source is complete through the end", () => {
  assert.equal(clock("awaiting_final_sync", ends + hour), "awaiting_final_sync");
  assert.equal(
    clock("awaiting_final_sync", ends + hour, { allSourcesCompleteThroughEnd: true }),
    "final",
  );
});

test("grace expiry finalizes even if someone never uploaded", () => {
  assert.equal(clock("awaiting_final_sync", grace + 1), "final");
});

test("final and cancelled never move", () => {
  for (const state of ["final", "cancelled"] as const) {
    assert.equal(clock(state, grace + hour, { allSourcesCompleteThroughEnd: true }), state);
  }
});

test("scheduled fight goes live at starts_at, not before", () => {
  assert.equal(clock("scheduled", starts - 1), "scheduled");
  assert.equal(clock("scheduled", starts), "live");
});

test("a scheduled fight that is already past ends_at closes in one tick", () => {
  assert.equal(clock("scheduled", ends + 1), "awaiting_final_sync");
  assert.equal(clock("scheduled", grace + 1), "final");
});

test("steps after ends_at do not overlap the fight window", () => {
  assert.equal(
    observationOverlapsWindow(
      "2026-08-31T22:00:00.000Z",
      "2026-09-01T22:00:00.000Z",
      "2026-08-24T22:00:00.000Z",
      "2026-08-31T22:00:00.000Z",
    ),
    false,
  );
  assert.equal(
    observationOverlapsWindow(
      "2026-08-30T22:00:00.000Z",
      "2026-08-31T22:00:00.000Z",
      "2026-08-24T22:00:00.000Z",
      "2026-08-31T22:00:00.000Z",
    ),
    true,
  );
});

test("3, 7, and 14 day fights resolve on a fake clock", () => {
  for (const days of [1, 3, 7, 14]) {
    const windowStart = Date.parse("2026-09-01T00:00:00.000Z");
    const windowEnd = windowStart + days * day;
    const graceEnd = windowEnd + day;
    const mid = windowStart + Math.floor((days * day) / 2);
    const input = {
      startsAtMs: windowStart,
      endsAtMs: windowEnd,
      graceEndsMs: graceEnd,
      allSourcesCompleteThroughEnd: false,
    };

    assert.equal(
      nextFightState({ state: "live", nowMs: mid, ...input }),
      "live",
      `${days}d still live at midpoint`,
    );
    assert.equal(
      nextFightState({ state: "live", nowMs: windowEnd + 1, ...input }),
      "awaiting_final_sync",
      `${days}d awaits sync just after end`,
    );
    assert.equal(
      nextFightState({ state: "awaiting_final_sync", nowMs: graceEnd + 1, ...input }),
      "final",
      `${days}d is final after 24h grace`,
    );
    assert.equal(
      observationOverlapsWindow(
        new Date(windowEnd).toISOString(),
        new Date(windowEnd + day).toISOString(),
        new Date(windowStart).toISOString(),
        new Date(windowEnd).toISOString(),
      ),
      false,
      `${days}d ignores steps after the window`,
    );
  }
});

test("closer only ticks fights that can change", () => {
  const mid = starts + 3 * day;
  assert.equal(
    fightNeedsCloserTick({ state: "live", nowMs: mid, startsAtMs: starts, endsAtMs: ends }),
    false,
  );
  assert.equal(
    fightNeedsCloserTick({ state: "live", nowMs: ends + 1, startsAtMs: starts, endsAtMs: ends }),
    true,
  );
  assert.equal(
    fightNeedsCloserTick({
      state: "scheduled",
      nowMs: starts - 1,
      startsAtMs: starts,
      endsAtMs: ends,
    }),
    false,
  );
  assert.equal(
    fightNeedsCloserTick({ state: "scheduled", nowMs: starts, startsAtMs: starts, endsAtMs: ends }),
    true,
  );
  assert.equal(
    fightNeedsCloserTick({
      state: "awaiting_final_sync",
      nowMs: ends + hour,
      startsAtMs: starts,
      endsAtMs: ends,
    }),
    true,
  );
  assert.equal(
    fightNeedsCloserTick({ state: "final", nowMs: grace + 1, startsAtMs: starts, endsAtMs: ends }),
    false,
  );
});

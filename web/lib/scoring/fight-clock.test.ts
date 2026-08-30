import assert from "node:assert/strict";
import { test } from "node:test";
import { fightNeedsCloserTick, nextFightState, observationOverlapsWindow } from "./fight-clock";

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

test("fight state follows its exact clock boundaries", () => {
  assert.equal(clock("scheduled", starts - 1), "scheduled");
  assert.equal(clock("scheduled", starts), "live");
  assert.equal(clock("live", ends - 1), "live");
  assert.equal(clock("live", ends + 1), "awaiting_final_sync");
  assert.equal(clock("awaiting_final_sync", ends + hour), "awaiting_final_sync");
  assert.equal(
    clock("awaiting_final_sync", ends + hour, { allSourcesCompleteThroughEnd: true }),
    "final",
  );
  assert.equal(clock("awaiting_final_sync", grace + 1), "final");
  assert.equal(clock("final", grace + hour), "final");
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

test("closer only ticks fights that can change", () => {
  assert.equal(
    fightNeedsCloserTick({ state: "live", nowMs: ends - hour, startsAtMs: starts, endsAtMs: ends }),
    false,
  );
  assert.equal(
    fightNeedsCloserTick({ state: "live", nowMs: ends + 1, startsAtMs: starts, endsAtMs: ends }),
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

import assert from "node:assert/strict";
import { test } from "node:test";
import { nextFightState, observationOverlapsWindow } from "./fightClock";

const hour = 60 * 60 * 1000;
const ends = Date.parse("2026-08-31T22:00:00.000Z");
const grace = ends + 24 * hour;

test("live fight stays live before ends_at", () => {
  assert.equal(
    nextFightState({
      state: "live",
      nowMs: ends - hour,
      endsAtMs: ends,
      graceEndsMs: grace,
      allSourcesCompleteThroughEnd: false,
    }),
    "live",
  );
});

test("live fight moves to awaiting_final_sync the second the window closes", () => {
  assert.equal(
    nextFightState({
      state: "live",
      nowMs: ends + 1,
      endsAtMs: ends,
      graceEndsMs: grace,
      allSourcesCompleteThroughEnd: false,
    }),
    "awaiting_final_sync",
  );
});

test("grace window stays open until every source is complete through the end", () => {
  assert.equal(
    nextFightState({
      state: "awaiting_final_sync",
      nowMs: ends + hour,
      endsAtMs: ends,
      graceEndsMs: grace,
      allSourcesCompleteThroughEnd: false,
    }),
    "awaiting_final_sync",
  );
  assert.equal(
    nextFightState({
      state: "awaiting_final_sync",
      nowMs: ends + hour,
      endsAtMs: ends,
      graceEndsMs: grace,
      allSourcesCompleteThroughEnd: true,
    }),
    "final",
  );
});

test("grace expiry finalizes even if someone never uploaded", () => {
  assert.equal(
    nextFightState({
      state: "awaiting_final_sync",
      nowMs: grace + 1,
      endsAtMs: ends,
      graceEndsMs: grace,
      allSourcesCompleteThroughEnd: false,
    }),
    "final",
  );
});

test("final and cancelled never move", () => {
  for (const state of ["final", "cancelled"] as const) {
    assert.equal(
      nextFightState({
        state,
        nowMs: grace + hour,
        endsAtMs: ends,
        graceEndsMs: grace,
        allSourcesCompleteThroughEnd: true,
      }),
      state,
    );
  }
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

import assert from "node:assert/strict";
import { test } from "node:test";
import { fightNeedsCloserTick } from "./fightClock";

const hour = 60 * 60 * 1000;
const day = 24 * hour;

test("a 3-day New-fight window needs a closer tick only after it ends", () => {
  const startsAtMs = Date.parse("2026-09-01T12:00:00.000Z");
  const endsAtMs = startsAtMs + 3 * day;

  assert.equal(
    fightNeedsCloserTick({
      state: "live",
      nowMs: startsAtMs + 2 * day,
      startsAtMs,
      endsAtMs,
    }),
    false,
  );
  assert.equal(
    fightNeedsCloserTick({
      state: "live",
      nowMs: endsAtMs + 1,
      startsAtMs,
      endsAtMs,
    }),
    true,
  );
  assert.equal(
    fightNeedsCloserTick({
      state: "awaiting_final_sync",
      nowMs: endsAtMs + hour,
      startsAtMs,
      endsAtMs,
    }),
    true,
  );
  assert.equal(
    fightNeedsCloserTick({
      state: "final",
      nowMs: endsAtMs + day + hour,
      startsAtMs,
      endsAtMs,
    }),
    false,
  );
});

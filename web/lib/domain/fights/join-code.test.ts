import assert from "node:assert/strict";
import { test } from "node:test";
import {
  isJoinCode,
  normalizeJoinCode,
  randomJoinCode,
  rollingWindow,
} from "./join-code";

test("normalizeJoinCode strips spaces and dashes and uppercases", () => {
  assert.equal(normalizeJoinCode(" ab-c1 "), "ABC1");
  assert.equal(normalizeJoinCode("k7m2"), "K7M2");
});

test("isJoinCode accepts the 4-character alphabet and rejects lookalikes", () => {
  assert.equal(isJoinCode("K7M2"), true);
  assert.equal(isJoinCode("2345"), true);
  assert.equal(isJoinCode("ABCD"), true);
  assert.equal(isJoinCode("O0I1"), false);
  assert.equal(isJoinCode("K7M"), false);
  assert.equal(isJoinCode("k7m2"), false);
});

test("randomJoinCode draws from the join-code alphabet", () => {
  const code = randomJoinCode(() => 0);
  assert.equal(code, "2222");
  assert.equal(isJoinCode(code), true);
});

test("rollingWindow starts the next fight at the previous ends_at", () => {
  const next = rollingWindow("2026-09-01T12:00:00.000Z", "2026-09-08T12:00:00.000Z");
  assert.equal(next.startsAt, "2026-09-08T12:00:00.000Z");
  assert.equal(next.endsAt, "2026-09-15T12:00:00.000Z");
});

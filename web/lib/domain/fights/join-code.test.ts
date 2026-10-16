import assert from "node:assert/strict";
import { test } from "node:test";
import {
    APP_WIDE_JOIN_CODE,
    isJoinCode,
    normalizeJoinCode,
    randomJoinCode,
    rollingWindow,
} from "./join-code";

test("normalizeJoinCode strips spaces and dashes and uppercases", () => {
    assert.equal(normalizeJoinCode(" ab-c1 "), "ABC1");
    assert.equal(normalizeJoinCode("k7m2"), "K7M2");
});

test("the app-wide join code is the existing PGG7 alphabet value", () => {
    assert.equal(APP_WIDE_JOIN_CODE, "PGG7");
    assert.equal(isJoinCode(APP_WIDE_JOIN_CODE), true);
    assert.equal(normalizeJoinCode("pgg7"), APP_WIDE_JOIN_CODE);
});

test("isJoinCode accepts 4 to 12 uppercase letters or digits", () => {
    assert.equal(isJoinCode("K7M2"), true);
    assert.equal(isJoinCode("2345"), true);
    assert.equal(isJoinCode("ABCD"), true);
    assert.equal(isJoinCode("O0I1"), true);
    assert.equal(isJoinCode("GOLFCLUB2026"), true);
    assert.equal(isJoinCode("K7M"), false);
    assert.equal(isJoinCode("GOLFCLUB20261"), false);
    assert.equal(isJoinCode("k7m2"), false);
    assert.equal(isJoinCode("GOLF_CLUB"), false);
});

test("randomJoinCode draws from the join-code alphabet", () => {
    const code = randomJoinCode(() => 0);
    assert.equal(code, "2222");
    assert.equal(isJoinCode(code), true);
});

test("rollingWindow starts the next fight at the previous ends_at", () => {
    const next = rollingWindow(
        "2026-09-01T12:00:00.000Z",
        "2026-09-08T12:00:00.000Z",
    );
    assert.equal(next.startsAt, "2026-09-08T12:00:00.000Z");
    assert.equal(next.endsAt, "2026-09-15T12:00:00.000Z");
});

import assert from "node:assert/strict";
import { test } from "node:test";
import { FRIEND_FIGHT_TIME_ZONE } from "@/lib/types/fights/friend-fight";
import { calendarMonthWindow } from "./friend-fights-supabase-query";

test("a friend round runs from the 1st to the next 1st in UTC", () => {
    assert.equal(FRIEND_FIGHT_TIME_ZONE, "UTC");
    assert.deepEqual(calendarMonthWindow(new Date("2026-01-31T23:59:59.999Z"), "UTC"), {
        startsAt: "2026-01-01T00:00:00.000Z",
        endsAt: "2026-02-01T00:00:00.000Z",
    });
    assert.deepEqual(calendarMonthWindow(new Date("2026-02-01T00:00:00.000Z"), "UTC"), {
        startsAt: "2026-02-01T00:00:00.000Z",
        endsAt: "2026-03-01T00:00:00.000Z",
    }, "February 2026 has 28 days");
    assert.deepEqual(calendarMonthWindow(new Date("2028-02-29T12:00:00.000Z"), "UTC"), {
        startsAt: "2028-02-01T00:00:00.000Z",
        endsAt: "2028-03-01T00:00:00.000Z",
    }, "February 2028 has 29 days");
    assert.deepEqual(calendarMonthWindow(new Date("2026-04-15T08:00:00.000Z"), "UTC"), {
        startsAt: "2026-04-01T00:00:00.000Z",
        endsAt: "2026-05-01T00:00:00.000Z",
    });
    assert.deepEqual(calendarMonthWindow(new Date("2026-12-31T23:00:00.000Z"), "UTC"), {
        startsAt: "2026-12-01T00:00:00.000Z",
        endsAt: "2027-01-01T00:00:00.000Z",
    }, "December rolls into January of the next year");
});

test("each next round starts where the last one ended", () => {
    let at = new Date("2026-10-15T00:00:00.000Z");
    const lengths: number[] = [];
    for (let round = 0; round < 6; round += 1) {
        const month = calendarMonthWindow(at, "UTC");
        lengths.push((Date.parse(month.endsAt) - Date.parse(month.startsAt)) / 86_400_000);
        at = new Date(month.endsAt);
    }
    assert.deepEqual(lengths, [31, 30, 31, 31, 28, 31], "October 2026 through March 2027");
});

test("another zone keeps local midnight across daylight saving", () => {
    assert.deepEqual(calendarMonthWindow(new Date("2026-10-31T23:30:00.000Z"), "Europe/Paris"), {
        startsAt: "2026-10-31T23:00:00.000Z",
        endsAt: "2026-11-30T23:00:00.000Z",
    }, "already November in Paris, after the clocks went back");
    assert.deepEqual(calendarMonthWindow(new Date("2026-03-10T12:00:00.000Z"), "America/Los_Angeles"), {
        startsAt: "2026-03-01T08:00:00.000Z",
        endsAt: "2026-04-01T07:00:00.000Z",
    }, "March starts in standard time and ends in daylight time");
    assert.deepEqual(calendarMonthWindow(new Date("2026-12-31T20:00:00.000Z"), "Asia/Tokyo"), {
        startsAt: "2026-12-31T15:00:00.000Z",
        endsAt: "2027-01-31T15:00:00.000Z",
    }, "already January in Tokyo");
});

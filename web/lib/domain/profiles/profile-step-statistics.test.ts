import assert from "node:assert/strict";
import { test } from "node:test";
import type { ProfileActivityDay } from "@/lib/types/profiles/shared-profile";
import { profileStepStatisticsSchema } from "@/lib/types/profiles/profile-step-statistics";
import { profileStepStatistics } from "./profile-step-statistics";

function day(date: string, steps: number, finalized = true, timeZone: string | null = "Europe/Paris"): ProfileActivityDay {
    return { day: date, steps, finalized, time_zone: timeZone, updated_at: `${date}T23:00:00Z` };
}

const context = { today: "2026-09-17", time_zone: "Europe/Paris" };

test("five activity categories match the companion thresholds and partition the recorded days", () => {
    const values = [0, 1_999, 2_000, 3_999, 4_000, 5_999, 6_000, 7_999, 8_000]
        .map((steps, index) => day(`2026-09-${String(index + 1).padStart(2, "0")}`, steps));
    const stats = profileStepStatistics(values, context, null);
    assert.deepEqual(stats.levels.map((level) => level.days), [2, 2, 2, 2, 1]);
    assert.equal(stats.levels.reduce((sum, level) => sum + level.share!, 0), 1);
    assert.equal(stats.recorded_days, 9);
    assert.deepEqual(stats.best_day, { day: "2026-09-09", steps: 8_000 });
    assert.deepEqual(profileStepStatisticsSchema.parse(stats), stats);
});

test("exact-category streaks end on another category and cannot bridge unknown days", () => {
    const stats = profileStepStatistics([
        day("2026-09-10", 8_000), day("2026-09-11", 9_000),
        day("2026-09-12", 7_000), day("2026-09-14", 8_000), day("2026-09-16", 8_000),
    ], context, null);
    assert.equal(stats.levels[4].longest_streak, 2);
    assert.equal(stats.levels[4].current_streak, 1);
    assert.equal(stats.levels[3].longest_streak, 1);
    assert.equal(stats.levels[3].current_streak, 0);
    assert.equal(stats.unknown_days, 2);
});

test("current streak runs through yesterday, never through partial today", () => {
    const stats = profileStepStatistics([
        day("2026-09-14", 8_000), day("2026-09-15", 8_000), day("2026-09-16", 9_000),
        day("2026-09-17", 1_000, false), day("2026-09-18", 50_000),
    ], context, null);
    assert.equal(stats.levels[4].current_streak, 3);
    assert.equal(stats.recorded_days, 3);
    assert.equal(stats.best_day?.steps, 9_000);
});

test("partial and unknown-zone history is excluded without fabricating zeros or a current streak", () => {
    const stats = profileStepStatistics([
        day("2026-09-14", 0), day("2026-09-15", 20_000, true, null), day("2026-09-16", 30_000, false),
    ], context, null);
    assert.equal(stats.recorded_days, 1);
    assert.equal(stats.unknown_days, 2);
    assert.equal(stats.average_steps, 0);
    assert.equal(stats.best_day?.steps, 0);
    assert.equal(stats.levels[0].days, 1);
    assert.ok(stats.levels.every((level) => level.current_streak === null));
});

test("the week is Monday through yesterday, with the observed denominator made explicit", () => {
    const stats = profileStepStatistics([
        day("2026-09-13", 50_000), day("2026-09-14", 6_000), day("2026-09-16", 10_000),
    ], context, null);
    assert.deepEqual(stats.week, {
        starts_on: "2026-09-14", elapsed_days: 3, recorded_days: 2, total_steps: 16_000, average_steps: 8_000,
    });
});

test("shared windows clip records and streaks before calculation while owner records retain older evidence", () => {
    const values = [day("2026-08-01", 40_000), day("2026-09-10", 8_000), day("2026-09-11", 9_000), day("2026-09-12", 8_000)];
    const shared = profileStepStatistics(values, context, 7);
    assert.equal(shared.from, "2026-09-11");
    assert.equal(shared.recorded_days, 2);
    assert.equal(shared.best_day?.steps, 9_000);
    assert.equal(shared.levels[4].longest_streak, 2);
    assert.equal(shared.unknown_days, 4);
    assert.equal(profileStepStatistics(values, context, null).best_day?.steps, 40_000);
    assert.equal(profileStepStatistics(values, context, 30).from, "2026-08-19");
});

test("empty history and Monday do not claim a zero-step weekly average", () => {
    const stats = profileStepStatistics([], { today: "2026-09-14", time_zone: "UTC" }, null);
    assert.equal(stats.from, null);
    assert.equal(stats.best_day, null);
    assert.equal(stats.average_steps, null);
    assert.equal(stats.week.elapsed_days, 0);
    assert.equal(stats.week.average_steps, null);
    assert.ok(stats.levels.every((level) => level.share === null && level.current_streak === null));
});

test("civil dates stay consecutive across daylight saving, leap days, and year boundaries", () => {
    for (const [first, second, today] of [
        ["2026-03-28", "2026-03-29", "2026-03-30"],
        ["2024-02-28", "2024-02-29", "2024-03-01"],
        ["2026-12-31", "2027-01-01", "2027-01-02"],
    ]) {
        const stats = profileStepStatistics([day(second, 10_000), day(first, 8_000)], { today, time_zone: "Europe/Paris" }, null);
        assert.equal(stats.levels[4].current_streak, 2);
        assert.equal(stats.unknown_days, 0);
    }
});

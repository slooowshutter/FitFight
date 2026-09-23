import assert from "node:assert/strict";
import { test } from "node:test";
import { healthKitActivityBatchSchema } from "@/lib/types/healthkit/healthkit-activity-batch";
import {
    measurementFromRaw,
    workoutDayMeasurements,
} from "./activity-measurements";

const raw = {
    id: "11111111-1111-4111-8111-111111111111",
    time_zone: "Europe/Paris",
    payload_hash: "a".repeat(64),
    collected_at: "2026-09-23T10:00:00.000Z",
};

test("a merged daily total becomes one day measurement that knows whether the day was complete", () => {
    const partial = measurementFromRaw({
        ...raw,
        record_kind: "total",
        record_type: "steps",
        record_key: "day:2026-09-23",
        payload: {
            metric: "steps",
            day: "2026-09-23",
            starts_at: "2026-09-22T22:00:00.000Z",
            ends_at: "2026-09-23T10:00:00.000Z",
            time_zone: "Europe/Paris",
            value: 4_000,
            unit: "steps",
        },
    })[0];
    assert.deepEqual(
        {
            scope: partial?.scope,
            day: partial?.day,
            ends_at: partial?.ends_at,
            observed_through: partial?.observed_through,
            inputs: partial?.input_ids,
        },
        {
            scope: "day",
            day: "2026-09-23",
            ends_at: "2026-09-23T22:00:00.000Z",
            observed_through: "2026-09-23T10:00:00.000Z",
            inputs: [raw.id],
        },
    );
});

test("a selected deletion removes the workout instead of producing a measurement", () => {
    assert.deepEqual(
        measurementFromRaw({
            ...raw,
            record_kind: "deletion",
            record_type: "workout",
            record_key: "22222222-2222-4222-8222-222222222222",
            payload: { healthkit_uuid: "22222222-2222-4222-8222-222222222222" },
        }),
        [],
    );
});

test("workout day totals count workouts once and never mix in merged daily totals", () => {
    const workouts = [
        { id: "33333333-3333-4333-8333-333333333333", type: "running", start: "2026-09-22T06:00:00.000Z", minutes: 30, distance: 5_000 },
        { id: "44444444-4444-4444-8444-444444444444", type: "yoga", start: "2026-09-22T18:00:00.000Z", minutes: 60, distance: null },
        { id: "55555555-5555-4555-8555-555555555555", type: "walking", start: "2026-09-22T22:30:00.000Z", minutes: 20, distance: 1_500 },
    ].flatMap((workout) =>
        measurementFromRaw({
            ...raw,
            id: workout.id,
            record_kind: "workout",
            record_type: "workout",
            record_key: workout.id,
            payload: {
                healthkit_uuid: workout.id,
                started_at: workout.start,
                ended_at: new Date(Date.parse(workout.start) + workout.minutes * 60_000).toISOString(),
                activity_type: workout.type,
                duration_seconds: workout.minutes * 60,
                distance_m: workout.distance,
            },
        }),
    );
    assert.equal(workouts.filter((row) => row.metric === "duration").length, 3);
    assert.deepEqual(workouts.filter((row) => row.metric === "distance").map((row) => row.value), [5_000, 1_500]);
    const derived = workoutDayMeasurements(
        workouts,
        new Date("2026-09-24T12:00:00.000Z"),
    );
    assert.deepEqual(
        derived.map(({ day, metric, value, input_ids }) => ({ day, metric, value, inputs: input_ids.length })),
        [
            { day: "2026-09-22", metric: "workout_count", value: 2, inputs: 2 },
            { day: "2026-09-22", metric: "workout_time", value: 5_400, inputs: 2 },
            { day: "2026-09-22", metric: "walk_run_workout_distance", value: 5_000, inputs: 1 },
            { day: "2026-09-23", metric: "workout_count", value: 1, inputs: 1 },
            { day: "2026-09-23", metric: "workout_time", value: 1_200, inputs: 1 },
            { day: "2026-09-23", metric: "walk_run_workout_distance", value: 1_500, inputs: 1 },
        ],
        "Paris civil days place a 00:30 workout on the next day",
    );
});

test("activity pages carry exact civil-day totals, unique workouts, and unambiguous deletions", () => {
    const page = {
        collected_at: "2026-09-23T10:00:00.000Z",
        time_zone: "Europe/Paris",
        totals: [
            {
                metric: "steps",
                day: "2020-01-01",
                starts_at: "2019-12-31T23:00:00.000Z",
                ends_at: "2020-01-01T23:00:00.000Z",
                value: 12_000,
                unit: "steps",
            },
        ],
        deleted_workouts: ["66666666-6666-4666-8666-666666666666"],
    };
    assert.equal(healthKitActivityBatchSchema.safeParse(page).success, true, "History has no age cap");
    for (const invalid of [
        { ...page, totals: [{ ...page.totals[0], value: 1.5 }] },
        { ...page, totals: [{ ...page.totals[0], unit: "count" }] },
        { ...page, totals: [{ ...page.totals[0], metric: "workout_count", unit: "count" }] },
        { ...page, totals: [page.totals[0], page.totals[0]] },
        { ...page, totals: [{ ...page.totals[0], ends_at: "2020-01-01T12:00:00.000Z" }] },
        {
            ...page,
            workouts: [
                {
                    healthkit_uuid: "66666666-6666-4666-8666-666666666666",
                    started_at: "2026-09-22T06:00:00.000Z",
                    ended_at: "2026-09-22T07:00:00.000Z",
                    activity_type: "running",
                    duration_seconds: 3_600,
                },
            ],
        },
    ]) {
        assert.equal(healthKitActivityBatchSchema.safeParse(invalid).success, false);
    }
});

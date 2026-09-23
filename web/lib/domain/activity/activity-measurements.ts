import { civilDayBounds, civilDayStamp } from "@/lib/scoring/civil-day";
import {
    dayTotalPayloadSchema,
    fightTotalPayloadSchema,
    workoutPayloadSchema,
    type ActivityMeasurement,
    type SelectedActivityRaw,
} from "@/lib/types/activity/activity-pipeline";

export const ACTIVITY_RESOLVER_VERSION = 1;

/** Day metrics FitFight derives from workout records instead of accepting client sums. */
export const workoutDayMetricValues = [
    "workout_count",
    "workout_time",
    "walk_run_workout_distance",
] as const;

/** One current input creates one row per measured quantity, never an increment of a prior row. */
export function measurementFromRaw(
    raw: SelectedActivityRaw,
): ActivityMeasurement[] {
    if (raw.record_kind === "deletion") {
        return [];
    }
    if (raw.record_kind === "workout") {
        const workout = workoutPayloadSchema.parse(raw.payload);
        const zone = raw.time_zone ?? "UTC";
        const endsAt = new Date(workout.ended_at).toISOString();
        const base = {
            scope: "workout" as const,
            scope_key: raw.record_key,
            starts_at: new Date(workout.started_at).toISOString(),
            ends_at: endsAt,
            observed_through: endsAt,
            day: civilDayStamp(new Date(workout.started_at), zone),
            time_zone: zone,
            fight_id: null,
            input_ids: [raw.id],
        };
        const measurements: ActivityMeasurement[] = [{
            ...base,
            metric: "duration",
            value: workout.duration_seconds,
            unit: "s",
            details: { activity_type: workout.activity_type, effort: workout.effort ?? null },
        }];
        const values = [
            { metric: "active_minutes", value: workout.active_minutes, unit: "min" },
            { metric: "distance", value: workout.distance_m, unit: "m" },
            { metric: "active_energy", value: workout.energy_kcal, unit: "kcal" },
        ];
        for (const item of values) {
            if (item.value !== null && item.value !== undefined) {
                measurements.push({
                    ...base,
                    metric: item.metric,
                    value: item.value,
                    unit: item.unit,
                    details: item.metric === "distance"
                        ? { activity_type: workout.activity_type }
                        : {},
                });
            }
        }
        return measurements;
    }
    if (raw.record_key.startsWith("fight:")) {
        const total = fightTotalPayloadSchema.parse(raw.payload);
        return [{
            scope: "fight_window",
            scope_key: total.fight_id,
            metric: "steps",
            starts_at: total.starts_at,
            ends_at: total.ends_at,
            observed_through: total.cutoff_at,
            day: null,
            time_zone: total.time_zone,
            fight_id: total.fight_id,
            value: total.steps,
            unit: "steps",
            details: { step_checkpoints: total.step_checkpoints },
            input_ids: [raw.id],
        }];
    }
    const total = dayTotalPayloadSchema.parse(raw.payload);
    return [{
        scope: "day",
        scope_key: total.day,
        metric: total.metric,
        starts_at: total.starts_at,
        ends_at: civilDayBounds(
            total.day,
            total.time_zone ?? "UTC",
        ).endsAt.toISOString(),
        observed_through: total.ends_at,
        day: total.day,
        time_zone: total.time_zone,
        fight_id: null,
        value: total.value,
        unit: total.unit,
        details: {},
        input_ids: [raw.id],
    }];
}

/**
 * Day totals derived from the current workout measurements of the given days. Workouts and merged
 * daily totals are never summed together. A day left without contributing workouts has no row.
 */
export function workoutDayMeasurements(
    workouts: ActivityMeasurement[],
    now: Date,
): ActivityMeasurement[] {
    const byDay = new Map<string, ActivityMeasurement[]>();
    for (const workout of workouts) {
        if (workout.day === null) {
            continue;
        }
        byDay.set(workout.day, [...(byDay.get(workout.day) ?? []), workout]);
    }
    return [...byDay].flatMap(([day, dayMeasurements]) => {
        const durations = dayMeasurements.filter((row) => row.metric === "duration");
        if (durations.length === 0) {
            return [];
        }
        const zone = durations[0].time_zone ?? "UTC";
        const bounds = civilDayBounds(day, zone);
        const walkRun = dayMeasurements.filter(
            (row) => row.metric === "distance" &&
                ["walking", "running"].includes(String(row.details.activity_type)),
        );
        const base = {
            scope: "day" as const,
            scope_key: day,
            starts_at: bounds.startsAt.toISOString(),
            ends_at: bounds.endsAt.toISOString(),
            observed_through: new Date(
                Math.min(bounds.endsAt.getTime(), now.getTime()),
            ).toISOString(),
            day,
            time_zone: zone,
            fight_id: null,
            details: {},
        };
        const derived: ActivityMeasurement[] = [
            {
                ...base,
                metric: "workout_count",
                value: durations.length,
                unit: "count",
                input_ids: durations.flatMap((row) => row.input_ids),
            },
            {
                ...base,
                metric: "workout_time",
                value: durations.reduce((sum, row) => sum + row.value, 0),
                unit: "s",
                input_ids: durations.flatMap((row) => row.input_ids),
            },
        ];
        if (walkRun.length > 0) {
            derived.push({
                ...base,
                metric: "walk_run_workout_distance",
                value: walkRun.reduce((sum, row) => sum + row.value, 0),
                unit: "m",
                input_ids: walkRun.flatMap((row) => row.input_ids),
            });
        }
        return derived;
    });
}

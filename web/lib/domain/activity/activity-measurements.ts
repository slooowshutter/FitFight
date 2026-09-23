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

/**
 * Replace-not-increment: an identity's current measurement comes only from its selected raw row.
 * A selected deletion means the workout no longer exists, so it returns null.
 */
export function measurementFromRaw(
    raw: SelectedActivityRaw,
): ActivityMeasurement | null {
    if (raw.record_kind === "deletion") {
        return null;
    }
    if (raw.record_kind === "workout") {
        const workout = workoutPayloadSchema.parse(raw.payload);
        const zone = raw.time_zone ?? "UTC";
        const endsAt = new Date(workout.ended_at).toISOString();
        return {
            scope: "workout",
            scope_key: raw.record_key,
            metric: "workout",
            starts_at: new Date(workout.started_at).toISOString(),
            ends_at: endsAt,
            observed_through: endsAt,
            day: civilDayStamp(new Date(workout.started_at), zone),
            time_zone: zone,
            fight_id: null,
            value: workout.duration_seconds,
            unit: "s",
            details: {
                activity_type: workout.activity_type,
                active_minutes: workout.active_minutes ?? null,
                distance_m: workout.distance_m ?? null,
                energy_kcal: workout.energy_kcal ?? null,
                effort: workout.effort ?? null,
            },
            input_ids: [raw.id],
        };
    }
    if (raw.record_key.startsWith("fight:")) {
        const total = fightTotalPayloadSchema.parse(raw.payload);
        return {
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
        };
    }
    const total = dayTotalPayloadSchema.parse(raw.payload);
    return {
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
    };
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
    return [...byDay].flatMap(([day, dayWorkouts]) => {
        const zone = dayWorkouts[0].time_zone ?? "UTC";
        const bounds = civilDayBounds(day, zone);
        const walkRun = dayWorkouts.filter(
            (workout) =>
                ["walking", "running"].includes(
                    String(workout.details.activity_type),
                ) && typeof workout.details.distance_m === "number",
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
                value: dayWorkouts.length,
                unit: "count",
                input_ids: dayWorkouts.flatMap((workout) => workout.input_ids),
            },
            {
                ...base,
                metric: "workout_time",
                value: dayWorkouts.reduce((sum, workout) => sum + workout.value, 0),
                unit: "s",
                input_ids: dayWorkouts.flatMap((workout) => workout.input_ids),
            },
        ];
        if (walkRun.length > 0) {
            derived.push({
                ...base,
                metric: "walk_run_workout_distance",
                value: walkRun.reduce(
                    (sum, workout) => sum + Number(workout.details.distance_m),
                    0,
                ),
                unit: "m",
                input_ids: walkRun.flatMap((workout) => workout.input_ids),
            });
        }
        return derived;
    });
}

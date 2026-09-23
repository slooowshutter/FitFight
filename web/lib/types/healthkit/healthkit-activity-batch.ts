import { z } from "zod";
import { civilDayBounds, isCivilDay } from "@/lib/scoring/civil-day";
import { timeZoneSchema } from "@/lib/types/time/time-zone";
import {
    healthKitActivityUnitByMetric,
    healthKitWorkoutSchema,
} from "@/lib/types/healthkit/healthkit-activity";

/** Apple-merged daily totals the phone sends. Workout day metrics are derived from workout records. */
export const healthKitTotalMetricValues = [
    "steps",
    "active_energy",
    "resting_energy",
    "walking_running_distance",
    "exercise_minutes",
    "stand_minutes",
    "stand_hours",
    "flights_climbed",
    "cycling_distance",
    "swimming_distance",
    "move_time_minutes",
    "wheelchair_distance",
    "wheelchair_pushes",
    "swimming_strokes",
    "rowing_distance",
    "paddle_distance",
    "skating_distance",
    "cross_country_ski_distance",
    "downhill_snow_distance",
] as const;

export const healthKitTotalMetricSchema = z.enum(healthKitTotalMetricValues);

export const healthKitTotalUnitByMetric = {
    ...healthKitActivityUnitByMetric,
    steps: "steps",
} as const;

export const MAX_ACTIVITY_BATCH_TOTALS = 1_000;
export const MAX_ACTIVITY_BATCH_WORKOUTS = 200;
export const MAX_ACTIVITY_BATCH_DELETIONS = 500;
const MAX_TOTAL_VALUE = 2_147_483_647;

const dateTimeSchema = z.string().datetime({ offset: true });

export const healthKitDayTotalSchema = z
    .object({
        metric: healthKitTotalMetricSchema,
        day: z.string().refine(isCivilDay, "must be YYYY-MM-DD"),
        starts_at: dateTimeSchema,
        ends_at: dateTimeSchema,
        value: z.number().finite().min(0).max(MAX_TOTAL_VALUE),
        unit: z.string().min(1).max(16),
    })
    .strict()
    .superRefine((value, context) => {
        if (value.unit !== healthKitTotalUnitByMetric[value.metric]) {
            context.addIssue({
                code: z.ZodIssueCode.custom,
                message: "unit does not match metric",
                path: ["unit"],
            });
        }
        if (value.metric === "steps" && !Number.isInteger(value.value)) {
            context.addIssue({
                code: z.ZodIssueCode.custom,
                message: "steps must be a whole number",
                path: ["value"],
            });
        }
    });

export const healthKitActivityBatchSchema = z
    .object({
        collected_at: dateTimeSchema,
        time_zone: timeZoneSchema,
        totals: z
            .array(healthKitDayTotalSchema)
            .max(MAX_ACTIVITY_BATCH_TOTALS)
            .default([]),
        workouts: z
            .array(healthKitWorkoutSchema)
            .max(MAX_ACTIVITY_BATCH_WORKOUTS)
            .default([]),
        deleted_workouts: z
            .array(
                z
                    .string()
                    .uuid()
                    .transform((value) => value.toLowerCase()),
            )
            .max(MAX_ACTIVITY_BATCH_DELETIONS)
            .default([]),
    })
    .strict()
    .superRefine((value, context) => {
        const collectedAt = Date.parse(value.collected_at);
        const totalKeys = new Set<string>();
        value.totals.forEach((total, index) => {
            const key = `${total.metric}:${total.day}`;
            if (totalKeys.has(key)) {
                context.addIssue({
                    code: z.ZodIssueCode.custom,
                    message: "duplicate daily total",
                    path: ["totals", index, "day"],
                });
            }
            totalKeys.add(key);
            const bounds = civilDayBounds(total.day, value.time_zone);
            if (Date.parse(total.starts_at) !== bounds.startsAt.getTime()) {
                context.addIssue({
                    code: z.ZodIssueCode.custom,
                    message: "starts_at must equal the civil-day start",
                    path: ["totals", index, "starts_at"],
                });
            }
            if (
                Date.parse(total.ends_at) !==
                    Math.min(bounds.endsAt.getTime(), collectedAt) ||
                Date.parse(total.ends_at) <= Date.parse(total.starts_at)
            ) {
                context.addIssue({
                    code: z.ZodIssueCode.custom,
                    message: "ends_at must equal the effective civil-day end",
                    path: ["totals", index, "ends_at"],
                });
            }
        });
        const workoutIds = new Set<string>();
        value.workouts.forEach((workout, index) => {
            if (workoutIds.has(workout.healthkit_uuid)) {
                context.addIssue({
                    code: z.ZodIssueCode.custom,
                    message: "duplicate workout",
                    path: ["workouts", index, "healthkit_uuid"],
                });
            }
            workoutIds.add(workout.healthkit_uuid);
            if (Date.parse(workout.ended_at) > collectedAt) {
                context.addIssue({
                    code: z.ZodIssueCode.custom,
                    message: "ended_at exceeds collected_at",
                    path: ["workouts", index, "ended_at"],
                });
            }
        });
        const deletedIds = new Set<string>();
        value.deleted_workouts.forEach((id, index) => {
            if (deletedIds.has(id) || workoutIds.has(id)) {
                context.addIssue({
                    code: z.ZodIssueCode.custom,
                    message: "a workout can appear once per batch",
                    path: ["deleted_workouts", index],
                });
            }
            deletedIds.add(id);
        });
    });

export const activityProcessingValues = ["processed", "pending"] as const;
export const activityProcessingSchema = z.enum(activityProcessingValues);

export const healthKitActivityBatchResponseSchema = z
    .object({
        received: z.number().int().min(0),
        processing: activityProcessingSchema,
    })
    .strict();

export type HealthKitTotalMetric = z.infer<typeof healthKitTotalMetricSchema>;
export type HealthKitDayTotal = z.infer<typeof healthKitDayTotalSchema>;
export type HealthKitActivityBatch = z.infer<
    typeof healthKitActivityBatchSchema
>;
export type ActivityProcessing = z.infer<typeof activityProcessingSchema>;
export type HealthKitActivityBatchResponse = z.infer<
    typeof healthKitActivityBatchResponseSchema
>;

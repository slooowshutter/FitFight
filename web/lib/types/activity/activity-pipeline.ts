import { z } from "zod";
import { fightStepCheckpointSchema } from "@/lib/types/fights/fight-step-checkpoint";
import { healthKitWorkoutSchema } from "@/lib/types/healthkit/healthkit-activity";
import { healthKitSampleSchema } from "@/lib/types/healthkit/healthkit-activity-batch";

export const activityRecordKindValues = ["total", "workout", "sample", "deletion"] as const;

export type JsonValue =
    | string
    | number
    | boolean
    | null
    | JsonValue[]
    | { [key: string]: JsonValue };

export const jsonValueSchema: z.ZodType<JsonValue> = z.lazy(() =>
    z.union([
        z.string(),
        z.number(),
        z.boolean(),
        z.null(),
        z.array(jsonValueSchema),
        z.record(jsonValueSchema),
    ]),
);
export const activityScopeValues = ["workout", "sample", "day", "fight_window"] as const;

const timestampSchema = z
    .string()
    .refine((value) => Number.isFinite(Date.parse(value)))
    .transform((value) => new Date(value).toISOString());

export const dayTotalPayloadSchema = z.object({
    metric: z.string().min(1),
    day: z.string().date(),
    starts_at: timestampSchema,
    ends_at: timestampSchema,
    /** Null only for legacy calendar rows saved before time zones were recorded. */
    time_zone: z.string().min(1).nullable(),
    value: z.number().finite().nonnegative(),
    unit: z.string().min(1),
});

export const fightTotalPayloadSchema = z.object({
    fight_id: z.string().uuid(),
    starts_at: timestampSchema,
    ends_at: timestampSchema,
    cutoff_at: timestampSchema,
    time_zone: z.string().min(1),
    steps: z.number().int().nonnegative(),
    step_checkpoints: z.array(fightStepCheckpointSchema).nullable(),
});

export const workoutPayloadSchema = healthKitWorkoutSchema;
export const samplePayloadSchema = healthKitSampleSchema;

/** The newest effective raw row for one record identity, as selected by the resolver. */
export const selectedActivityRawSchema = z.object({
    id: z.string().uuid(),
    record_kind: z.enum(activityRecordKindValues),
    record_type: z.string(),
    record_key: z.string(),
    time_zone: z.string().nullable(),
    payload: z.record(jsonValueSchema),
    payload_hash: z.string(),
    collected_at: timestampSchema,
});

export const claimedActivityRawSchema = z.object({
    id: z.string().uuid(),
    user_id: z.string().uuid(),
    source_id: z.string().uuid(),
    record_kind: z.enum(activityRecordKindValues),
    record_type: z.string(),
    record_key: z.string(),
});

export const activityMeasurementSchema = z.object({
    scope: z.enum(activityScopeValues),
    scope_key: z.string(),
    metric: z.string(),
    starts_at: z.string(),
    ends_at: z.string(),
    observed_through: z.string(),
    day: z.string().nullable(),
    time_zone: z.string().nullable(),
    fight_id: z.string().uuid().nullable(),
    value: z.number().finite().nonnegative(),
    unit: z.string(),
    details: z.record(jsonValueSchema),
    input_ids: z.array(z.string().uuid()).min(1),
});

export type ActivityRecordKind = (typeof activityRecordKindValues)[number];
export type DayTotalPayload = z.infer<typeof dayTotalPayloadSchema>;
export type FightTotalPayload = z.infer<typeof fightTotalPayloadSchema>;
export type WorkoutPayload = z.infer<typeof workoutPayloadSchema>;
export type SamplePayload = z.infer<typeof samplePayloadSchema>;
export type SelectedActivityRaw = z.infer<typeof selectedActivityRawSchema>;
export type ClaimedActivityRaw = z.infer<typeof claimedActivityRawSchema>;
export type ActivityMeasurement = z.infer<typeof activityMeasurementSchema>;
/** One record for durable intake; `payload` keys are built in a fixed order so equal content hashes equally. */
export type ActivityRawRecord = {
    record_kind: ActivityRecordKind;
    record_type: string;
    record_key: string;
    starts_at: string | null;
    ends_at: string | null;
    time_zone: string | null;
    payload: Record<string, JsonValue>;
};

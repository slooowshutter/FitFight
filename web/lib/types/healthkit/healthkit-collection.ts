import { z } from "zod";
import { civilDayBounds, isCivilDay } from "@/lib/scoring/civil-day";

const MAX_DAY_ROWS = 4000;
export const healthCollectionSessionsPerKind = 2000;
export const healthKitCollectionMaxBytes = 4_000_000;
const MAX_VALUE = 1_000_000_000_000;
const MAX_DURATION_SECONDS = 2_592_000;

const dateTimeSchema = z.string().datetime({ offset: true });
const civilDaySchema = z.string().refine(isCivilDay, "must be YYYY-MM-DD");
const timeZoneSchema = z.string().min(1).max(100).refine((value) => {
  try {
    Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}, "invalid time zone");

export const healthCollectionMetricValues = [
  "distance_walking_running",
  "flights_climbed",
  "active_energy",
  "basal_energy",
  "exercise_time",
  "stand_time",
  "resting_heart_rate",
  "walking_heart_rate_average",
  "body_mass",
] as const;
export const healthCollectionMetricSchema = z.enum(healthCollectionMetricValues);

export const healthCollectionUnitByMetric = {
  distance_walking_running: "m",
  flights_climbed: "count",
  active_energy: "kcal",
  basal_energy: "kcal",
  exercise_time: "min",
  stand_time: "min",
  resting_heart_rate: "count/min",
  walking_heart_rate_average: "count/min",
  body_mass: "kg",
} as const;

export const healthCollectionSessionKindValues = ["workout", "sleep", "mindful"] as const;
export const healthCollectionSessionKindSchema = z.enum(healthCollectionSessionKindValues);
const MAX_SESSIONS = healthCollectionSessionsPerKind * healthCollectionSessionKindValues.length;

const healthCollectionDaySchema = z.object({
  day: civilDaySchema,
  metric: healthCollectionMetricSchema,
  value: z.number().finite().min(0).max(MAX_VALUE),
  unit: z.string().min(1).max(20),
  starts_at: dateTimeSchema,
  ends_at: dateTimeSchema,
}).strict().superRefine((value, context) => {
  if (healthCollectionUnitByMetric[value.metric] !== value.unit) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "unit does not match metric",
      path: ["unit"],
    });
  }
  if (Date.parse(value.ends_at) <= Date.parse(value.starts_at)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ends_at must follow starts_at",
      path: ["ends_at"],
    });
  }
});

const healthCollectionSessionSchema = z.object({
  source_uuid: z.string().uuid().transform((value) => value.toLowerCase()),
  kind: healthCollectionSessionKindSchema,
  activity_type: z.string().min(1).max(64),
  starts_at: dateTimeSchema,
  ends_at: dateTimeSchema,
  duration_seconds: z.number().finite().min(0).max(MAX_DURATION_SECONDS),
  energy_kcal: z.number().finite().min(0).max(MAX_VALUE).nullish(),
  distance_m: z.number().finite().min(0).max(MAX_VALUE).nullish(),
}).strict().superRefine((value, context) => {
  if (Date.parse(value.ends_at) <= Date.parse(value.starts_at)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ends_at must follow starts_at",
      path: ["ends_at"],
    });
  }
});

export const healthKitCollectionSyncSchema = z.object({
  complete_through: dateTimeSchema,
  time_zone: timeZoneSchema,
  days: z.array(healthCollectionDaySchema).max(MAX_DAY_ROWS),
  sessions: z.array(healthCollectionSessionSchema).max(MAX_SESSIONS),
}).strict().superRefine((value, context) => {
  const completeThrough = Date.parse(value.complete_through);
  const dayKeys = new Set<string>();
  value.days.forEach((day, index) => {
    if (!isCivilDay(day.day)) {
      return;
    }
    const key = `${day.metric}:${day.day}`;
    if (dayKeys.has(key)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate metric day",
        path: ["days", index, "day"],
      });
    }
    dayKeys.add(key);
    const bounds = civilDayBounds(day.day, value.time_zone);
    if (Date.parse(day.ends_at) > completeThrough) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at exceeds complete_through",
        path: ["days", index, "ends_at"],
      });
    }
    if (Date.parse(day.starts_at) !== bounds.startsAt.getTime()) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "starts_at must equal the civil-day start",
        path: ["days", index, "starts_at"],
      });
    }
    if (Date.parse(day.ends_at) !== Math.min(bounds.endsAt.getTime(), completeThrough)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at must equal the effective civil-day end",
        path: ["days", index, "ends_at"],
      });
    }
  });
  const sessionIds = new Set<string>();
  const sessionsPerKind = {
    workout: 0,
    sleep: 0,
    mindful: 0,
  };
  value.sessions.forEach((session, index) => {
    if (sessionIds.has(session.source_uuid)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate session",
        path: ["sessions", index, "source_uuid"],
      });
    }
    sessionIds.add(session.source_uuid);
    sessionsPerKind[session.kind] += 1;
    if (Date.parse(session.ends_at) > completeThrough) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at exceeds complete_through",
        path: ["sessions", index, "ends_at"],
      });
    }
  });
  healthCollectionSessionKindValues.forEach((kind) => {
    if (sessionsPerKind[kind] > healthCollectionSessionsPerKind) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "too many sessions of one kind",
        path: ["sessions"],
      });
    }
  });
});

export const healthKitCollectionSyncResponseSchema = z.object({
  complete_through: dateTimeSchema,
  synced_days: z.number().int().min(0),
  synced_sessions: z.number().int().min(0),
}).strict();

export type HealthCollectionMetric = z.infer<typeof healthCollectionMetricSchema>;
export type HealthCollectionSessionKind = z.infer<typeof healthCollectionSessionKindSchema>;
export type HealthKitCollectionSync = z.infer<typeof healthKitCollectionSyncSchema>;
export type HealthKitCollectionSyncResponse = z.infer<
  typeof healthKitCollectionSyncResponseSchema
>;

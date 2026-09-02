import { z } from "zod";
import { civilDayBounds, isCivilDay } from "@/lib/scoring/civil-day";

const MAX_MERGED_DAYS = 400;
const MAX_FIGHT_AGGREGATES = 100;
const MAX_STEP_COUNT = 2_147_483_647;

const uuidV4Schema = z.string().uuid().refine(
  (value) => value[14] === "4" && ["8", "9", "a", "b"].includes(value[19]?.toLowerCase()),
  "must be a UUID v4",
).transform((value) => value.toLowerCase());
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
const stepCountSchema = z.number().int().min(0).max(MAX_STEP_COUNT);

const healthKitMergedDaySchema = z.object({
  day: civilDaySchema,
  starts_at: dateTimeSchema,
  ends_at: dateTimeSchema,
  steps: stepCountSchema,
}).strict().superRefine((value, context) => {
  if (Date.parse(value.ends_at) <= Date.parse(value.starts_at)) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ends_at must follow starts_at",
      path: ["ends_at"],
    });
  }
});

const healthKitFightAggregateSchema = z.object({
  fight_id: uuidV4Schema,
  starts_at: dateTimeSchema,
  ends_at: dateTimeSchema,
  cutoff_at: dateTimeSchema,
  steps: stepCountSchema,
}).strict().superRefine((value, context) => {
  const startsAt = Date.parse(value.starts_at);
  const endsAt = Date.parse(value.ends_at);
  const cutoffAt = Date.parse(value.cutoff_at);
  if (endsAt <= startsAt) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "ends_at must follow starts_at",
      path: ["ends_at"],
    });
  }
  if (cutoffAt <= startsAt || cutoffAt > endsAt) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "cutoff_at is outside the Fight window",
      path: ["cutoff_at"],
    });
  }
});

export const healthKitAggregateSyncSchema = z.object({
  complete_through: dateTimeSchema,
  time_zone: timeZoneSchema,
  merged_days: z.array(healthKitMergedDaySchema).max(MAX_MERGED_DAYS),
  fight_aggregates: z.array(healthKitFightAggregateSchema).max(MAX_FIGHT_AGGREGATES),
}).strict().superRefine((value, context) => {
  const completeThrough = Date.parse(value.complete_through);
  const mergedDays = new Set<string>();
  value.merged_days.forEach((day, index) => {
    if (!isCivilDay(day.day)) {
      return;
    }
    const bounds = civilDayBounds(day.day, value.time_zone);
    if (mergedDays.has(day.day)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate merged day",
        path: ["merged_days", index, "day"],
      });
    }
    mergedDays.add(day.day);
    if (Date.parse(day.ends_at) > completeThrough) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at exceeds complete_through",
        path: ["merged_days", index, "ends_at"],
      });
    }
    if (Date.parse(day.starts_at) !== bounds.startsAt.getTime()) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "starts_at must equal the civil-day start",
        path: ["merged_days", index, "starts_at"],
      });
    }
    if (Date.parse(day.ends_at) !== Math.min(bounds.endsAt.getTime(), completeThrough)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "ends_at must equal the effective civil-day end",
        path: ["merged_days", index, "ends_at"],
      });
    }
  });
  const fightIds = new Set<string>();
  value.fight_aggregates.forEach((aggregate, index) => {
    if (fightIds.has(aggregate.fight_id)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "duplicate Fight aggregate",
        path: ["fight_aggregates", index, "fight_id"],
      });
    }
    fightIds.add(aggregate.fight_id);
    const expectedCutoff = Math.min(completeThrough, Date.parse(aggregate.ends_at));
    if (Date.parse(aggregate.cutoff_at) !== expectedCutoff) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: "cutoff_at does not match complete_through",
        path: ["fight_aggregates", index, "cutoff_at"],
      });
    }
  });
});

export const healthKitAggregateSyncResponseSchema = z.object({
  complete_through: dateTimeSchema,
  synced_days: z.number().int().min(0),
  synced_fights: z.number().int().min(0),
}).strict();

export type HealthKitAggregateSync = z.infer<typeof healthKitAggregateSyncSchema>;
export type HealthKitAggregateSyncResponse = z.infer<
  typeof healthKitAggregateSyncResponseSchema
>;

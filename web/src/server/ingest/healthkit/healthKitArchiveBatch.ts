import { z } from "zod";
import { isCivilDay } from "../../scoring/civilDay";

const dateTime = z.string().datetime({ offset: true });
const optionalText = z.string().max(500).nullable().optional();

function isTimeZone(value: string): boolean {
  try {
    Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}

const timeZone = z.string().min(1).max(100).refine(isTimeZone, "invalid time zone");
const civilDay = z.string().refine(isCivilDay, "day must be YYYY-MM-DD");

const metadataValueSchema = z.object({
  kind: z.string().min(1).max(200),
  value: z.string().max(8_000),
  objc_type: z.string().max(100).nullable().optional(),
});

const sampleSchema = z
  .object({
    sample_id: z.string().uuid(),
    value: z.number().finite().min(0),
    unit: z.literal("count").default("count"),
    starts_at: dateTime,
    ends_at: dateTime,
    local_day: civilDay,
    time_zone: timeZone,
    source_name: z.string().min(1).max(500),
    source_bundle_identifier: z.string().min(1).max(500),
    source_version: optionalText,
    source_product_type: optionalText,
    source_os_version: optionalText,
    device_name: optionalText,
    device_manufacturer: optionalText,
    device_model: optionalText,
    device_hardware_version: optionalText,
    device_firmware_version: optionalText,
    device_software_version: optionalText,
    device_local_identifier: optionalText,
    device_udi_identifier: optionalText,
    metadata: z.record(metadataValueSchema).default({}),
    user_entered: z.boolean().nullable().optional(),
  })
  .superRefine((sample, context) => {
    if (Date.parse(sample.ends_at) < Date.parse(sample.starts_at)) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: "ends_at precedes starts_at" });
    }
    if (Object.keys(sample.metadata).length > 64) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: "metadata has too many keys" });
    }
    const metadataCharacters = Object.entries(sample.metadata).reduce(
      (total, [key, value]) => total + key.length + value.kind.length + value.value.length,
      0,
    );
    if (metadataCharacters > 16_000) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: "metadata is too large" });
    }
  });

const deletionSchema = z.object({ sample_id: z.string().uuid() });

const mergedDaySchema = z
  .object({
    day: civilDay,
    starts_at: dateTime,
    ends_at: dateTime,
    time_zone: timeZone,
    steps: z.number().int().min(0),
  })
  .refine(
    (day) => Date.parse(day.ends_at) > Date.parse(day.starts_at),
    "ends_at must follow starts_at",
  );

const sourceDaySchema = z
  .object({
    day: civilDay,
    starts_at: dateTime,
    ends_at: dateTime,
    time_zone: timeZone,
    source_name: z.string().min(1).max(500),
    source_bundle_identifier: z.string().min(1).max(500),
    steps: z.number().finite().min(0),
  })
  .refine(
    (day) => Date.parse(day.ends_at) > Date.parse(day.starts_at),
    "ends_at must follow starts_at",
  );

const syncSchema = z.object({
  time_zone: timeZone,
  accessible_from: dateTime.nullable().optional(),
  complete_through: dateTime,
});

function duplicateKey<T>(values: T[], key: (value: T) => string): string | null {
  const seen = new Set<string>();
  for (const value of values) {
    const candidate = key(value);
    if (seen.has(candidate)) {
      return candidate;
    }
    seen.add(candidate);
  }
  return null;
}

export const healthKitArchiveSchema = z
  .object({
    samples: z.array(sampleSchema).max(250).default([]),
    deletions: z.array(deletionSchema).max(500).default([]),
    merged_days: z.array(mergedDaySchema).max(45).default([]),
    source_days: z.array(sourceDaySchema).max(1_000).default([]),
    sync: syncSchema.nullable().optional(),
  })
  .superRefine((batch, context) => {
    if (
      batch.samples.length === 0 &&
      batch.deletions.length === 0 &&
      batch.merged_days.length === 0 &&
      batch.source_days.length === 0 &&
      !batch.sync
    ) {
      context.addIssue({ code: z.ZodIssueCode.custom, message: "batch is empty" });
    }

    const duplicates = [
      duplicateKey(batch.samples, (sample) => sample.sample_id),
      duplicateKey(batch.deletions, (deletion) => deletion.sample_id),
      duplicateKey(batch.merged_days, (day) => day.day),
      duplicateKey(
        batch.source_days,
        (day) => `${day.day}:${day.source_bundle_identifier}`,
      ),
    ].filter((value): value is string => value !== null);
    if (duplicates.length > 0) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: `duplicate archive key: ${duplicates[0]}`,
      });
    }
  });

export type HealthKitArchiveBatch = z.infer<typeof healthKitArchiveSchema>;

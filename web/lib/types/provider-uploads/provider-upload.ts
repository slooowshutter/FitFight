import { z } from "zod";
import { isCivilDay } from "@/lib/scoring/civil-day";

const uuidV4Schema = z.string().uuid().refine(
  (value) => value[14] === "4" && ["8", "9", "a", "b"].includes(value[19]?.toLowerCase()),
  "must be a UUID v4",
);
const dateTimeSchema = z.string().datetime({ offset: true });
const civilDaySchema = z.string().refine(isCivilDay, "must be YYYY-MM-DD");
const nullableTextSchema = z.string().max(500).nullable().optional().transform((value) => value ?? null);
const timeZoneSchema = z.string().min(1).max(100).refine((value) => {
  try {
    Intl.DateTimeFormat("en-US", { timeZone: value }).format();
    return true;
  } catch {
    return false;
  }
}, "invalid time zone");

const metadataValueSchema = z.object({
  kind: z.string().min(1).max(200),
  value: z.string().max(8_000),
  objc_type: z.string().max(100).nullable(),
}).strict();

export const createProviderUploadSchema = z.object({
  upload_id: uuidV4Schema,
  provider: z.literal("apple_health"),
  connection_route: z.literal("healthkit"),
  metric: z.literal("steps"),
  format_version: z.literal(1),
  byte_size: z.number().int().min(1),
  sha256: z.string().regex(/^[0-9a-f]{64}$/),
}).strict();

export const providerArchiveRecordSchema = z.discriminatedUnion("type", [
  z.object({
    type: z.literal("sample"),
    operation: z.enum(["add", "change"]),
    sample_id: uuidV4Schema,
    value: z.number().finite().min(0),
    unit: z.literal("count"),
    starts_at: dateTimeSchema,
    ends_at: dateTimeSchema,
    local_day: civilDaySchema,
    time_zone: timeZoneSchema,
    source_name: z.string().min(1).max(500),
    source_bundle_identifier: z.string().min(1).max(500),
    source_version: nullableTextSchema,
    source_product_type: nullableTextSchema,
    source_os_version: nullableTextSchema,
    device_name: nullableTextSchema,
    device_manufacturer: nullableTextSchema,
    device_model: nullableTextSchema,
    device_hardware_version: nullableTextSchema,
    device_firmware_version: nullableTextSchema,
    device_software_version: nullableTextSchema,
    device_local_identifier: nullableTextSchema,
    device_udi_identifier: nullableTextSchema,
    metadata: z.record(metadataValueSchema),
    user_entered: z.boolean().nullable().optional().transform((value) => value ?? null),
  }).strict(),
  z.object({
    type: z.literal("deletion"),
    operation: z.literal("delete"),
    sample_id: uuidV4Schema,
    occurred_at: dateTimeSchema,
  }).strict(),
  z.object({
    type: z.literal("merged_day"),
    day: civilDaySchema,
    starts_at: dateTimeSchema,
    ends_at: dateTimeSchema,
    time_zone: timeZoneSchema,
    steps: z.number().int().min(0),
  }).strict(),
  z.object({
    type: z.literal("source_day"),
    day: civilDaySchema,
    starts_at: dateTimeSchema,
    ends_at: dateTimeSchema,
    time_zone: timeZoneSchema,
    source_name: z.string().min(1).max(500),
    source_bundle_identifier: z.string().min(1).max(500),
    steps: z.number().finite().min(0),
  }).strict(),
  z.object({
    type: z.literal("fight_aggregate"),
    fight_id: uuidV4Schema,
    starts_at: dateTimeSchema,
    ends_at: dateTimeSchema,
    cutoff_at: dateTimeSchema,
    steps: z.number().int().min(0),
  }).strict(),
  z.object({
    type: z.literal("checkpoint"),
    time_zone: timeZoneSchema,
    accessible_from: dateTimeSchema.nullable(),
    complete_through: dateTimeSchema,
  }).strict(),
]).superRefine((value, context) => {
  if ("starts_at" in value) {
    const permitsEqual = value.type === "sample";
    if (permitsEqual
      ? Date.parse(value.ends_at) < Date.parse(value.starts_at)
      : Date.parse(value.ends_at) <= Date.parse(value.starts_at)) {
      context.addIssue({
        code: z.ZodIssueCode.custom,
        message: permitsEqual ? "ends_at precedes starts_at" : "ends_at must follow starts_at",
        path: ["ends_at"],
      });
    }
  }
  if (value.type === "fight_aggregate"
    && (Date.parse(value.cutoff_at) < Date.parse(value.starts_at)
      || Date.parse(value.cutoff_at) > Date.parse(value.ends_at))) {
    context.addIssue({
      code: z.ZodIssueCode.custom,
      message: "cutoff_at is outside the fight window",
      path: ["cutoff_at"],
    });
  }
});

export const providerUploadIdSchema = uuidV4Schema;

export type CreateProviderUpload = z.infer<typeof createProviderUploadSchema>;
export type ProviderArchiveRecord = z.infer<typeof providerArchiveRecordSchema>;

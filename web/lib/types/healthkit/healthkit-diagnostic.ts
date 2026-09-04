import { z } from "zod";

export const healthKitBackgroundRefreshStatusValues = [
  "available",
  "denied",
  "restricted",
] as const;
export const healthKitDeliveryRegistrationStatusValues = ["enabled", "unavailable"] as const;
export const healthKitSyncTriggerValues = ["observer", "foreground", "manual"] as const;
export const healthKitSyncErrorCodeValues = [
  "authentication_unavailable",
  "network_unavailable",
  "protected_data_unavailable",
  "attempt_expired",
  "healthkit_unavailable",
  "background_delivery_unavailable",
  "sync_failed",
] as const;

const optionalDateTimeSchema = z.string().datetime({ offset: true }).nullable();

export const healthKitDiagnosticSnapshotSchema = z.object({
  background_refresh_status: z.enum(healthKitBackgroundRefreshStatusValues),
  delivery_registration_status: z.enum(healthKitDeliveryRegistrationStatusValues),
  last_observer_wake: optionalDateTimeSchema,
  last_sync_attempt: optionalDateTimeSchema,
  last_automatic_sync: optionalDateTimeSchema,
  last_manual_sync: optionalDateTimeSchema,
  last_trigger_context: z.enum(healthKitSyncTriggerValues).nullable(),
  error_code: z.enum(healthKitSyncErrorCodeValues).nullable(),
  app_version: z.string().min(1).max(40),
  app_build: z.string().min(1).max(40),
}).strict();

export const healthKitDiagnosticSnapshotResponseSchema = z.object({
  updated_at: z.string().datetime({ offset: true }),
}).strict();

export type HealthKitDiagnosticSnapshot = z.infer<typeof healthKitDiagnosticSnapshotSchema>;
export type HealthKitDiagnosticSnapshotResponse = z.infer<
  typeof healthKitDiagnosticSnapshotResponseSchema
>;

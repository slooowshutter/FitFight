import assert from "node:assert/strict";
import test from "node:test";
import type { Sql } from "postgres";
import { saveHealthKitDiagnosticSnapshot } from "@/lib/supabase/queries/healthkit-diagnostics-supabase-query";
import {
  healthKitDiagnosticSnapshotResponseSchema,
  healthKitDiagnosticSnapshotSchema,
} from "@/lib/types/healthkit/healthkit-diagnostic";

const validSnapshot = {
  background_refresh_status: "available",
  delivery_registration_status: "enabled",
  last_observer_wake: "2026-09-04T08:00:00.000Z",
  last_sync_attempt: "2026-09-04T08:00:01.000Z",
  last_automatic_sync: "2026-09-04T08:00:02.000Z",
  last_manual_sync: null,
  last_trigger_context: "observer",
  error_code: null,
  app_version: "1.0.0",
  app_build: "42",
} as const;

test("HealthKit diagnostics accept only the stable snapshot vocabulary", () => {
  assert.deepEqual(healthKitDiagnosticSnapshotSchema.parse(validSnapshot), validSnapshot);
  assert.throws(() => healthKitDiagnosticSnapshotSchema.parse({
    ...validSnapshot,
    background_refresh_status: "sometimes",
  }));
  assert.throws(() => healthKitDiagnosticSnapshotSchema.parse({
    ...validSnapshot,
    free_form_error: "private device details",
  }));
});

test("HealthKit diagnostics overwrite the one row for the authenticated user", async () => {
  let queryText = "";
  const database = ((strings: TemplateStringsArray) => {
    queryText = strings.join("?");
    return Promise.resolve([{ updated_at: "2026-09-04T08:00:03.000Z" }]);
  }) as unknown as Sql;

  const result = await saveHealthKitDiagnosticSnapshot(
    "5b2216f4-762d-4890-a516-63046a01df31",
    healthKitDiagnosticSnapshotSchema.parse(validSnapshot),
    database,
  );

  assert.match(queryText, /on conflict \(user_id, connection_route\) do update/);
  assert.deepEqual(healthKitDiagnosticSnapshotResponseSchema.parse(result), result);
});

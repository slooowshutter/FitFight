import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
  HealthKitDiagnosticSnapshot,
  HealthKitDiagnosticSnapshotResponse,
} from "@/lib/types/healthkit/healthkit-diagnostic";

export async function saveHealthKitDiagnosticSnapshot(
  userId: string,
  input: HealthKitDiagnosticSnapshot,
  database: Sql = createDatabaseClient(),
): Promise<HealthKitDiagnosticSnapshotResponse> {
  const [row] = await database<{ updated_at: string }[]>`
    insert into private.healthkit_sync_diagnostics (
      user_id, connection_route, background_refresh_status,
      delivery_registration_status, last_observer_wake, last_sync_attempt,
      last_automatic_sync, last_manual_sync, last_trigger_context, error_code,
      app_version, app_build, updated_at
    ) values (
      ${userId}, 'healthkit', ${input.background_refresh_status},
      ${input.delivery_registration_status}, ${input.last_observer_wake},
      ${input.last_sync_attempt}, ${input.last_automatic_sync},
      ${input.last_manual_sync}, ${input.last_trigger_context}, ${input.error_code},
      ${input.app_version}, ${input.app_build}, clock_timestamp()
    )
    on conflict (user_id, connection_route) do update
    set background_refresh_status = excluded.background_refresh_status,
      delivery_registration_status = excluded.delivery_registration_status,
      last_observer_wake = excluded.last_observer_wake,
      last_sync_attempt = excluded.last_sync_attempt,
      last_automatic_sync = excluded.last_automatic_sync,
      last_manual_sync = excluded.last_manual_sync,
      last_trigger_context = excluded.last_trigger_context,
      error_code = excluded.error_code,
      app_version = excluded.app_version,
      app_build = excluded.app_build,
      updated_at = excluded.updated_at
    returning updated_at::text as updated_at
  `;
  if (!row) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not save HealthKit diagnostics");
  }
  return row;
}

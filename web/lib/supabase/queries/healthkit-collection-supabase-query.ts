import { createHash } from "node:crypto";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { civilDayInTimeZone } from "@/lib/scoring/civil-day";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import type {
  HealthKitCollectionSync,
  HealthKitCollectionSyncResponse,
} from "@/lib/types/healthkit/healthkit-collection";

export async function syncHealthKitCollection(
  userId: string,
  input: HealthKitCollectionSync,
  database: Sql = createDatabaseClient(),
): Promise<HealthKitCollectionSyncResponse> {
  return database.begin("read write", async (sql) => {
    const [state] = await sql<{
      complete_through: string;
      server_now: string;
    }[]>`
      insert into private.health_ingest_state (user_id, complete_through, time_zone)
      values (${userId}, ${input.complete_through}, ${input.time_zone})
      on conflict (user_id) do update
      set complete_through = excluded.complete_through,
        time_zone = excluded.time_zone,
        updated_at = now()
      where private.health_ingest_state.complete_through <= excluded.complete_through
      returning complete_through::text as complete_through,
        clock_timestamp()::text as server_now
    `;
    if (!state) {
      throw new ApiError(409, ERROR_CODES.conflict, "Sync is older than current Apple Health collection");
    }
    if (Date.parse(input.complete_through) > Date.parse(state.server_now)) {
      throw new ApiError(
        400,
        ERROR_CODES.validation,
        "complete_through cannot be in the future",
      );
    }

    const completeLocalDay = civilDayInTimeZone(
      new Date(input.complete_through),
      input.time_zone,
    );
    if (input.days.length > 0) {
      const dayRows = input.days.map((day) => ({
        user_id: userId,
        metric: day.metric,
        day: day.day,
        value: day.value,
        unit: day.unit,
        starts_at: day.starts_at,
        ends_at: day.ends_at,
        time_zone: input.time_zone,
        input_hash: createHash("sha256").update(JSON.stringify(day)).digest("hex"),
        finalized_at: day.day < completeLocalDay ? new Date(input.complete_through) : null,
      }));
      await sql`
        insert into private.health_metric_days ${sql(
          dayRows,
          "user_id",
          "metric",
          "day",
          "value",
          "unit",
          "starts_at",
          "ends_at",
          "time_zone",
          "input_hash",
          "finalized_at",
        )}
        on conflict (user_id, metric, day) do update
        set value = excluded.value,
          unit = excluded.unit,
          starts_at = excluded.starts_at,
          ends_at = excluded.ends_at,
          time_zone = excluded.time_zone,
          input_hash = excluded.input_hash,
          finalized_at = excluded.finalized_at,
          updated_at = now()
        where private.health_metric_days.finalized_at is null
      `;
    }
    if (input.sessions.length > 0) {
      const sessionRows = input.sessions.map((session) => ({
        user_id: userId,
        source_uuid: session.source_uuid,
        kind: session.kind,
        activity_type: session.activity_type,
        starts_at: session.starts_at,
        ends_at: session.ends_at,
        duration_seconds: session.duration_seconds,
        energy_kcal: session.energy_kcal ?? null,
        distance_m: session.distance_m ?? null,
        input_hash: createHash("sha256").update(JSON.stringify(session)).digest("hex"),
        finalized_at:
          civilDayInTimeZone(new Date(session.ends_at), input.time_zone) < completeLocalDay
            ? new Date(input.complete_through)
            : null,
      }));
      await sql`
        insert into private.health_sessions ${sql(
          sessionRows,
          "user_id",
          "source_uuid",
          "kind",
          "activity_type",
          "starts_at",
          "ends_at",
          "duration_seconds",
          "energy_kcal",
          "distance_m",
          "input_hash",
          "finalized_at",
        )}
        on conflict (user_id, source_uuid) do update
        set kind = excluded.kind,
          activity_type = excluded.activity_type,
          starts_at = excluded.starts_at,
          ends_at = excluded.ends_at,
          duration_seconds = excluded.duration_seconds,
          energy_kcal = excluded.energy_kcal,
          distance_m = excluded.distance_m,
          input_hash = excluded.input_hash,
          finalized_at = excluded.finalized_at,
          updated_at = now()
        where private.health_sessions.finalized_at is null
      `;
    }

    return {
      complete_through: input.complete_through,
      synced_days: input.days.length,
      synced_sessions: input.sessions.length,
    };
  });
}

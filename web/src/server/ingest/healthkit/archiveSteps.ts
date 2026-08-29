import type { Sql, TransactionSql } from "postgres";
import { createDatabaseClient } from "../../db/postgres";
import { ApiError, ERROR_CODES } from "../../http";
import { listFightsToRecalculate, recalculateFight } from "../../scoring/recalculateFight";
import type { HealthKitArchiveBatch } from "./healthKitArchiveBatch";

export type HealthKitArchiveAck = {
  samples: number;
  deletions: number;
  mergedDays: number;
  sourceDays: number;
  sourceId: string;
  recalculatedFightIds: string[];
};

export type RecalculateAffectedFights = (userId: string) => Promise<string[]>;

type SourceRow = { id: string };

const sampleColumns = [
  "user_id",
  "sample_id",
  "value",
  "unit",
  "starts_at",
  "ends_at",
  "local_day",
  "time_zone",
  "source_name",
  "source_bundle_identifier",
  "source_version",
  "source_product_type",
  "source_os_version",
  "device_name",
  "device_manufacturer",
  "device_model",
  "device_hardware_version",
  "device_firmware_version",
  "device_software_version",
  "device_local_identifier",
  "device_udi_identifier",
  "metadata",
  "user_entered",
] as const;

function contributingLabels(batch: HealthKitArchiveBatch): string[] {
  const names = [
    ...batch.samples.map((sample) => sample.source_name),
    ...batch.source_days.map((day) => day.source_name),
  ];
  return [...new Set(names.map((name) => name.trim()).filter(Boolean))].sort();
}

async function ensureSource(
  sql: TransactionSql,
  userId: string,
  batch: HealthKitArchiveBatch,
): Promise<string> {
  const labels = contributingLabels(batch);
  const completeThrough = batch.sync?.complete_through ?? null;
  const [source] = await sql<SourceRow[]>`
    insert into public.data_sources (
      user_id, provider, source_label, contributing_source_labels,
      connection_route, capabilities, status, consent_version,
      connected_at, last_success_at, complete_through
    ) values (
      ${userId}, 'apple_health', 'Apple Health', ${sql.array(labels)}::text[],
      'healthkit', array['steps']::text[], 'healthy', 1,
      now(), now(), ${completeThrough}
    )
    on conflict (user_id, provider, connection_route) do update
      set contributing_source_labels = case
            when cardinality(excluded.contributing_source_labels) > 0
              then excluded.contributing_source_labels
            else public.data_sources.contributing_source_labels
          end,
          status = 'healthy',
          revoked_at = null,
          last_success_at = now(),
          last_error_code = null,
          complete_through = case
            when excluded.complete_through is null then public.data_sources.complete_through
            when public.data_sources.complete_through is null then excluded.complete_through
            else greatest(public.data_sources.complete_through, excluded.complete_through)
          end
    returning id
  `;
  if (!source) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not save Apple Health source");
  }
  return source.id;
}

async function writeSamples(
  sql: TransactionSql,
  userId: string,
  samples: HealthKitArchiveBatch["samples"],
): Promise<void> {
  if (samples.length === 0) {
    return;
  }
  const rows = samples.map((sample) => ({
    user_id: userId,
    sample_id: sample.sample_id,
    value: sample.value,
    unit: sample.unit,
    starts_at: sample.starts_at,
    ends_at: sample.ends_at,
    local_day: sample.local_day,
    time_zone: sample.time_zone,
    source_name: sample.source_name,
    source_bundle_identifier: sample.source_bundle_identifier,
    source_version: sample.source_version ?? null,
    source_product_type: sample.source_product_type ?? null,
    source_os_version: sample.source_os_version ?? null,
    device_name: sample.device_name ?? null,
    device_manufacturer: sample.device_manufacturer ?? null,
    device_model: sample.device_model ?? null,
    device_hardware_version: sample.device_hardware_version ?? null,
    device_firmware_version: sample.device_firmware_version ?? null,
    device_software_version: sample.device_software_version ?? null,
    device_local_identifier: sample.device_local_identifier ?? null,
    device_udi_identifier: sample.device_udi_identifier ?? null,
    metadata: sql.json(sample.metadata),
    user_entered: sample.user_entered ?? null,
  }));
  await sql`
    insert into private.healthkit_step_samples ${sql(rows, ...sampleColumns)}
    on conflict (user_id, sample_id) do update
      set value = excluded.value,
          unit = excluded.unit,
          starts_at = excluded.starts_at,
          ends_at = excluded.ends_at,
          local_day = excluded.local_day,
          time_zone = excluded.time_zone,
          source_name = excluded.source_name,
          source_bundle_identifier = excluded.source_bundle_identifier,
          source_version = excluded.source_version,
          source_product_type = excluded.source_product_type,
          source_os_version = excluded.source_os_version,
          device_name = excluded.device_name,
          device_manufacturer = excluded.device_manufacturer,
          device_model = excluded.device_model,
          device_hardware_version = excluded.device_hardware_version,
          device_firmware_version = excluded.device_firmware_version,
          device_software_version = excluded.device_software_version,
          device_local_identifier = excluded.device_local_identifier,
          device_udi_identifier = excluded.device_udi_identifier,
          metadata = excluded.metadata,
          user_entered = excluded.user_entered,
          last_received_at = now()
  `;
}

async function writeDeletions(
  sql: TransactionSql,
  userId: string,
  deletions: HealthKitArchiveBatch["deletions"],
): Promise<void> {
  if (deletions.length === 0) {
    return;
  }
  const rows = deletions.map((deletion) => ({
    user_id: userId,
    sample_id: deletion.sample_id,
  }));
  await sql`
    insert into private.healthkit_step_sample_deletions ${sql(rows, "user_id", "sample_id")}
    on conflict (user_id, sample_id) do update
      set last_received_at = now()
  `;
}

async function writeDays(
  sql: TransactionSql,
  userId: string,
  sourceId: string,
  mergedDays: HealthKitArchiveBatch["merged_days"],
  sourceDays: HealthKitArchiveBatch["source_days"],
): Promise<void> {
  if (mergedDays.length > 0) {
    const days = mergedDays.map((day) => day.day);
    await sql`
      delete from private.healthkit_step_source_days
      where user_id = ${userId}
        and day = any(${sql.array(days)}::date[])
    `;

    const scoreRows = mergedDays.map((day) => ({
      user_id: userId,
      day: day.day,
      steps: day.steps,
      updated_at: new Date(),
    }));
    await sql`
      insert into public.step_days ${sql(scoreRows, "user_id", "day", "steps", "updated_at")}
      on conflict (user_id, day) do update
        set steps = excluded.steps,
            updated_at = excluded.updated_at
    `;

    const observations = mergedDays.map((day) => ({
      user_id: userId,
      source_id: sourceId,
      external_record_id: `day:${day.day}`,
      metric: "steps",
      starts_at: day.starts_at,
      ends_at: day.ends_at,
      value: day.steps,
      unit: "steps",
      revision: 1,
      provenance: sql.json({ route: "healthkit", timeZone: day.time_zone }),
      retracted_at: null,
    }));
    await sql`
      insert into private.metric_observations ${sql(
        observations,
        "user_id",
        "source_id",
        "external_record_id",
        "metric",
        "starts_at",
        "ends_at",
        "value",
        "unit",
        "revision",
        "provenance",
        "retracted_at",
      )}
      on conflict (source_id, external_record_id, revision) do update
        set starts_at = excluded.starts_at,
            ends_at = excluded.ends_at,
            value = excluded.value,
            provenance = excluded.provenance,
            retracted_at = null
    `;
  }

  if (sourceDays.length === 0) {
    return;
  }
  const rows = sourceDays.map((day) => ({
    user_id: userId,
    day: day.day,
    starts_at: day.starts_at,
    ends_at: day.ends_at,
    time_zone: day.time_zone,
    source_name: day.source_name,
    source_bundle_identifier: day.source_bundle_identifier,
    steps: day.steps,
    updated_at: new Date(),
  }));
  await sql`
    insert into private.healthkit_step_source_days ${sql(
      rows,
      "user_id",
      "day",
      "starts_at",
      "ends_at",
      "time_zone",
      "source_name",
      "source_bundle_identifier",
      "steps",
      "updated_at",
    )}
    on conflict (user_id, day, source_bundle_identifier) do update
      set starts_at = excluded.starts_at,
          ends_at = excluded.ends_at,
          time_zone = excluded.time_zone,
          source_name = excluded.source_name,
          steps = excluded.steps,
          updated_at = excluded.updated_at
  `;
}

async function writeSync(
  sql: TransactionSql,
  userId: string,
  sync: NonNullable<HealthKitArchiveBatch["sync"]> | null | undefined,
): Promise<void> {
  if (!sync) {
    return;
  }
  await sql`
    insert into private.healthkit_step_syncs (
      user_id, time_zone, accessible_from, complete_through,
      raw_sample_count, deletion_count, merged_day_count, source_day_count,
      last_success_at
    ) values (
      ${userId}, ${sync.time_zone}, ${sync.accessible_from ?? null}, ${sync.complete_through},
      (select count(*) from private.healthkit_step_samples where user_id = ${userId}),
      (select count(*) from private.healthkit_step_sample_deletions where user_id = ${userId}),
      (select count(*) from public.step_days where user_id = ${userId}),
      (select count(*) from private.healthkit_step_source_days where user_id = ${userId}),
      now()
    )
    on conflict (user_id) do update
      set time_zone = excluded.time_zone,
          accessible_from = excluded.accessible_from,
          complete_through = excluded.complete_through,
          raw_sample_count = excluded.raw_sample_count,
          deletion_count = excluded.deletion_count,
          merged_day_count = excluded.merged_day_count,
          source_day_count = excluded.source_day_count,
          last_success_at = excluded.last_success_at
  `;
}

export async function archiveHealthKitSteps(
  userId: string,
  batch: HealthKitArchiveBatch,
  database: Sql = createDatabaseClient(),
  recalculateAffectedFights: RecalculateAffectedFights = async (affectedUserId) => {
    const fightIds = await listFightsToRecalculate(affectedUserId);
    for (const fightId of fightIds) {
      await recalculateFight(fightId);
    }
    return fightIds;
  },
): Promise<HealthKitArchiveAck> {
  let sourceId: string;
  try {
    sourceId = await database.begin("read write", async (sql) => {
      const [profile] = await sql<{ user_id: string }[]>`
        select user_id from public.profiles
        where user_id = ${userId} and deleted_at is null
        for update
      `;
      if (!profile) {
        throw new ApiError(400, ERROR_CODES.profile_missing, "Profile is missing");
      }

      const id = await ensureSource(sql, userId, batch);
      await writeSamples(sql, userId, batch.samples);
      await writeDeletions(sql, userId, batch.deletions);
      await writeDays(sql, userId, id, batch.merged_days, batch.source_days);
      await writeSync(sql, userId, batch.sync);
      return id;
    });
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    console.error("healthkit_archive_failed", error instanceof Error ? error.name : "unknown");
    throw new ApiError(500, ERROR_CODES.db_error, "Could not archive HealthKit Steps");
  }

  const fightIds = batch.merged_days.length > 0
    ? await recalculateAffectedFights(userId)
    : [];

  return {
    samples: batch.samples.length,
    deletions: batch.deletions.length,
    mergedDays: batch.merged_days.length,
    sourceDays: batch.source_days.length,
    sourceId,
    recalculatedFightIds: fightIds,
  };
}

import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { readProviderArchive } from "@/lib/ingest/provider-archive";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { scoreFight } from "@/lib/scoring/score-fight";
import { asNumber, type OutcomeRule } from "@/lib/types/database";
import type {
  CreateProviderUpload,
  ProviderArchiveRecord,
} from "@/lib/types/provider-uploads/provider-upload";

const BUCKET = "provider-inbox";

export async function createProviderUpload(
  userId: string,
  input: CreateProviderUpload,
  database: Sql = createDatabaseClient(),
) {
  const objectPath = `${userId}/${input.upload_id}/archive.ndjson`;
  const rows = await database<{
    upload_id: string;
    status: string;
    object_path: string;
    expected_byte_size: string;
    expected_sha256: string;
    provider: string;
    connection_route: string;
    metric: string;
    format_version: number;
  }[]>`
    insert into private.provider_uploads (
      upload_id, user_id, provider, connection_route, metric, format_version,
      expected_byte_size, expected_sha256, object_path
    ) values (
      ${input.upload_id}, ${userId}, ${input.provider}, ${input.connection_route},
      ${input.metric}, ${input.format_version}, ${input.byte_size}, ${input.sha256}, ${objectPath}
    )
    on conflict (upload_id) do nothing
    returning upload_id, status, object_path, expected_byte_size::text,
      expected_sha256, provider, connection_route, metric, format_version
  `;
  let upload = rows[0];
  let created = true;
  if (!upload) {
    created = false;
    [upload] = await database<{
      upload_id: string;
      status: string;
      object_path: string;
      expected_byte_size: string;
      expected_sha256: string;
      provider: string;
      connection_route: string;
      metric: string;
      format_version: number;
    }[]>`
      select upload_id, status, object_path, expected_byte_size::text,
        expected_sha256, provider, connection_route, metric, format_version
      from private.provider_uploads
      where upload_id = ${input.upload_id} and user_id = ${userId}
    `;
    if (!upload
      || Number(upload.expected_byte_size) !== input.byte_size
      || upload.expected_sha256 !== input.sha256
      || upload.provider !== input.provider
      || upload.connection_route !== input.connection_route
      || upload.metric !== input.metric
      || upload.format_version !== input.format_version) {
      throw new ApiError(409, ERROR_CODES.conflict, "Upload ID is already in use");
    }
  }

  const admin = createAdminClient();
  const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(objectPath, {
    upsert: false,
  });
  if (error || !data) {
    throw new ApiError(503, ERROR_CODES.storage_error, "Could not authorize archive upload");
  }
  const projectUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!projectUrl) {
    throw new ApiError(500, ERROR_CODES.config, "Missing NEXT_PUBLIC_SUPABASE_URL");
  }
  const parsedUrl = new URL(projectUrl);
  const tusHost = parsedUrl.hostname.endsWith(".supabase.co")
    ? parsedUrl.hostname.replace(".supabase.co", ".storage.supabase.co")
    : parsedUrl.host;

  return {
    created,
    response: {
      upload_id: upload.upload_id,
      status: upload.status,
      object_path: upload.object_path,
      tus_url: `${parsedUrl.protocol}//${tusHost}/storage/v1/upload/resumable/sign`,
      tus_headers: { "x-signature": data.token, "x-upsert": "false" },
      tus_metadata: {
        bucketName: BUCKET,
        objectName: upload.object_path,
        contentType: "application/x-ndjson",
        cacheControl: "3600",
      },
    },
  };
}

export async function getProviderUpload(
  userId: string,
  uploadId: string,
  database: Sql = createDatabaseClient(),
) {
  const [upload] = await database<{
    upload_id: string;
    status: string;
    receipt: Record<string, unknown> | null;
    error_code: string | null;
  }[]>`
    select upload_id, status, receipt, error_code
    from private.provider_uploads
    where upload_id = ${uploadId} and user_id = ${userId}
  `;
  if (!upload) {
    throw new ApiError(404, ERROR_CODES.not_found, "Provider upload was not found");
  }
  return {
    upload_id: upload.upload_id,
    status: upload.status,
    ...(upload.status === "completed" && upload.receipt ? { receipt: upload.receipt } : {}),
    ...(upload.error_code ? { error_code: upload.error_code } : {}),
  };
}

export async function getProviderUploadContext(
  userId: string,
  database: Sql = createDatabaseClient(),
  now = new Date(),
) {
  const rows = await database<{
    fight_id: string;
    state: "live" | "awaiting_final_sync";
    starts_at: string;
    ends_at: string;
  }[]>`
    select fight.id as fight_id, fight.state::text as state,
      fight.starts_at::text as starts_at, fight.ends_at::text as ends_at
    from public.fights as fight
    join public.fight_members as member on member.fight_id = fight.id
    where member.user_id = ${userId}
      and member.state = 'accepted'
      and fight.state in ('live', 'awaiting_final_sync')
    order by fight.starts_at, fight.id
  `;
  return {
    server_now: now.toISOString(),
    fight_windows: rows.map((row) => ({
      ...row,
      starts_at: new Date(row.starts_at).toISOString(),
      ends_at: new Date(row.ends_at).toISOString(),
      cutoff_at: new Date(Math.min(now.getTime(), Date.parse(row.ends_at))).toISOString(),
    })),
  };
}

export async function processProviderUpload(
  userId: string,
  uploadId: string,
  database: Sql = createDatabaseClient(),
) {
  const claimed = await database.begin("read write", async (sql) => {
    const [upload] = await sql<{
      upload_id: string;
      status: string;
      object_path: string;
      expected_byte_size: string;
      expected_sha256: string;
      receipt: Record<string, unknown> | null;
      lease_expires_at: string | null;
    }[]>`
      select upload_id, status, object_path, expected_byte_size::text,
        expected_sha256, receipt, lease_expires_at::text
      from private.provider_uploads
      where upload_id = ${uploadId} and user_id = ${userId}
      for update
    `;
    if (!upload) {
      throw new ApiError(404, ERROR_CODES.not_found, "Provider upload was not found");
    }
    if (upload.status === "completed" || upload.status === "committed") {
      return upload;
    }
    if (upload.status === "rejected") {
      throw new ApiError(409, ERROR_CODES.conflict, "Provider upload was rejected");
    }
    if (upload.status === "processing"
      && upload.lease_expires_at
      && Date.parse(upload.lease_expires_at) > Date.now()) {
      throw new ApiError(409, ERROR_CODES.upload_busy, "Provider upload is processing");
    }
    await sql`
      update private.provider_uploads
      set status = 'processing', processing_started_at = now(),
        lease_expires_at = now() + interval '10 minutes', error_code = null, updated_at = now()
      where upload_id = ${uploadId}
    `;
    return { ...upload, status: "processing" };
  });

  if (claimed.status !== "committed" && claimed.status !== "completed") {
    const admin = createAdminClient();
    const { data, error } = await admin.storage.from(BUCKET).download(claimed.object_path).asStream();
    if (error || !data) {
      const missing = error?.status === 404 || error?.statusCode === "404";
      const errorCode = missing ? ERROR_CODES.archive_not_found : ERROR_CODES.storage_error;
      await database`
        update private.provider_uploads
        set status = 'retryable_failure', error_code = ${errorCode},
          lease_expires_at = null, updated_at = now()
        where upload_id = ${uploadId} and user_id = ${userId}
      `;
      throw new ApiError(
        missing ? 404 : 503,
        errorCode,
        missing ? "Archive object was not found" : "Could not download archive object",
      );
    }

    let archive: Awaited<ReturnType<typeof readProviderArchive>>;
    try {
      archive = await readProviderArchive(
        data,
        Number(claimed.expected_byte_size),
        claimed.expected_sha256,
      );
    } catch (error) {
      const code = error instanceof ApiError ? error.code : ERROR_CODES.archive_invalid;
      await database`
        update private.provider_uploads
        set status = 'rejected', error_code = ${code}, lease_expires_at = null, updated_at = now()
        where upload_id = ${uploadId} and user_id = ${userId}
      `;
      throw error;
    }

    try {
      const { data: eventStream, error: eventStreamError } = await admin.storage
        .from(BUCKET)
        .download(claimed.object_path)
        .asStream();
      if (eventStreamError || !eventStream) {
        throw new ApiError(503, ERROR_CODES.storage_error, "Could not reread archive object");
      }

      await database.begin("read write", async (sql) => {
      const [locked] = await sql<{ status: string }[]>`
        select status from private.provider_uploads
        where upload_id = ${uploadId} and user_id = ${userId}
        for update
      `;
      if (locked?.status === "committed" || locked?.status === "completed") {
        return;
      }
      if (locked?.status !== "processing") {
        throw new ApiError(409, ERROR_CODES.conflict, "Provider upload state changed");
      }

      const [source] = await sql<{ id: string }[]>`
        insert into public.data_sources (
          user_id, provider, source_label, connection_route, capabilities,
          status, consent_version, connected_at, last_success_at
        ) values (
          ${userId}, 'apple_health', 'Apple Health', 'healthkit', array['steps']::text[],
          'healthy', 1, now(), now()
        )
        on conflict (user_id, provider, connection_route) do update
          set status = 'healthy', revoked_at = null, last_success_at = now(), last_error_code = null
        returning id
      `;
      if (!source) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not save Apple Health source");
      }

      const mergedDays = archive.records.filter((item) => item.record.type === "merged_day");
      const sourceDays = archive.records.filter((item) => item.record.type === "source_day");
      const fightAggregates = archive.records.filter((item) => item.record.type === "fight_aggregate");
      const checkpoint = archive.records.find((item) => item.record.type === "checkpoint");
      if (!checkpoint || checkpoint.record.type !== "checkpoint") {
        throw new ApiError(400, ERROR_CODES.archive_invalid, "Archive checkpoint is missing");
      }

      const eventBatch: Array<{
        record: Extract<ProviderArchiveRecord, { type: "sample" | "deletion" }>;
        inputHash: string;
      }> = [];
      const flushEvents = async () => {
        if (eventBatch.length === 0) return;
        const sampleIds = eventBatch.flatMap((item) =>
          item.record.type === "sample" ? [item.record.sample_id] : []
        );
        const previousSamples = sampleIds.length === 0 ? [] : await sql<{
          external_record_id: string;
          payload_hash: string;
          event_kind: "add" | "change";
        }[]>`
          select external_record_id, payload_hash, event_kind
          from private.provider_events
          where user_id = ${userId} and source_id = ${source.id}
            and external_record_id = any(${sql.array(sampleIds)}::text[])
            and event_kind in ('add', 'change')
        `;
        const changedSampleIds = new Set(previousSamples.map((row) => row.external_record_id));
        const replayKinds = new Map(previousSamples.map((row) => [
          `${row.external_record_id}:${row.payload_hash}`,
          row.event_kind,
        ]));
        const rows = eventBatch.map((item) => {
          const record = item.record;
          return {
            upload_id: uploadId,
            user_id: userId,
            source_id: source.id,
            event_kind: record.type === "sample"
              ? replayKinds.get(`${record.sample_id}:${item.inputHash}`)
                ?? (changedSampleIds.has(record.sample_id) ? "change" : "add")
              : "delete",
            external_record_id: record.sample_id,
            payload_hash: item.inputHash,
            payload: sql.json(record),
            occurred_at: record.type === "deletion" ? record.occurred_at : record.ends_at,
          };
        });
        await sql`
          insert into private.provider_events ${sql(
            rows, "upload_id", "user_id", "source_id", "event_kind",
            "external_record_id", "payload_hash", "payload", "occurred_at",
          )}
          on conflict (user_id, source_id, event_kind, external_record_id, payload_hash) do nothing
        `;
        eventBatch.length = 0;
      };
      await readProviderArchive(
        eventStream,
        Number(claimed.expected_byte_size),
        claimed.expected_sha256,
        async (item) => {
          eventBatch.push(item);
          if (eventBatch.length >= 500) {
            await flushEvents();
          }
        },
      );
      await flushEvents();

      const completeLocalDay = new Intl.DateTimeFormat("en-CA", {
        timeZone: checkpoint.record.time_zone,
        year: "numeric",
        month: "2-digit",
        day: "2-digit",
      }).format(new Date(checkpoint.record.complete_through));
      for (const item of mergedDays) {
        if (item.record.type !== "merged_day") continue;
        const finalized = item.record.day < completeLocalDay;
        await sql`
          insert into private.metric_observations (
            user_id, source_id, upload_id, external_record_id, metric, starts_at, ends_at,
            value, unit, revision, provenance, scope, civil_day, cutoff_at, input_hash,
            normalization_version, calculation_version
          ) values (
            ${userId}, ${source.id}, ${uploadId}, ${`day:${item.record.day}:${item.inputHash}`},
            'steps', ${item.record.starts_at}, ${item.record.ends_at}, ${item.record.steps}, 'steps', 1,
            ${sql.json({ route: "healthkit", timeZone: item.record.time_zone })}, 'civil_day',
            ${item.record.day}, ${item.record.ends_at}, ${item.inputHash}, 1, 1
          ) on conflict (source_id, external_record_id, revision) do nothing
        `;
        await sql`
          insert into public.metric_days (
            user_id, source_id, metric, day, value, unit, input_hash,
            normalization_version, calculation_version, finalized_at
          ) values (
            ${userId}, ${source.id}, 'steps', ${item.record.day}, ${item.record.steps}, 'steps',
            ${item.inputHash}, 1, 1, ${finalized ? new Date() : null}
          ) on conflict (user_id, source_id, metric, day) do update
          set value = excluded.value, input_hash = excluded.input_hash,
            normalization_version = excluded.normalization_version,
            calculation_version = excluded.calculation_version,
            finalized_at = case
              when public.metric_days.finalized_at is not null then public.metric_days.finalized_at
              else excluded.finalized_at
            end,
            updated_at = now()
          where public.metric_days.finalized_at is null
        `;
        await sql`
          insert into public.step_days (user_id, day, steps, updated_at)
          select user_id, day, value, updated_at
          from public.metric_days
          where user_id = ${userId} and source_id = ${source.id}
            and metric = 'steps' and day = ${item.record.day}
          on conflict (user_id, day) do update
            set steps = excluded.steps, updated_at = excluded.updated_at
        `;
      }

      for (const item of sourceDays) {
        if (item.record.type !== "source_day") continue;
        await sql`
          insert into private.provider_events (
            upload_id, user_id, source_id, event_kind, external_record_id,
            payload_hash, payload, occurred_at
          ) values (
            ${uploadId}, ${userId}, ${source.id}, 'add',
            ${`source-day:${item.record.day}:${item.record.source_bundle_identifier}`},
            ${item.inputHash}, ${sql.json(item.record)}, ${item.record.ends_at}
          ) on conflict (user_id, source_id, event_kind, external_record_id, payload_hash) do nothing
        `;
      }

      for (const item of fightAggregates) {
        if (item.record.type !== "fight_aggregate") continue;
        const [fight] = await sql<{
          outcome_rule: OutcomeRule;
          stake_minor: number | null;
          default_goal_value: string | null;
        }[]>`
          select fight.outcome_rule::text as outcome_rule, fight.stake_minor,
            fight.default_goal_value::text as default_goal_value
          from public.fights as fight
          join public.fight_members as member on member.fight_id = fight.id
          where fight.id = ${item.record.fight_id} and member.user_id = ${userId}
            and member.state = 'accepted'
            and fight.starts_at = ${item.record.starts_at}
            and fight.ends_at = ${item.record.ends_at}
            and fight.state in ('live', 'awaiting_final_sync')
          for update of fight
        `;
        if (!fight) {
          throw new ApiError(400, ERROR_CODES.archive_invalid, "Fight aggregate does not match context");
        }
        await sql`
          insert into private.metric_observations (
            user_id, source_id, upload_id, external_record_id, metric, starts_at, ends_at,
            value, unit, revision, provenance, scope, cutoff_at, input_hash,
            normalization_version, calculation_version
          ) values (
            ${userId}, ${source.id}, ${uploadId},
            ${`fight:${item.record.fight_id}:${item.record.cutoff_at}:${item.inputHash}`},
            'steps', ${item.record.starts_at}, ${item.record.cutoff_at}, ${item.record.steps}, 'steps', 1,
            ${sql.json({ route: "healthkit", fightId: item.record.fight_id })}, 'fight_window',
            ${item.record.cutoff_at}, ${item.inputHash}, 1, 1
          ) on conflict (source_id, external_record_id, revision) do nothing
        `;
        await sql`
          insert into private.fight_score_snapshots (
            fight_id, user_id, source_id, upload_id, cutoff_at, value,
            input_hash, calculation_version, is_final
          ) values (
            ${item.record.fight_id}, ${userId}, ${source.id}, ${uploadId},
            ${item.record.cutoff_at}, ${item.record.steps}, ${item.inputHash}, 1,
            false
          ) on conflict (fight_id, user_id, cutoff_at, input_hash) do nothing
        `;
        await sql`
          update public.fight_members
          set current_value = ${item.record.steps}, freshness = 'recent',
            last_synced_at = now(),
            input_revision = coalesce(input_revision, 0) + 1
          where fight_id = ${item.record.fight_id}
            and user_id = ${userId}
            and finalized_at is null
        `;
        const members = await sql<{
          user_id: string;
          current_value: string | null;
          final_value: string | null;
          personal_target: string | null;
        }[]>`
          select user_id, current_value::text, final_value::text, personal_target::text
          from public.fight_members
          where fight_id = ${item.record.fight_id} and state = 'accepted'
          for update
        `;
        const scores = scoreFight({
          outcomeRule: fight.outcome_rule,
          stakeMinor: fight.stake_minor,
          defaultGoalValue: asNumber(fight.default_goal_value),
          members: members.map((member) => ({
            userId: member.user_id,
            value: asNumber(member.current_value) ?? asNumber(member.final_value) ?? 0,
            personalTarget: asNumber(member.personal_target),
          })),
        });
        for (const score of scores) {
          await sql`
            update public.fight_members
            set rank = ${score.rank}, outcome_minor = ${score.outcomeMinor}
            where fight_id = ${item.record.fight_id}
              and user_id = ${score.userId}
              and finalized_at is null
          `;
        }
      }

      const receipt = {
        upload_id: uploadId,
        samples: archive.sampleCount,
        deletions: archive.deletionCount,
        merged_days: mergedDays.length,
        source_days: sourceDays.length,
        fight_aggregates: fightAggregates.length,
      };
      await sql`
        update public.data_sources
        set complete_through = case
          when complete_through is null then ${checkpoint.record.complete_through}
          else greatest(complete_through, ${checkpoint.record.complete_through})
        end,
        last_success_at = now(), status = 'healthy'
        where id = ${source.id}
      `;
      await sql`
        update private.provider_uploads
        set source_id = ${source.id}, actual_byte_size = ${archive.actualBytes},
          actual_sha256 = ${archive.actualSha256}, status = 'committed',
          receipt = ${sql.json(receipt)}, committed_at = now(), lease_expires_at = null,
          error_code = null, updated_at = now()
        where upload_id = ${uploadId}
      `;
      });
    } catch (error) {
      const rejected = error instanceof ApiError && error.status < 500;
      const errorCode = error instanceof ApiError ? error.code : ERROR_CODES.db_error;
      await database`
        update private.provider_uploads
        set status = ${rejected ? "rejected" : "retryable_failure"}, error_code = ${errorCode},
          lease_expires_at = null, updated_at = now()
        where upload_id = ${uploadId} and user_id = ${userId}
          and status = 'processing'
      `;
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError(500, ERROR_CODES.db_error, "Could not process provider archive");
    }
  }

  const admin = createAdminClient();
  const { error: cleanupError } = await admin.storage.from(BUCKET).remove([claimed.object_path]);
  if (cleanupError && cleanupError.status !== 404 && cleanupError.statusCode !== "404") {
    return { response: await getProviderUpload(userId, uploadId, database), cleanupPending: true };
  }
  await database`
    update private.provider_uploads
    set status = 'completed', completed_at = now(),
      receipt = receipt || jsonb_build_object('completed_at', now()), updated_at = now()
    where upload_id = ${uploadId} and user_id = ${userId} and status = 'committed'
  `;
  return { response: await getProviderUpload(userId, uploadId, database), cleanupPending: false };
}

export async function removeProviderInboxObjects(
  userId: string,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  const rows = await database<{ object_path: string }[]>`
    select object_path from private.provider_uploads where user_id = ${userId}
  `;
  const admin = createAdminClient();
  const paths = rows.map((entry) => entry.object_path);
  if (paths.length > 0) {
    const { error: removeError } = await admin.storage.from(BUCKET).remove(paths);
    if (removeError && removeError.status !== 404 && removeError.statusCode !== "404") {
      throw new ApiError(503, ERROR_CODES.storage_error, "Could not remove pending provider archives");
    }
  }
}

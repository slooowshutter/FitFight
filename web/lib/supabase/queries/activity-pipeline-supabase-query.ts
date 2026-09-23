import { createHash } from "node:crypto";
import type { Sql, TransactionSql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import {
    ACTIVITY_RESOLVER_VERSION,
    measurementFromRaw,
    workoutDayMeasurements,
    workoutDayMetricValues,
} from "@/lib/domain/activity/activity-measurements";
import { scoreFight } from "@/lib/scoring/score-fight";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    activityMeasurementSchema,
    claimedActivityRawSchema,
    fightTotalPayloadSchema,
    selectedActivityRawSchema,
    type ActivityMeasurement,
    type ActivityRawRecord,
    type ClaimedActivityRaw,
    type JsonValue,
    type SelectedActivityRaw,
} from "@/lib/types/activity/activity-pipeline";
import {
    healthKitTotalMetricValues,
    type ActivityProcessing,
    type HealthKitActivityBatch,
    type HealthKitActivityBatchResponse,
} from "@/lib/types/healthkit/healthkit-activity-batch";
import {
    healthKitAggregateFightSchema,
    healthKitAggregateMemberSchema,
} from "@/lib/types/healthkit/healthkit-aggregate-database";
import { skipGraceNotificationsForMember } from "./notification-intents-supabase-query";

const MAX_PROCESSING_ATTEMPTS = 5;

/**
 * Durable intake. Identical content from a retry or a second device is one row. A newer re-read of
 * that content returns it to pending, so a total that goes A, B, then A again selects A.
 */
export async function insertActivityRaw(
    sql: Sql | TransactionSql,
    userId: string,
    sourceId: string,
    collectedAt: string,
    records: ActivityRawRecord[],
): Promise<number> {
    if (records.length === 0) {
        return 0;
    }
    const rows = records.map((record) => ({
        ...record,
        payload_hash: createHash("sha256")
            .update(JSON.stringify(record.payload))
            .digest("hex"),
    }));
    await sql`
        insert into private.activity_raw (
            user_id, source_id, record_kind, record_type, record_key, starts_at, ends_at,
            time_zone, payload, payload_hash, collected_at
        )
        select ${userId}, ${sourceId}, record.record_kind, record.record_type, record.record_key,
            record.starts_at, record.ends_at, record.time_zone, record.payload, record.payload_hash,
            ${collectedAt}
        from jsonb_to_recordset(${sql.json(rows)}::jsonb) as record (
            record_kind text, record_type text, record_key text, starts_at timestamptz,
            ends_at timestamptz, time_zone text, payload jsonb, payload_hash text
        )
        on conflict (source_id, record_kind, record_type, record_key, payload_hash) do update
        set collected_at = excluded.collected_at,
            processing_state = 'pending',
            processing_attempts = 0,
            processing_error = null,
            lease_expires_at = null
        where private.activity_raw.collected_at < excluded.collected_at
    `;
    return records.length;
}

export async function receiveHealthKitActivity(
    userId: string,
    input: HealthKitActivityBatch,
    database: Sql = createDatabaseClient(),
): Promise<HealthKitActivityBatchResponse> {
    const received = await database.begin("read write", async (sql) => {
        const [source] = await sql<{ id: string; server_now: string }[]>`
            insert into public.data_sources (
                user_id, provider, source_label, connection_route, capabilities,
                status, consent_version, connected_at, last_success_at
            ) values (
                ${userId}, 'apple_health', 'Apple Health', 'healthkit',
                ${sql.array([...healthKitTotalMetricValues, ...workoutDayMetricValues])}::text[],
                'healthy', 1, now(), now()
            )
            on conflict (user_id, provider, connection_route) do update
            set status = 'healthy', revoked_at = null, last_success_at = now(),
                last_error_code = null
            returning id, clock_timestamp()::text as server_now
        `;
        // NOTE: the phone stamps collection with the API server clock; allow small skew from Postgres.
        if (
            Date.parse(input.collected_at) >
            Date.parse(source.server_now) + 60_000
        ) {
            throw new ApiError(
                400,
                ERROR_CODES.validation,
                "collected_at cannot be in the future",
            );
        }
        return insertActivityRaw(sql, userId, source.id, input.collected_at, [
            ...input.totals.map((total) => ({
                record_kind: "total" as const,
                record_type: total.metric,
                record_key: `day:${total.day}`,
                starts_at: total.starts_at,
                ends_at: total.ends_at,
                time_zone: input.time_zone,
                payload: {
                    metric: total.metric,
                    day: total.day,
                    starts_at: new Date(total.starts_at).toISOString(),
                    ends_at: new Date(total.ends_at).toISOString(),
                    time_zone: input.time_zone,
                    value: total.value,
                    unit: total.unit,
                },
            })),
            ...input.workouts.map((workout) => ({
                record_kind: "workout" as const,
                record_type: "workout",
                record_key: workout.healthkit_uuid,
                starts_at: workout.started_at,
                ends_at: workout.ended_at,
                time_zone: input.time_zone,
                payload: workoutPayload(workout),
            })),
            ...input.deleted_workouts.map((id) => ({
                record_kind: "deletion" as const,
                record_type: "workout",
                record_key: id,
                starts_at: null,
                ends_at: null,
                time_zone: input.time_zone,
                payload: { healthkit_uuid: id },
            })),
        ]);
    });
    return { received, processing: await processActivity({ userId }, database) };
}

/** Normalized workout content, so the same workout hashes equally from every client. */
export function workoutPayload(
    workout: HealthKitActivityBatch["workouts"][number],
): Record<string, JsonValue> {
    return {
        healthkit_uuid: workout.healthkit_uuid,
        started_at: new Date(workout.started_at).toISOString(),
        ended_at: new Date(workout.ended_at).toISOString(),
        activity_type: workout.activity_type,
        duration_seconds: workout.duration_seconds,
        active_minutes: workout.active_minutes ?? null,
        distance_m: workout.distance_m ?? null,
        energy_kcal: workout.energy_kcal ?? null,
        effort: workout.effort ?? null,
    };
}

/**
 * Resolve received activity in bounded batches. Claimed rows carry a lease, so work interrupted by a
 * crash or timeout is claimed again later. Fight totals resolve in their own transaction first, so
 * a failure in other activity never blocks standings.
 */
export async function processActivity(
    options: { userId?: string; limit?: number; budgetMs?: number } = {},
    database: Sql = createDatabaseClient(),
): Promise<ActivityProcessing> {
    const limit = options.limit ?? 5_000;
    const startedAt = Date.now();
    const userId = options.userId ?? null;
    let failed = false;
    for (;;) {
        const claimed = claimedActivityRawSchema.array().parse(
            await database`
                update private.activity_raw as raw
                set processing_state = 'processing',
                    processing_attempts = raw.processing_attempts + 1,
                    lease_expires_at = now() + interval '5 minutes'
                where raw.id in (
                    select candidate.id
                    from private.activity_raw as candidate
                    where candidate.processing_state <> 'processed'
                        and (candidate.processing_state <> 'processing'
                            or candidate.lease_expires_at < now())
                        and (candidate.processing_state <> 'failed'
                            or candidate.processing_attempts < ${MAX_PROCESSING_ATTEMPTS})
                        and (${userId}::uuid is null or candidate.user_id = ${userId}::uuid)
                    order by candidate.received_at, candidate.id
                    limit ${limit}
                    for update skip locked
                )
                returning raw.id, raw.user_id, raw.source_id, raw.record_kind,
                    raw.record_type, raw.record_key
            `,
        );
        const bySource = new Map<string, ClaimedActivityRaw[]>();
        for (const row of claimed) {
            bySource.set(row.source_id, [
                ...(bySource.get(row.source_id) ?? []),
                row,
            ]);
        }
        for (const rows of bySource.values()) {
            const fights = rows.filter((row) =>
                row.record_key.startsWith("fight:"),
            );
            const others = rows.filter(
                (row) => !row.record_key.startsWith("fight:"),
            );
            for (const group of [fights, others]) {
                if (group.length === 0) {
                    continue;
                }
                try {
                    await database.begin("read write", (sql) =>
                        resolveActivity(sql, group),
                    );
                } catch (error) {
                    failed = true;
                    console.error(
                        "fitfight_activity_processing_failed",
                        error instanceof Error ? error.name : "unknown",
                    );
                    await database`
                        update private.activity_raw
                        set processing_state = 'failed',
                            processing_error = ${error instanceof Error ? error.message.slice(0, 500) : "unknown"},
                            lease_expires_at = null
                        where id = any(${database.array(group.map((row) => row.id))}::uuid[])
                            and processing_state = 'processing'
                    `;
                }
            }
        }
        if (
            claimed.length < limit ||
            Date.now() - startedAt >= (options.budgetMs ?? 0)
        ) {
            break;
        }
    }
    if (failed || userId === null) {
        return failed ? "pending" : "processed";
    }
    const [remaining] = await database<{ count: number }[]>`
        select count(*)::integer as count
        from private.activity_raw
        where user_id = ${userId}
            and processing_state <> 'processed'
    `;
    return remaining.count === 0 ? "processed" : "pending";
}

async function resolveActivity(
    sql: TransactionSql,
    claimed: ClaimedActivityRaw[],
): Promise<void> {
    const { user_id: userId, source_id: sourceId } = claimed[0];
    // One resolver per source at a time: a later-committed stale choice cannot overwrite a newer one.
    await sql`select pg_advisory_xact_lock(hashtextextended(${`fitfight_activity:${sourceId}`}, 0))`;
    const identities = [
        ...new Map(
            claimed.map((row) => [
                `${row.record_type}\n${row.record_key}`,
                row,
            ]),
        ).values(),
    ];
    // A deletion outranks every version (HealthKit never reuses a UUID, so no replay resurrects it).
    // Otherwise the reading that covers the most time wins, then the newest collection.
    const selected = selectedActivityRawSchema.array().parse(
        await sql`
            select distinct on (raw.record_type, raw.record_key)
                raw.id, raw.record_kind, raw.record_type, raw.record_key, raw.time_zone,
                raw.payload, raw.payload_hash, raw.collected_at::text as collected_at
            from private.activity_raw as raw
            join unnest(
                ${sql.array(identities.map((row) => row.record_type))}::text[],
                ${sql.array(identities.map((row) => row.record_key))}::text[]
            ) as wanted (record_type, record_key)
                on wanted.record_type = raw.record_type and wanted.record_key = raw.record_key
            where raw.source_id = ${sourceId}
            order by raw.record_type, raw.record_key, (raw.record_kind = 'deletion') desc,
                raw.ends_at desc nulls last, raw.collected_at desc, raw.received_at desc, raw.id desc
        `,
    );
    const measurements = selected
        .map(measurementFromRaw)
        .filter((measurement) => measurement !== null);
    const workoutKeys = selected
        .filter((raw) => raw.record_type === "workout")
        .map((raw) => raw.record_key);
    const previousWorkoutDays = workoutKeys.length
        ? (
              await sql<{ day: string }[]>`
                  select day::text as day from private.activity_metrics
                  where source_id = ${sourceId} and scope = 'workout'
                      and scope_key = any(${sql.array(workoutKeys)}::text[])
              `
          ).map((row) => row.day)
        : [];

    await saveMeasurements(sql, userId, sourceId, measurements);
    const deletedKeys = selected
        .filter((raw) => raw.record_kind === "deletion")
        .map((raw) => raw.record_key);
    if (deletedKeys.length > 0) {
        await sql`
            delete from private.activity_metrics
            where source_id = ${sourceId} and scope = 'workout'
                and scope_key = any(${sql.array(deletedKeys)}::text[])
        `;
    }
    const workoutDays = [
        ...new Set([
            ...previousWorkoutDays,
            ...measurements
                .filter((measurement) => measurement.scope === "workout")
                .map((measurement) => measurement.day as string),
        ]),
    ];
    if (workoutDays.length > 0) {
        const dayWorkouts = activityMeasurementSchema.array().parse(
            await sql`
                select scope, scope_key, metric, starts_at::text, ends_at::text,
                    observed_through::text, day::text, time_zone, fight_id, value::float8 as value,
                    unit, details, input_ids::text[] as input_ids
                from private.activity_metrics
                where source_id = ${sourceId} and scope = 'workout'
                    and day = any(${sql.array(workoutDays)}::date[])
                order by starts_at, scope_key
            `,
        );
        const derived = workoutDayMeasurements(dayWorkouts, new Date());
        await sql`
            delete from private.activity_metrics
            where source_id = ${sourceId} and scope = 'day'
                and metric = any(${sql.array([...workoutDayMetricValues])}::text[])
                and day = any(${sql.array(workoutDays)}::date[])
                and not ((metric, scope_key) in (
                    select * from unnest(
                        ${sql.array(derived.map((measurement) => measurement.metric))}::text[],
                        ${sql.array(derived.map((measurement) => measurement.scope_key))}::text[]
                    )
                ))
        `;
        await saveMeasurements(sql, userId, sourceId, derived);
    }

    const fightReadings = selected.filter((raw) =>
        raw.record_key.startsWith("fight:"),
    );
    if (fightReadings.length > 0) {
        await publishFightScores(sql, userId, sourceId, fightReadings);
    }
    await mirrorLegacyStepDays(sql, userId, sourceId, selected);

    await sql`
        update private.activity_raw
        set processing_state = 'processed',
            processing_version = ${ACTIVITY_RESOLVER_VERSION},
            processing_error = null,
            lease_expires_at = null,
            processed_at = now()
        where id = any(${sql.array(claimed.map((row) => row.id))}::uuid[])
            and processing_state = 'processing'
    `;
}

async function saveMeasurements(
    sql: TransactionSql,
    userId: string,
    sourceId: string,
    measurements: ActivityMeasurement[],
): Promise<void> {
    if (measurements.length === 0) {
        return;
    }
    await sql`
        insert into private.activity_metrics (
            user_id, source_id, scope, scope_key, metric, starts_at, ends_at, observed_through,
            day, time_zone, fight_id, value, unit, details, input_ids, calculation_version
        )
        select ${userId}, ${sourceId}, measurement.scope, measurement.scope_key,
            measurement.metric, measurement.starts_at, measurement.ends_at,
            measurement.observed_through, measurement.day, measurement.time_zone,
            measurement.fight_id, measurement.value, measurement.unit, measurement.details,
            measurement.input_ids, ${ACTIVITY_RESOLVER_VERSION}
        from jsonb_to_recordset(${sql.json(measurements)}::jsonb) as measurement (
            scope text, scope_key text, metric text, starts_at timestamptz, ends_at timestamptz,
            observed_through timestamptz, day date, time_zone text, fight_id uuid, value numeric,
            unit text, details jsonb, input_ids uuid[]
        )
        on conflict (source_id, scope, scope_key, metric) do update
        set starts_at = excluded.starts_at,
            ends_at = excluded.ends_at,
            observed_through = excluded.observed_through,
            day = excluded.day,
            time_zone = excluded.time_zone,
            fight_id = excluded.fight_id,
            value = excluded.value,
            unit = excluded.unit,
            details = excluded.details,
            input_ids = excluded.input_ids,
            calculation_version = excluded.calculation_version
        where (
            private.activity_metrics.starts_at, private.activity_metrics.ends_at,
            private.activity_metrics.observed_through, private.activity_metrics.day,
            private.activity_metrics.time_zone, private.activity_metrics.value,
            private.activity_metrics.unit, private.activity_metrics.details,
            private.activity_metrics.input_ids, private.activity_metrics.calculation_version
        ) is distinct from (
            excluded.starts_at, excluded.ends_at, excluded.observed_through, excluded.day,
            excluded.time_zone, excluded.value, excluded.unit, excluded.details,
            excluded.input_ids, excluded.calculation_version
        )
    `;
}

/**
 * Publish the selected exact-window reading as the member's newest score revision, then rescore.
 * Final or changed Fights are skipped: their frozen result follows the finalization policy.
 */
async function publishFightScores(
    sql: TransactionSql,
    userId: string,
    sourceId: string,
    readings: SelectedActivityRaw[],
): Promise<void> {
    const totals = readings.map((raw) => ({
        raw,
        total: fightTotalPayloadSchema.parse(raw.payload),
    }));
    const fights = healthKitAggregateFightSchema.array().parse(
        await sql`
            select fight.id as fight_id, fight.starts_at::text as starts_at,
                fight.ends_at::text as ends_at, fight.time_zone,
                fight.outcome_rule::text as outcome_rule,
                fight.stake_minor,
                fight.default_goal_value::text as default_goal_value
            from public.fights as fight
            join public.fight_members as member on member.fight_id = fight.id
            where member.user_id = ${userId}
                and member.state = 'accepted'
                and member.finalized_at is null
                and fight.state in ('live', 'awaiting_final_sync')
                and fight.id = any(${sql.array(totals.map(({ total }) => total.fight_id))}::uuid[])
            order by fight.id
            for update of fight, member
        `,
    );
    const snapshots = totals.flatMap(({ raw, total }) => {
        const fight = fights.find((row) => row.fight_id === total.fight_id);
        if (
            !fight ||
            Date.parse(fight.starts_at) !== Date.parse(total.starts_at) ||
            Date.parse(fight.ends_at) !== Date.parse(total.ends_at)
        ) {
            return [];
        }
        return [
            {
                fight_id: total.fight_id,
                cutoff_at: total.cutoff_at,
                value: total.steps,
                step_checkpoints: total.step_checkpoints,
                // A later re-read that returns to an earlier total becomes the newest revision again.
                input_hash: createHash("sha256")
                    .update(`${raw.payload_hash}:${raw.collected_at}`)
                    .digest("hex"),
                final_steps_complete:
                    Date.parse(total.cutoff_at) >= Date.parse(fight.ends_at),
            },
        ];
    });
    if (snapshots.length === 0) {
        return;
    }
    const fightIds = snapshots.map((snapshot) => snapshot.fight_id);
    await sql`
        insert into private.fight_score_snapshots (
            fight_id, user_id, source_id, cutoff_at, value,
            input_hash, calculation_version, is_final, created_at, step_checkpoints
        )
        select snapshot.fight_id, ${userId}, ${sourceId}, snapshot.cutoff_at,
            snapshot.value, snapshot.input_hash, 1, false, clock_timestamp(), snapshot.step_checkpoints
        from jsonb_to_recordset(${sql.json(snapshots)}::jsonb) as snapshot (
            fight_id uuid, cutoff_at timestamptz, value numeric, input_hash text, step_checkpoints jsonb
        )
        on conflict (fight_id, user_id, cutoff_at, input_hash) do nothing
    `;
    // A separate statement sees the inserted snapshots, including replayed/corrected totals.
    await sql`
        with latest as (
            select distinct on (fight_id) fight_id, value
            from private.fight_score_snapshots
            where fight_id = any(${sql.array(fightIds)}::uuid[])
                and user_id = ${userId}
                and source_id = ${sourceId}
            order by fight_id, cutoff_at desc, created_at desc, id desc
        )
        update public.fight_members as member
        set current_value = latest.value,
            selected_source_id = ${sourceId},
            source_label = 'Apple Health',
            freshness = 'recent',
            last_synced_at = now(),
            final_steps_complete = member.final_steps_complete or snapshot.final_steps_complete,
            input_revision = case
                when member.current_value is distinct from latest.value
                    or member.selected_source_id is distinct from ${sourceId}
                    or member.source_label is distinct from 'Apple Health'
                    or member.freshness is distinct from 'recent'
                then coalesce(member.input_revision, 0) + 1
                else member.input_revision
            end
        from latest
        join jsonb_to_recordset(${sql.json(snapshots)}::jsonb) as snapshot (
            fight_id uuid, final_steps_complete boolean
        ) on snapshot.fight_id = latest.fight_id
        where member.fight_id = latest.fight_id
            and member.user_id = ${userId}
            and member.state = 'accepted'
            and member.finalized_at is null
    `;
    for (const snapshot of snapshots) {
        if (snapshot.final_steps_complete) {
            await skipGraceNotificationsForMember(sql, snapshot.fight_id, userId);
        }
    }
    const members = healthKitAggregateMemberSchema.array().parse(
        await sql`
            select fight_id, user_id, current_value::text, final_value::text, personal_target::text
            from public.fight_members
            where fight_id = any(${sql.array(fightIds)}::uuid[]) and state = 'accepted'
            order by fight_id, user_id
            for update
        `,
    );
    const scores = fights
        .filter((fight) => fightIds.includes(fight.fight_id))
        .flatMap((fight) =>
            scoreFight({
                outcomeRule: fight.outcome_rule,
                stakeMinor: fight.stake_minor,
                defaultGoalValue: fight.default_goal_value,
                members: members
                    .filter((member) => member.fight_id === fight.fight_id)
                    .map((member) => ({
                        userId: member.user_id,
                        value: member.current_value ?? member.final_value ?? 0,
                        personalTarget: member.personal_target,
                    })),
            }).map((score) => ({
                fight_id: fight.fight_id,
                user_id: score.userId,
                rank: score.rank,
                outcome_minor: score.outcomeMinor,
            })),
        );
    if (scores.length > 0) {
        await sql`
            update public.fight_members as member
            set rank = score.rank, outcome_minor = score.outcome_minor
            from jsonb_to_recordset(${sql.json(scores)}::jsonb) as score (
                fight_id uuid, user_id uuid, rank integer, outcome_minor integer
            )
            where member.fight_id = score.fight_id
                and member.user_id = score.user_id
                and member.finalized_at is null
        `;
    }
}

/**
 * Installed builds before the checkpoint charts read calendar Steps for Fight days from step_days.
 * Keep that mirror, including its day freeze, for Steps days inside the user's open Fights.
 */
async function mirrorLegacyStepDays(
    sql: TransactionSql,
    userId: string,
    sourceId: string,
    selected: SelectedActivityRaw[],
): Promise<void> {
    const days = selected.flatMap((raw) => {
        const measurement =
            raw.record_type === "steps" && raw.record_key.startsWith("day:")
                ? measurementFromRaw(raw)
                : null;
        return measurement?.time_zone
            ? [
                  {
                      day: measurement.day,
                      time_zone: measurement.time_zone,
                      starts_at: measurement.starts_at,
                      observed_through: measurement.observed_through,
                      value: measurement.value,
                      input_hash: raw.payload_hash,
                      finalized_at:
                          Date.parse(measurement.observed_through) >=
                          Date.parse(measurement.ends_at)
                              ? raw.collected_at
                              : null,
                  },
              ]
            : [];
    });
    if (days.length === 0) {
        return;
    }
    const mirrored = await sql<{ day: string }[]>`
        insert into public.metric_days (
            user_id, source_id, metric, day, time_zone, value, unit, input_hash,
            normalization_version, calculation_version, finalized_at
        )
        select ${userId}, ${sourceId}, 'steps', day.day, day.time_zone, day.value, 'steps',
            day.input_hash, 1, 1, day.finalized_at
        from jsonb_to_recordset(${sql.json(days)}::jsonb) as day (
            day date, time_zone text, starts_at timestamptz, observed_through timestamptz,
            value numeric, input_hash text, finalized_at timestamptz
        )
        where exists (
            select 1
            from public.fights as fight
            join public.fight_members as member on member.fight_id = fight.id
            where member.user_id = ${userId}
                and member.state = 'accepted'
                and fight.state in ('live', 'awaiting_final_sync')
                and day.starts_at < fight.ends_at
                and day.observed_through > fight.starts_at
        )
        on conflict (user_id, source_id, metric, day) do update
        set value = excluded.value,
            time_zone = excluded.time_zone,
            input_hash = excluded.input_hash,
            normalization_version = excluded.normalization_version,
            calculation_version = excluded.calculation_version,
            finalized_at = case
                when public.metric_days.finalized_at is not null then public.metric_days.finalized_at
                else excluded.finalized_at
            end,
            updated_at = now()
        where public.metric_days.finalized_at is null
        returning day::text as day
    `;
    if (mirrored.length === 0) {
        return;
    }
    await sql`
        insert into public.step_days (user_id, day, steps, updated_at)
        select user_id, day, value::integer, updated_at
        from public.metric_days
        where user_id = ${userId}
            and source_id = ${sourceId}
            and metric = 'steps'
            and day = any(${sql.array(mirrored.map((row) => row.day))}::date[])
        on conflict (user_id, day) do update
        set steps = excluded.steps, updated_at = excluded.updated_at
    `;
}

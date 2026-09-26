import type { Sql } from "postgres";
import { workoutDayMetricValues } from "@/lib/domain/activity/activity-measurements";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { civilDayBounds, civilDayStamp } from "@/lib/scoring/civil-day";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    healthKitAggregateFightSchema,
    healthKitAggregateSourceSchema,
} from "@/lib/types/healthkit/healthkit-aggregate-database";
import type {
    HealthKitAggregateSync,
    HealthKitAggregateSyncResponse,
} from "@/lib/types/healthkit/healthkit-aggregate";
import {
    insertActivityRaw,
    processActivity,
    workoutPayload,
} from "./activity-pipeline-supabase-query";

export async function syncHealthKitAggregates(
    userId: string,
    input: HealthKitAggregateSync,
    database: Sql = createDatabaseClient(),
): Promise<HealthKitAggregateSyncResponse> {
    const intake = await database.begin("read write", async (sql) => {
        const [sourceRow] = await sql`
            insert into public.data_sources (
                user_id, provider, source_label, connection_route, capabilities,
                status, consent_version, connected_at, last_success_at, complete_through
            ) values (
                ${userId}, 'apple_health', 'Apple Health', 'healthkit',
                array[
                    'steps','active_energy','resting_energy','walking_running_distance','exercise_minutes',
                    'stand_minutes','stand_hours','flights_climbed','cycling_distance',
                    'swimming_distance','move_time_minutes','wheelchair_distance',
                    'wheelchair_pushes','swimming_strokes','rowing_distance','paddle_distance',
                    'skating_distance','cross_country_ski_distance','downhill_snow_distance',
                    'workout_count','workout_time','walk_run_workout_distance'
                ]::text[],
                'healthy', 1, now(), now(), ${input.complete_through}
            )
            on conflict (user_id, provider, connection_route) do update
            set status = 'healthy', revoked_at = null, last_success_at = now(),
                capabilities = excluded.capabilities,
                complete_through = greatest(
                    coalesce(public.data_sources.complete_through, excluded.complete_through),
                    excluded.complete_through
                ),
                last_error_code = null
            returning id, complete_through::text as complete_through,
                clock_timestamp()::text as server_now
        `;
        if (!sourceRow) {
            throw new ApiError(
                500,
                ERROR_CODES.db_error,
                "Could not save Apple Health source",
            );
        }
        const source = healthKitAggregateSourceSchema.parse(sourceRow);
        if (
            Date.parse(input.complete_through) > Date.parse(source.server_now)
        ) {
            throw new ApiError(
                400,
                ERROR_CODES.validation,
                "complete_through cannot be in the future",
            );
        }
        if (
            Date.parse(source.complete_through) >
            Date.parse(input.complete_through)
        ) {
            throw new ApiError(
                409,
                ERROR_CODES.conflict,
                "Sync is older than current Apple Health data",
            );
        }

        const fightIds = input.fight_aggregates.map(
            (aggregate) => aggregate.fight_id,
        );
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
                and fight.state in ('live', 'awaiting_final_sync')
            order by fight.id
            for update of fight, member
        `,
        );
        const submittedFightIds = new Set(fightIds);
        if (
            fights.length !== submittedFightIds.size ||
            fights.some((fight) => !submittedFightIds.has(fight.fight_id))
        ) {
            throw new ApiError(
                400,
                ERROR_CODES.validation,
                "Fight aggregate set does not match sync context",
            );
        }
        const fightsById = new Map(
            fights.map((fight) => [fight.fight_id, fight]),
        );
        for (const aggregate of input.fight_aggregates) {
            const fight = fightsById.get(aggregate.fight_id);
            const expectedCutoff = fight
                ? Math.min(
                      Date.parse(input.complete_through),
                      Date.parse(fight.ends_at),
                  )
                : Number.NaN;
            if (
                !fight ||
                Date.parse(aggregate.starts_at) !==
                    Date.parse(fight.starts_at) ||
                Date.parse(aggregate.ends_at) !== Date.parse(fight.ends_at) ||
                Date.parse(aggregate.cutoff_at) !== expectedCutoff
            ) {
                throw new ApiError(
                    400,
                    ERROR_CODES.validation,
                    "Fight aggregate does not match sync context",
                );
            }
            if (aggregate.step_checkpoints) {
                let cursor = Date.parse(fight.starts_at);
                for (const point of aggregate.step_checkpoints) {
                    const day = civilDayStamp(
                        new Date(cursor),
                        fight.time_zone,
                    );
                    const cutoff = Math.min(
                        civilDayBounds(day, fight.time_zone).endsAt.getTime(),
                        expectedCutoff,
                    );
                    if (
                        point.day !== day ||
                        Date.parse(point.cutoff_at) !== cutoff
                    ) {
                        throw new ApiError(
                            400,
                            ERROR_CODES.validation,
                            "Fight checkpoints must cover each Fight day",
                        );
                    }
                    cursor = cutoff;
                }
            }
        }

        for (const day of input.merged_days) {
            const overlapsSubmittedFight = fights.some(
                (fight) =>
                    Date.parse(day.starts_at) <
                        Math.min(
                            Date.parse(fight.ends_at),
                            Date.parse(input.complete_through),
                        ) &&
                    Date.parse(day.ends_at) > Date.parse(fight.starts_at),
            );
            if (!overlapsSubmittedFight) {
                throw new ApiError(
                    400,
                    ERROR_CODES.validation,
                    "Merged day does not overlap a submitted Fight",
                );
            }
        }

        const derivedMetrics: readonly string[] = workoutDayMetricValues;
        return insertActivityRaw(sql, userId, source.id, input.complete_through, [
            ...input.fight_aggregates.map((aggregate) => {
                const zone =
                    fightsById.get(aggregate.fight_id)?.time_zone ??
                    input.time_zone;
                return {
                    record_kind: "total" as const,
                    record_type: "steps",
                    record_key: `fight:${aggregate.fight_id}`,
                    starts_at: aggregate.starts_at,
                    ends_at: aggregate.cutoff_at,
                    time_zone: zone,
                    payload: {
                        fight_id: aggregate.fight_id,
                        starts_at: new Date(aggregate.starts_at).toISOString(),
                        ends_at: new Date(aggregate.ends_at).toISOString(),
                        cutoff_at: new Date(aggregate.cutoff_at).toISOString(),
                        time_zone: zone,
                        steps: aggregate.steps,
                        step_checkpoints: aggregate.step_checkpoints ?? null,
                    },
                };
            }),
            ...[
                ...input.merged_days.map((day) => ({
                    metric: "steps",
                    day: day.day,
                    starts_at: day.starts_at,
                    ends_at: day.ends_at,
                    value: day.steps,
                    unit: "steps",
                })),
                // Workout day totals are derived from workout records, never taken from a client sum.
                ...(input.activity_days ?? []).filter(
                    (day) => !derivedMetrics.includes(day.metric),
                ),
            ].map((day) => ({
                record_kind: "total" as const,
                record_type: day.metric,
                record_key: `day:${day.day}`,
                starts_at: day.starts_at,
                ends_at: day.ends_at,
                time_zone: input.time_zone,
                payload: {
                    metric: day.metric,
                    day: day.day,
                    starts_at: new Date(day.starts_at).toISOString(),
                    ends_at: new Date(day.ends_at).toISOString(),
                    time_zone: input.time_zone,
                    value: day.value,
                    unit: day.unit,
                },
            })),
            // Installed builds send no deletions: a workout missing from their list is not deleted.
            ...(input.workouts ?? []).map((workout) => ({
                record_kind: "workout" as const,
                record_type: "workout",
                record_key: workout.healthkit_uuid,
                starts_at: workout.started_at,
                ends_at: workout.ended_at,
                time_zone: input.time_zone,
                payload: workoutPayload(workout),
            })),
        ]);
    });

    return {
        complete_through: input.complete_through,
        synced_days: input.merged_days.length,
        synced_fights: input.fight_aggregates.length,
        // The activity import resolves its own backlog; a Steps upload waits only for its readings.
        processing: await processActivity({ userId, rawIds: intake.ids }, database),
    };
}

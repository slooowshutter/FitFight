import { createHash } from "node:crypto";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { civilDayInTimeZone } from "@/lib/scoring/civil-day";
import { scoreFight } from "@/lib/scoring/score-fight";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { asNumber, type OutcomeRule } from "@/lib/types/database";
import type {
  HealthKitAggregateSync,
  HealthKitAggregateSyncResponse,
} from "@/lib/types/healthkit/healthkit-aggregate";

export async function syncHealthKitAggregates(
  userId: string,
  input: HealthKitAggregateSync,
  database: Sql = createDatabaseClient(),
): Promise<HealthKitAggregateSyncResponse> {
  return database.begin("read write", async (sql) => {
    const [source] = await sql<{
      id: string;
      complete_through: string;
      server_now: string;
    }[]>`
      insert into public.data_sources (
        user_id, provider, source_label, connection_route, capabilities,
        status, consent_version, connected_at, last_success_at, complete_through
      ) values (
        ${userId}, 'apple_health', 'Apple Health', 'healthkit', array['steps']::text[],
        'healthy', 1, now(), now(), ${input.complete_through}
      )
      on conflict (user_id, provider, connection_route) do update
      set status = 'healthy', revoked_at = null, last_success_at = now(),
        complete_through = greatest(
          coalesce(public.data_sources.complete_through, excluded.complete_through),
          excluded.complete_through
        ),
        last_error_code = null
      returning id, complete_through::text as complete_through,
        clock_timestamp()::text as server_now
    `;
    if (!source) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not save Apple Health source");
    }
    if (Date.parse(input.complete_through) > Date.parse(source.server_now)) {
      throw new ApiError(
        400,
        ERROR_CODES.validation,
        "complete_through cannot be in the future",
      );
    }
    if (Date.parse(source.complete_through) > Date.parse(input.complete_through)) {
      throw new ApiError(409, ERROR_CODES.conflict, "Sync is older than current Apple Health data");
    }

    const fightIds = input.fight_aggregates.map((aggregate) => aggregate.fight_id);
    const fights = await sql<{
      fight_id: string;
      starts_at: string;
      ends_at: string;
      outcome_rule: OutcomeRule;
      stake_minor: number | null;
      default_goal_value: string | null;
    }[]>`
      select fight.id as fight_id, fight.starts_at::text as starts_at,
        fight.ends_at::text as ends_at,
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
    `;
    const submittedFightIds = new Set(fightIds);
    if (fights.length !== submittedFightIds.size
      || fights.some((fight) => !submittedFightIds.has(fight.fight_id))) {
      throw new ApiError(
        400,
        ERROR_CODES.validation,
        "Fight aggregate set does not match sync context",
      );
    }
    const fightsById = new Map(fights.map((fight) => [fight.fight_id, fight]));
    const aggregateFights = input.fight_aggregates.map((aggregate) => {
      const fight = fightsById.get(aggregate.fight_id);
      const expectedCutoff = fight
        ? Math.min(Date.parse(input.complete_through), Date.parse(fight.ends_at))
        : Number.NaN;
      if (!fight
        || Date.parse(aggregate.starts_at) !== Date.parse(fight.starts_at)
        || Date.parse(aggregate.ends_at) !== Date.parse(fight.ends_at)
        || Date.parse(aggregate.cutoff_at) !== expectedCutoff) {
        throw new ApiError(
          400,
          ERROR_CODES.validation,
          "Fight aggregate does not match sync context",
        );
      }
      return { aggregate, fight };
    });

    for (const day of input.merged_days) {
      const overlapsSubmittedFight = fights.some((fight) =>
        Date.parse(day.starts_at) < Math.min(
          Date.parse(fight.ends_at),
          Date.parse(input.complete_through),
        )
        && Date.parse(day.ends_at) > Date.parse(fight.starts_at)
      );
      if (!overlapsSubmittedFight) {
        throw new ApiError(
          400,
          ERROR_CODES.validation,
          "Merged day does not overlap a submitted Fight",
        );
      }
    }

    if (input.merged_days.length > 0) {
      const completeLocalDay = civilDayInTimeZone(
        new Date(input.complete_through),
        input.time_zone,
      );
      const dayRows = input.merged_days.map((day) => ({
        user_id: userId,
        source_id: source.id,
        metric: "steps",
        day: day.day,
        value: day.steps,
        unit: "steps",
        input_hash: createHash("sha256").update(JSON.stringify({
          time_zone: input.time_zone,
          ...day,
        })).digest("hex"),
        normalization_version: 1,
        calculation_version: 1,
        finalized_at: day.day < completeLocalDay ? new Date(input.complete_through) : null,
      }));
      await sql`
        insert into public.metric_days ${sql(
          dayRows,
          "user_id",
          "source_id",
          "metric",
          "day",
          "value",
          "unit",
          "input_hash",
          "normalization_version",
          "calculation_version",
          "finalized_at",
        )}
        on conflict (user_id, source_id, metric, day) do update
        set value = excluded.value,
          input_hash = excluded.input_hash,
          normalization_version = excluded.normalization_version,
          calculation_version = excluded.calculation_version,
          finalized_at = excluded.finalized_at,
          updated_at = now()
        where public.metric_days.finalized_at is null
      `;
      await sql`
        insert into public.step_days (user_id, day, steps, updated_at)
        select user_id, day, value::integer, updated_at
        from public.metric_days
        where user_id = ${userId}
          and source_id = ${source.id}
          and metric = 'steps'
          and day = any(${sql.array(input.merged_days.map((day) => day.day))}::date[])
        on conflict (user_id, day) do update
        set steps = excluded.steps, updated_at = excluded.updated_at
      `;
    }

    for (const { aggregate, fight } of aggregateFights) {
      const inputHash = createHash("sha256").update(JSON.stringify(aggregate)).digest("hex");
      await sql`
        insert into private.fight_score_snapshots (
          fight_id, user_id, source_id, cutoff_at, value,
          input_hash, calculation_version, is_final, created_at
        ) values (
          ${aggregate.fight_id}, ${userId}, ${source.id}, ${aggregate.cutoff_at},
          ${aggregate.steps}, ${inputHash}, 1, false, clock_timestamp()
        )
        on conflict (fight_id, user_id, cutoff_at, input_hash) do nothing
      `;
      const [latest] = await sql<{ value: string }[]>`
        select value::text as value
        from private.fight_score_snapshots
        where fight_id = ${aggregate.fight_id}
          and user_id = ${userId}
        order by cutoff_at desc, created_at desc, id desc
        limit 1
      `;
      if (!latest) {
        throw new ApiError(500, ERROR_CODES.db_error, "Could not save Fight aggregate");
      }
      await sql`
        update public.fight_members
        set current_value = ${latest.value},
          selected_source_id = ${source.id},
          source_label = 'Apple Health',
          freshness = 'recent',
          last_synced_at = now(),
          final_steps_complete = final_steps_complete
            or ${Date.parse(input.complete_through) >= Date.parse(fight.ends_at)},
          input_revision = case
            when current_value is distinct from ${latest.value}
              or selected_source_id is distinct from ${source.id}
              or source_label is distinct from 'Apple Health'
              or freshness is distinct from 'recent'
            then coalesce(input_revision, 0) + 1
            else input_revision
          end
        where fight_id = ${aggregate.fight_id}
          and user_id = ${userId}
          and state = 'accepted'
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
        where fight_id = ${aggregate.fight_id} and state = 'accepted'
        order by user_id
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
          where fight_id = ${aggregate.fight_id}
            and user_id = ${score.userId}
            and finalized_at is null
        `;
      }
    }

    return {
      complete_through: input.complete_through,
      synced_days: input.merged_days.length,
      synced_fights: input.fight_aggregates.length,
    };
  });
}

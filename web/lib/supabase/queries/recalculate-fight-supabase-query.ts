import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { nextFightState, observationOverlapsWindow } from "@/lib/scoring/fight-clock";
import { scoreFight, scoringEngineVersion } from "@/lib/scoring/score-fight";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  asNumber,
  type FightState,
  type ObservationRow,
  type OutcomeRule,
} from "@/lib/types/database";

const SCORABLE_STATES = ["live", "scheduled", "awaiting_final_sync"] as const;

function latestObservations(rows: ObservationRow[]): ObservationRow[] {
  const latest = new Map<string, ObservationRow>();
  for (const row of rows) {
    const key = `${row.source_id}:${row.external_record_id}`;
    const prev = latest.get(key);
    if (!prev || row.revision > prev.revision) {
      latest.set(key, row);
    }
  }
  return [...latest.values()];
}

export async function listFightsToRecalculate(
  userId: string,
  admin: SupabaseClient = createAdminClient(),
): Promise<string[]> {
  const { data: memberships, error: memberError } = await admin
    .from("fight_members")
    .select("fight_id")
    .eq("user_id", userId)
    .eq("state", "accepted");
  if (memberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight memberships");
  }
  const fightIds = (memberships ?? []).map((row) => row.fight_id as string);
  if (fightIds.length === 0) {
    return [];
  }
  const { data: fights, error: fightError } = await admin
    .from("fights")
    .select("id")
    .in("id", fightIds)
    .in("state", [...SCORABLE_STATES]);
  if (fightError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fights");
  }
  return (fights ?? []).map((row) => row.id as string);
}

export async function recalculateFight(
  fightId: string,
  admin: SupabaseClient = createAdminClient(),
  now: Date = new Date(),
  database: Sql = createDatabaseClient(),
): Promise<void> {
  await database.begin("read write", async (sql) => {
    const [fight] = await sql<{
      state: FightState;
      outcome_rule: OutcomeRule;
      stake_minor: number | null;
      default_goal_value: string | null;
      starts_at: string;
      ends_at: string;
      final_sync_grace_seconds: number;
    }[]>`
      select
        state::text as state,
        outcome_rule::text as outcome_rule,
        stake_minor,
        default_goal_value::text as default_goal_value,
        starts_at::text as starts_at,
        ends_at::text as ends_at,
        final_sync_grace_seconds
      from public.fights
      where id = ${fightId}
      for update
    `;
    if (
      !fight
      || fight.state === "final"
      || fight.state === "cancelled"
      || fight.state === "draft"
    ) {
      return;
    }

    const members = await sql<{
      user_id: string;
      selected_source_id: string | null;
      personal_target: string | null;
      input_revision: number | null;
    }[]>`
      select
        user_id,
        selected_source_id,
        personal_target::text as personal_target,
        input_revision
      from public.fight_members
      where fight_id = ${fightId}
        and state = 'accepted'
      for update
    `;
    const userIds = members.map((member) => member.user_id);
    const sourceIds = members
      .map((member) => member.selected_source_id)
      .filter((id): id is string => id !== null);

    const snapshotValues = new Map<string, number>();
    let observations: ObservationRow[] = [];
    if (userIds.length > 0) {
      const snapshots = await sql<{ user_id: string; value: string }[]>`
        select distinct on (user_id) user_id, value::text as value
        from private.fight_score_snapshots
        where fight_id = ${fightId}
          and user_id = any(${sql.array(userIds)}::uuid[])
          and cutoff_at <= ${fight.ends_at}
        order by user_id, cutoff_at desc, created_at desc
      `;
      for (const snapshot of snapshots) {
        snapshotValues.set(snapshot.user_id, Number(snapshot.value));
      }
      const observationData = await sql<ObservationRow[]>`
        select
          id, user_id, source_id, external_record_id, metric,
          starts_at::text as starts_at,
          ends_at::text as ends_at,
          value::text as value,
          unit,
          revision,
          retracted_at::text as retracted_at
        from private.metric_observations
        where metric = 'steps'
          and user_id = any(${sql.array(userIds)}::uuid[])
          and retracted_at is null
          and starts_at < ${fight.ends_at}
          and ends_at > ${fight.starts_at}
      `;
      observations = latestObservations(observationData).filter((row) =>
        observationOverlapsWindow(row.starts_at, row.ends_at, fight.starts_at, fight.ends_at),
      );
    }

    const completeThroughBySource = new Map<string, string>();
    if (sourceIds.length > 0) {
      const sources = await sql<{ id: string; complete_through: string | null }[]>`
        select id, complete_through::text as complete_through
        from public.data_sources
        where id = any(${sql.array(sourceIds)}::uuid[])
      `;
      for (const source of sources) {
        if (source.complete_through) {
          completeThroughBySource.set(source.id, source.complete_through);
        }
      }
    }

    const scored = scoreFight({
      outcomeRule: fight.outcome_rule,
      stakeMinor: fight.stake_minor,
      defaultGoalValue: asNumber(fight.default_goal_value),
      members: members.map((member) => {
        const value = snapshotValues.get(member.user_id) ?? observations
            .filter(
              (row) =>
                row.user_id === member.user_id &&
                member.selected_source_id !== null &&
                row.source_id === member.selected_source_id,
            )
            .reduce((sum, row) => sum + (asNumber(row.value) ?? 0), 0);
        return {
          userId: member.user_id,
          value,
          personalTarget: asNumber(member.personal_target),
        };
      }),
    });

    const nextRevision =
      Math.max(0, ...members.map((member) => member.input_revision ?? 0)) + 1;
    const endsAt = new Date(fight.ends_at);
    const graceEnds = new Date(endsAt.getTime() + fight.final_sync_grace_seconds * 1000);

    const allComplete =
      members.length > 0 &&
      members.every((member) => {
        if (!member.selected_source_id) {
          return false;
        }
        const completeThrough = completeThroughBySource.get(member.selected_source_id);
        if (!completeThrough) {
          return false;
        }
        return Date.parse(completeThrough) >= Date.parse(fight.ends_at);
      });

    const nextState = nextFightState({
      state: fight.state,
      nowMs: now.getTime(),
      startsAtMs: new Date(fight.starts_at).getTime(),
      endsAtMs: endsAt.getTime(),
      graceEndsMs: graceEnds.getTime(),
      allSourcesCompleteThroughEnd: allComplete,
    });

    const byUser = new Map(scored.map((row) => [row.userId, row]));
    for (const member of members) {
      const result = byUser.get(member.user_id);
      if (!result) {
        continue;
      }
      const completeThrough = member.selected_source_id
        ? completeThroughBySource.get(member.selected_source_id)
        : undefined;
      const finalStepsComplete = Boolean(
        completeThrough && Date.parse(completeThrough) >= Date.parse(fight.ends_at),
      );
      await sql`
        update public.fight_members
        set current_value = ${result.currentValue},
          rank = ${result.rank},
          outcome_minor = ${result.outcomeMinor},
          freshness = 'recent',
          input_revision = ${nextRevision},
          scoring_engine_version = ${scoringEngineVersion},
          final_steps_complete = final_steps_complete or ${finalStepsComplete}
        where fight_id = ${fightId}
          and user_id = ${member.user_id}
          and finalized_at is null
      `;
    }
    if (nextState !== fight.state) {
      await sql`
        update public.fights
        set state = ${nextState}
        where id = ${fightId}
          and state = ${fight.state}
      `;
    }
  });
}

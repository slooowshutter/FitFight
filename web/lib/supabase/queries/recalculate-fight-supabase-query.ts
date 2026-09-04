import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { nextFightState, observationOverlapsWindow } from "@/lib/scoring/fight-clock";
import { STEPS_CALCULATION_VERSION, scoreFight } from "@/lib/scoring/score-fight";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  asNumber,
  type DataSourceRow,
  type FightMemberRow,
  type FightRow,
  type FightState,
  type ObservationRow,
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
  const { data: fightData, error: fightError } = await admin
    .from("fights")
    .select("*")
    .eq("id", fightId)
    .maybeSingle();
  if (fightError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight");
  }
  const fight = fightData as FightRow | null;
  if (!fight) {
    return;
  }
  if (fight.state === "final" || fight.state === "cancelled" || fight.state === "draft") {
    return;
  }

  const { data: memberData, error: memberError } = await admin
    .from("fight_members")
    .select("*")
    .eq("fight_id", fightId)
    .eq("state", "accepted");
  if (memberError) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not load fight members");
  }
  const members = (memberData ?? []) as FightMemberRow[];
  const userIds = members.map((member) => member.user_id);
  const sourceIds = members
    .map((member) => member.selected_source_id)
    .filter((id): id is string => typeof id === "string");

  let observations: ObservationRow[] = [];
  const snapshotValues = new Map<string, number>();
  if (userIds.length > 0) {
    const snapshots = await database<{ user_id: string; value: string }[]>`
      select distinct on (user_id) user_id, value::text as value
      from private.fight_score_snapshots
      where fight_id = ${fightId}
        and user_id = any(${database.array(userIds)}::uuid[])
        and cutoff_at <= ${fight.ends_at}
      order by user_id, cutoff_at desc, created_at desc
    `;
    for (const snapshot of snapshots) {
      snapshotValues.set(snapshot.user_id, Number(snapshot.value));
    }
    const observationData = await database<ObservationRow[]>`
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
        and user_id = any(${database.array(userIds)}::uuid[])
        and retracted_at is null
        and starts_at < ${fight.ends_at}
        and ends_at > ${fight.starts_at}
    `;
    observations = latestObservations(observationData).filter((row) =>
      observationOverlapsWindow(row.starts_at, row.ends_at, fight.starts_at, fight.ends_at),
    );
  }

  const sourcesById = new Map<string, DataSourceRow>();
  if (sourceIds.length > 0) {
    const { data: sourceData, error: sourceError } = await admin
      .from("data_sources")
      .select("id, user_id, provider, source_label, contributing_source_labels, connection_route, status, complete_through")
      .in("id", sourceIds);
    if (sourceError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not load data sources");
    }
    for (const source of (sourceData ?? []) as DataSourceRow[]) {
      sourcesById.set(source.id, source);
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
  const nowIso = now.toISOString();
  const endsAt = new Date(fight.ends_at);
  const graceEnds = new Date(endsAt.getTime() + fight.final_sync_grace_seconds * 1000);

  const allComplete =
    members.length > 0 &&
    members.every((member) => {
      if (!member.selected_source_id) {
        return false;
      }
      const source = sourcesById.get(member.selected_source_id);
      if (!source?.complete_through) {
        return false;
      }
      return Date.parse(source.complete_through) >= Date.parse(fight.ends_at);
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
    const patch: Record<string, unknown> = {
      current_value: result.currentValue,
      rank: result.rank,
      outcome_minor: result.outcomeMinor,
      freshness: "recent",
      input_revision: nextRevision,
      calculation_version: STEPS_CALCULATION_VERSION,
    };
    if (member.selected_source_id) {
      const completeThrough = sourcesById.get(member.selected_source_id)?.complete_through;
      if (completeThrough && Date.parse(completeThrough) >= Date.parse(fight.ends_at)) {
        patch.final_steps_complete = true;
      }
    }
    if (nextState === "final" && member.finalized_at == null) {
      patch.final_value = result.currentValue;
      patch.finalized_at = nowIso;
    }
    const { error: updateError } = await admin
      .from("fight_members")
      .update(patch)
      .eq("fight_id", fightId)
      .eq("user_id", member.user_id)
      .is("finalized_at", null);
    if (updateError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not update fight member scores");
    }
  }

  if (nextState === "final") {
    await database`
      update private.fight_score_snapshots as snapshot
      set is_final = true
      where snapshot.fight_id = ${fightId}
        and snapshot.is_final = false
        and snapshot.id in (
          select distinct on (user_id) id
          from private.fight_score_snapshots
          where fight_id = ${fightId}
          order by user_id, cutoff_at desc, created_at desc, id desc
        )
    `;
  }

  if (nextState !== fight.state) {
    const { error: stateError } = await admin
      .from("fights")
      .update({ state: nextState })
      .eq("id", fightId);
    if (stateError) {
      throw new ApiError(500, ERROR_CODES.db_error, "Could not update fight state");
    }
  }
}

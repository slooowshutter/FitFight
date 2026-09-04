import type { SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { nextFightState } from "@/lib/scoring/fight-clock";
import { scoreFight } from "@/lib/scoring/score-fight";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  fightCalculationRowSchema,
  fightCalculationMemberSchema,
  fightCalculationSnapshotSchema,
} from "@/lib/types/fights/fight-calculation";

const SCORABLE_STATES = ["live", "scheduled", "awaiting_final_sync"] as const;

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

/** Serialize score reads and finalization with the aggregate upload transaction. */
export async function recalculateFight(
  fightId: string,
  now: Date = new Date(),
  database: Sql = createDatabaseClient(),
): Promise<void> {
  await database.begin("read write", async (sql) => {
    const fights = await sql`
      select state::text, starts_at::text, ends_at::text,
        final_sync_grace_seconds, outcome_rule::text, stake_minor, default_goal_value::text
      from public.fights where id = ${fightId}
      for update
    `;
    if (!fights[0]) return;
    const fight = fightCalculationRowSchema.parse(fights[0]);
    if (["final", "cancelled", "draft", "inviting"].includes(fight.state)) return;

    const members = fightCalculationMemberSchema.array().parse(await sql`
      select user_id, personal_target::text, input_revision
      from public.fight_members
      where fight_id = ${fightId} and state = 'accepted'
      order by user_id
      for update
    `);
    const snapshots = fightCalculationSnapshotSchema.array().parse(await sql`
      select distinct on (snapshot.user_id)
        snapshot.id, snapshot.user_id, snapshot.value::text, snapshot.cutoff_at::text
      from private.fight_score_snapshots as snapshot
      join public.fight_members as member
        on member.fight_id = snapshot.fight_id and member.user_id = snapshot.user_id
        and member.selected_source_id = snapshot.source_id and member.state = 'accepted'
      where snapshot.fight_id = ${fightId} and snapshot.cutoff_at <= ${fight.ends_at}
      order by snapshot.user_id, snapshot.cutoff_at desc, snapshot.created_at desc, snapshot.id desc
    `);
    const byUser = new Map(snapshots.map((snapshot) => [snapshot.user_id, snapshot]));
    const endsAtMs = Date.parse(fight.ends_at);
    const allComplete = members.length > 0 && members.every((member) => {
      const snapshot = byUser.get(member.user_id);
      return snapshot !== undefined && Date.parse(snapshot.cutoff_at) === endsAtMs;
    });
    const nextState = nextFightState({
      state: fight.state,
      nowMs: now.getTime(),
      startsAtMs: Date.parse(fight.starts_at),
      endsAtMs,
      graceEndsMs: endsAtMs + fight.final_sync_grace_seconds * 1000,
      allSourcesCompleteThroughEnd: allComplete,
    });
    const scores = scoreFight({
      outcomeRule: fight.outcome_rule,
      stakeMinor: fight.stake_minor,
      defaultGoalValue: fight.default_goal_value,
      members: members.map((member) => ({
        userId: member.user_id,
        value: byUser.get(member.user_id)?.value ?? 0,
        personalTarget: member.personal_target,
      })),
    });
    const revision = Math.max(0, ...members.map((member) => member.input_revision ?? 0)) + 1;
    const final = nextState === "final";
    for (const score of scores) {
      const snapshot = byUser.get(score.userId);
      const complete = snapshot !== undefined && Date.parse(snapshot.cutoff_at) === endsAtMs;
      await sql`
        update public.fight_members
        set current_value = ${score.currentValue}, rank = ${score.rank},
          outcome_minor = ${score.outcomeMinor}, input_revision = ${revision},
          final_steps_complete = ${complete},
          final_value = case when ${final} then ${score.currentValue} else final_value end,
          finalized_at = case when ${final} then ${now.toISOString()}::timestamptz else finalized_at end
        where fight_id = ${fightId} and user_id = ${score.userId}
      `;
      if (final && snapshot) {
        await sql`update private.fight_score_snapshots set is_final = true where id = ${snapshot.id}`;
      }
    }
    if (nextState !== fight.state) {
      await sql`update public.fights set state = ${nextState} where id = ${fightId}`;
    }
  });
}

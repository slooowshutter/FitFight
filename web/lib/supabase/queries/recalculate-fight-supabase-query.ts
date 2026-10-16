import type { Sql } from "postgres";
import { nextFightState } from "@/lib/scoring/fight-clock";
import { scoreFight } from "@/lib/scoring/score-fight";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    fightCalculationRowSchema,
    fightCalculationMemberSchema,
    fightCalculationSnapshotSchema,
} from "@/lib/types/fights/fight-calculation";
import {
    enqueueAwaitingFinalSyncNotifications,
    enqueueFightFinalizedNotifications,
    enqueueFriendsResultsNotifications,
    enqueueFriendsSyncNotifications,
    supersedeGraceNotifications,
} from "./notification-intents-supabase-query";

/** Serialize score reads and finalization with the aggregate upload transaction. */
export async function recalculateFight(
    fightId: string,
    now: Date = new Date(),
    database: Sql = createDatabaseClient(),
): Promise<void> {
    await database.begin("read write", async (sql) => {
        // Without closes_after_grace the Fight has no deadline: it waits for everyone's final Steps.
        const fights = await sql`
            select state::text, starts_at::text, ends_at::text,
                (case when closes_after_grace
                    then ends_at + final_sync_grace_seconds * interval '1 second' end)::text as grace_ends_at,
                outcome_rule::text, stake_minor, default_goal_value::text, host_id, friends
            from public.fights where id = ${fightId}
            for update
        `;
        if (!fights[0]) return;
        const fight = fightCalculationRowSchema.parse(fights[0]);
        if (["final", "cancelled", "draft", "inviting"].includes(fight.state))
            return;

        const members = fightCalculationMemberSchema.array().parse(
            await sql`
            select user_id, personal_target::text, input_revision
            from public.fight_members
            where fight_id = ${fightId} and state = 'accepted'
            order by user_id
            for update
        `,
        );
        const snapshots = fightCalculationSnapshotSchema.array().parse(
            await sql`
            select distinct on (snapshot.user_id)
                snapshot.id, snapshot.user_id, snapshot.value::text, snapshot.cutoff_at::text
            from private.fight_score_snapshots as snapshot
            join public.fight_members as member
                on member.fight_id = snapshot.fight_id and member.user_id = snapshot.user_id
                and member.selected_source_id = snapshot.source_id and member.state = 'accepted'
            where snapshot.fight_id = ${fightId} and snapshot.cutoff_at <= ${fight.ends_at}
            order by snapshot.user_id, snapshot.cutoff_at desc, snapshot.created_at desc, snapshot.id desc
        `,
        );
        const byUser = new Map(
            snapshots.map((snapshot) => [snapshot.user_id, snapshot]),
        );
        const endsAtMs = Date.parse(fight.ends_at);
        const scoreInput = {
            outcomeRule: fight.outcome_rule,
            stakeMinor: fight.stake_minor,
            defaultGoalValue: fight.default_goal_value,
            members: members.map((member) => {
                const snapshot = byUser.get(member.user_id);
                return {
                    userId: member.user_id,
                    value: snapshot?.value ?? 0,
                    personalTarget: member.personal_target,
                    complete:
                        snapshot !== undefined &&
                        Date.parse(snapshot.cutoff_at) === endsAtMs,
                };
            }),
        };
        // Members without final Steps keep their last synced total. Steps only go up, so a lone
        // missing member already ahead of everyone else cannot change any rank.
        // NOTE: awaitingDueAt in the closer mirrors this rule to pick which Fights to recalculate.
        const missing = scoreInput.members.filter((member) => !member.complete);
        const nextState = nextFightState({
            state: fight.state,
            nowMs: now.getTime(),
            startsAtMs: Date.parse(fight.starts_at),
            endsAtMs,
            graceEndsMs: fight.grace_ends_at === null ? null : Date.parse(fight.grace_ends_at),
            resultSettled:
                members.length > 0 &&
                (missing.length === 0 ||
                    (fight.outcome_rule === "highest_total" &&
                        missing.length === 1 &&
                        scoreInput.members.length > 1 &&
                        scoreInput.members.every(
                            (member) =>
                                member === missing[0] ||
                                member.value < missing[0].value,
                        ))),
        });
        const final = nextState === "final";
        const scores = scoreFight(scoreInput);
        const revision =
            Math.max(
                0,
                ...members.map((member) => member.input_revision ?? 0),
            ) + 1;
        const scoredMembers = scores.map((score) => {
            const snapshot = byUser.get(score.userId);
            return {
                user_id: score.userId,
                current_value: score.currentValue,
                rank: score.rank,
                outcome_minor: score.outcomeMinor,
                final_steps_complete:
                    snapshot !== undefined &&
                    Date.parse(snapshot.cutoff_at) === endsAtMs,
            };
        });
        if (scoredMembers.length > 0) {
            await sql`
                update public.fight_members as member
                set current_value = score.current_value, rank = score.rank,
                    outcome_minor = score.outcome_minor, input_revision = ${revision},
                    final_steps_complete = score.final_steps_complete
                from jsonb_to_recordset(${sql.json(scoredMembers)}::jsonb) as score (
                    user_id uuid, current_value numeric, rank integer, outcome_minor integer,
                    final_steps_complete boolean
                )
                where member.fight_id = ${fightId}
                    and member.user_id = score.user_id
                    and member.finalized_at is null
            `;
        }
        if (final && snapshots.length > 0) {
            await sql`
                update private.fight_score_snapshots set is_final = true
                where id = any(${sql.array(snapshots.map((snapshot) => snapshot.id))}::uuid[])
            `;
        }
        if (nextState !== fight.state) {
            await sql`update public.fights set state = ${nextState} where id = ${fightId}`;
            const notificationMembers = scoredMembers
                .filter((member) => member.user_id !== fight.host_id)
                .map((member) => ({
                    user_id: member.user_id,
                    final_steps_complete: member.final_steps_complete,
                }));
            if (nextState === "awaiting_final_sync") {
                if (fight.friends) {
                    await enqueueFriendsSyncNotifications(sql, fightId);
                } else {
                    await enqueueAwaitingFinalSyncNotifications(
                        sql,
                        fightId,
                        fight.ends_at,
                        notificationMembers,
                    );
                }
            } else if (nextState === "final") {
                await supersedeGraceNotifications(sql, fightId);
                if (fight.friends) {
                    await enqueueFriendsResultsNotifications(sql, fightId, now);
                } else {
                    await enqueueFightFinalizedNotifications(
                        sql,
                        fightId,
                        now,
                        notificationMembers,
                    );
                }
            }
        }
    });
}

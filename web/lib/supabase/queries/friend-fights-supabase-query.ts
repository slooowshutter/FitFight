import type { Sql, TransactionSql } from "postgres";
import { civilDayStamp, wallMidnightToUtc } from "@/lib/scoring/civil-day";
import { createAdminClient } from "@/lib/supabase/admin";
import {
    FRIEND_FIGHT_NAME,
    FRIEND_FIGHT_TIME_ZONE,
    friendFightMemberSchema,
    friendFightPairSchema,
} from "@/lib/types/fights/friend-fight";
import { publishCivilDayScores } from "./activity-pipeline-supabase-query";
import { allocateJoinCode } from "./create-fight-supabase-query";
import { recordSharedFightParticipation } from "./profile-events-supabase-query";

/** The calendar month containing `at` in `timeZone`: the instants of its 1st and the next 1st at 00:00. */
export function calendarMonthWindow(at: Date, timeZone: string): { startsAt: string; endsAt: string } {
    const first = `${civilDayStamp(at, timeZone).slice(0, 7)}-01`;
    // Date.UTC rolls month 12 over into January of the next year.
    const next = new Date(Date.UTC(Number(first.slice(0, 4)), Number(first.slice(5, 7)), 1)).toISOString().slice(0, 10);
    return {
        startsAt: wallMidnightToUtc(first, timeZone).toISOString(),
        endsAt: wallMidnightToUtc(next, timeZone).toISOString(),
    };
}

/**
 * Gives every accepted friendship of `userId`, or only its pair with `friendId`, a round for this
 * month. A series paused after the friendship was accepted (a leave or a block) stays paused; one
 * paused before it (the pair unfriended, then refriended) resumes with the round it had.
 */
export async function ensureFriendFights(database: Sql, userId: string, friendId?: string): Promise<void> {
    const month = calendarMonthWindow(new Date(), FRIEND_FIGHT_TIME_ZONE);
    // Run once to skip pairs that need nothing, then again per pair after locking its rows, so a
    // concurrent remove, block or leave is never undone.
    const findPairs = async (sql: Sql, friend: string | null) => friendFightPairSchema.array().parse(await sql`
        select friendship.user_low, friendship.user_high, friendship.requester_id,
            series.id as series_id, live.id as live_fight_id
        from private.profile_friendships as friendship
        join public.profiles as low on low.id = friendship.user_low and low.deleted_at is null
        join public.profiles as high on high.id = friendship.user_high and high.deleted_at is null
        left join public.fight_series as series
            on series.friend_low = friendship.user_low and series.friend_high = friendship.user_high
        left join lateral (
            select round.id from public.fights as round
            where round.series_id = series.id and round.state <> 'cancelled' and round.ends_at > now()
            order by round.starts_at
            limit 1
        ) as live on true
        where friendship.state = 'accepted'
            and ${userId}::uuid in (friendship.user_low, friendship.user_high)
            and (${friend}::uuid is null or ${friend}::uuid in (friendship.user_low, friendship.user_high))
            and not exists (
                select 1 from (
                    select blocker_id, blocked_id from private.profile_blocks
                    union all select blocker_id, blocked_id from private.feed_blocks
                    union all select blocker_id, blocked_id from private.feedback_blocks
                ) as blocks
                where (blocks.blocker_id = friendship.user_low and blocks.blocked_id = friendship.user_high)
                    or (blocks.blocker_id = friendship.user_high and blocks.blocked_id = friendship.user_low)
            )
            and (${friendId !== undefined} or series.id is null or (
                (series.paused_at is null or friendship.accepted_at > series.paused_at) and live.id is null
            ))
    `);
    for (const pair of await findPairs(database, friendId ?? null)) {
        const joinCode = pair.series_id ? null : await allocateJoinCode(createAdminClient());
        await database.begin(async (sql) => {
            await sql`
                select 1 from private.profile_friendships
                where user_low = ${pair.user_low} and user_high = ${pair.user_high}
                for share
            `;
            await sql`
                select 1 from public.fight_series
                where friend_low = ${pair.user_low} and friend_high = ${pair.user_high}
                for update
            `;
            const [current] = await findPairs(sql, pair.user_low === userId.toLowerCase() ? pair.user_high : pair.user_low);
            if (!current) return;
            const [series] = current.series_id
                ? await sql<{ id: string }[]>`
                    update public.fight_series set paused_at = null where id = ${current.series_id} returning id
                `
                : await sql<{ id: string }[]>`
                    insert into public.fight_series (
                        owner_id, join_code, visibility, recurring, duration_seconds, name, time_zone,
                        friend_low, friend_high
                    )
                    values (
                        ${current.requester_id}, ${joinCode}, 'invite_only', true,
                        ${(Date.parse(month.endsAt) - Date.parse(month.startsAt)) / 1000},
                        ${FRIEND_FIGHT_NAME}, ${FRIEND_FIGHT_TIME_ZONE}, ${current.user_low}, ${current.user_high}
                    )
                    on conflict (friend_low, friend_high) where friend_low is not null
                    do update set paused_at = null
                    returning id
                `;
            // A round cancelled by unfriending this month comes back when the pair refriends.
            const [round] = current.live_fight_id
                ? [{ id: current.live_fight_id }]
                : await sql<{ id: string }[]>`
                    insert into public.fights (
                        owner_id, name, state, starts_at, ends_at, time_zone, metric,
                        outcome_rule, goal_policy, stake_kind, action_text, series_id, friends, closes_after_grace
                    )
                    select owner_id, ${FRIEND_FIGHT_NAME}, 'live', ${month.startsAt}, ${month.endsAt},
                        ${FRIEND_FIGHT_TIME_ZONE}, 'steps', 'highest_total', 'shared', 'action', action_text, id, true, false
                    from public.fight_series where id = ${series.id}
                    on conflict (series_id, starts_at) where series_id is not null
                    do update set state = case when fights.state = 'cancelled' then 'live' else fights.state end
                    returning id
                `;
            await sql`update public.fight_series set current_fight_id = ${round.id} where id = ${series.id}`;
            // Only a source the friend already has: one who never synced gets theirs from their first day Steps.
            await sql`
                insert into public.fight_members (fight_id, user_id, state, accepted_at, selected_source_id, source_label)
                select ${round.id}, friend.user_id, 'accepted', now(), source.id, source.source_label
                from unnest(${sql.array([current.user_low, current.user_high])}::uuid[]) as friend (user_id)
                left join public.data_sources as source
                    on source.user_id = friend.user_id and source.provider = 'apple_health'
                    and source.connection_route = 'healthkit'
                on conflict (fight_id, user_id) do update
                set state = 'accepted', accepted_at = now(),
                    selected_source_id = coalesce(fight_members.selected_source_id, excluded.selected_source_id),
                    source_label = coalesce(fight_members.source_label, excluded.source_label)
                where fight_members.state <> 'accepted'
            `;
            await sql`
                insert into public.fight_series_members (series_id, user_id, state, joined_at)
                values (${series.id}, ${current.user_low}, 'accepted', now()),
                    (${series.id}, ${current.user_high}, 'accepted', now())
                on conflict (series_id, user_id) do update set state = 'accepted'
                where fight_series_members.state <> 'accepted'
            `;
            await recordSharedFightParticipation(sql, round.id, null);
            const members = friendFightMemberSchema.array().parse(await sql`
                select user_id, selected_source_id from public.fight_members
                where fight_id = ${round.id} and state = 'accepted' and selected_source_id is not null
            `);
            // Score both from Steps already stored for this month, so the card is not 0 until the next sync.
            for (const member of members) {
                await publishCivilDayScores(sql, member.user_id, member.selected_source_id, round.id);
            }
        });
    }
}

/** Unfriending or blocking cancels the pair's live round and pauses its series. Nothing is deleted. */
export async function endFriendFight(sql: TransactionSql, userA: string, userB: string): Promise<void> {
    const [low, high] = [userA.toLowerCase(), userB.toLowerCase()].sort();
    const [series] = await sql<{ id: string }[]>`
        update public.fight_series set paused_at = coalesce(paused_at, now())
        where friend_low = ${low} and friend_high = ${high}
        returning id
    `;
    if (series) {
        await sql`update public.fights set state = 'cancelled' where series_id = ${series.id} and friends and state = 'live'`;
    }
}

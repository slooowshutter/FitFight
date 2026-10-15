import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { civilDayBounds, civilDayStamp } from "@/lib/scoring/civil-day";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { FRIEND_FIGHT_NAME, FRIEND_FIGHT_TIME_ZONE } from "@/lib/types/fights/friend-fight";
import { healthKitActivityBatchSchema } from "@/lib/types/healthkit/healthkit-activity-batch";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { receiveHealthKitActivity } from "./activity-pipeline-supabase-query";
import { createInvite } from "./create-invite-supabase-query";
import { deleteAccount } from "./delete-account-supabase-query";
import { blockFeedbackAuthor } from "./feedback-supabase-query";
import { blockFeedAuthor } from "./fight-posts-supabase-query";
import { calendarMonthWindow, ensureFriendFights } from "./friend-fights-supabase-query";
import { joinFight } from "./join-fight-supabase-query";
import { departFightMemberships } from "./membership-departure-supabase-query";
import { mintNextRecurringFight } from "./mint-recurring-fight-supabase-query";
import { cancelFight } from "./cancel-fight-supabase-query";
import { closeDueFightsForUser } from "./close-due-fights-supabase-query";
import { blockProfile, changeFriendship } from "./profile-friends-supabase-query";
import { getProviderUploadContext } from "./provider-uploads-supabase-query";
import { updateFight } from "./update-fight-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 5 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
});
after(async () => {
    await closeDatabaseClientForTests();
    await database.end();
});

type PairRound = {
    series_id: string;
    paused: boolean;
    owner_id: string;
    series_name: string;
    visibility: string;
    recurring: boolean;
    current_fight_id: string | null;
    id: string;
    state: string;
    starts_at: string;
    ends_at: string;
    time_zone: string;
    name: string;
    friends: boolean;
    host_id: string | null;
    accepted: number;
    sourced: number;
};

async function createUsers(count: number) {
    const users = Array.from({ length: count }, () => randomUUID());
    for (const id of users) await database`insert into auth.users (id) values (${id})`;
    return users;
}

async function removeUsers(users: string[]) {
    const ids = database.array(users);
    await database`
        delete from public.fights where owner_id = any(${ids}::uuid[]) or series_id in (
            select id from public.fight_series where friend_low = any(${ids}::uuid[]) or friend_high = any(${ids}::uuid[])
        )
    `;
    await database`delete from public.fight_series where owner_id = any(${ids}::uuid[])`;
    await database`delete from auth.users where id = any(${ids}::uuid[])`;
}

async function befriend(requester: string, recipient: string) {
    await changeFriendship(requester, recipient, "request", database);
    await changeFriendship(recipient, requester, "accept", database);
}

/** Every round of the pair's series, oldest first. */
async function pairRounds(userA: string, userB: string) {
    const [low, high] = [userA, userB].sort();
    return database<PairRound[]>`
        select series.id as series_id, series.paused_at is not null as paused, series.owner_id,
            series.name as series_name, series.visibility::text as visibility, series.recurring,
            series.current_fight_id, fight.id, fight.state::text as state,
            to_char(fight.starts_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as starts_at,
            to_char(fight.ends_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as ends_at,
            fight.time_zone, fight.name, fight.friends, fight.host_id,
            (select count(*)::int from public.fight_members as member
                where member.fight_id = fight.id and member.state = 'accepted') as accepted,
            (select count(*)::int from public.fight_members as member
                where member.fight_id = fight.id and member.state = 'accepted'
                    and member.selected_source_id is not null) as sourced
        from public.fight_series as series
        join public.fights as fight on fight.series_id = series.id
        where series.friend_low = ${low} and series.friend_high = ${high}
        order by fight.starts_at
    `;
}

async function uploadSteps(userId: string, steps: Record<string, number>, phoneZone: string, collectedAt = new Date(Date.now() - 1_000)) {
    await receiveHealthKitActivity(userId, healthKitActivityBatchSchema.parse({
        collected_at: collectedAt.toISOString(),
        time_zone: phoneZone,
        totals: Object.entries(steps).map(([day, value]) => {
            const bounds = civilDayBounds(day, phoneZone);
            return {
                metric: "steps",
                day,
                starts_at: bounds.startsAt.toISOString(),
                ends_at: new Date(Math.min(bounds.endsAt.getTime(), collectedAt.getTime())).toISOString(),
                value,
                unit: "steps",
            };
        }),
    }), database);
}

async function memberScore(fightId: string, userId: string) {
    const [member] = await database<{ value: number | null; complete: boolean }[]>`
        select current_value::float8 as value, final_steps_complete as complete from public.fight_members
        where fight_id = ${fightId} and user_id = ${userId}
    `;
    return member;
}

test("accepting a friend starts one round from the 1st, scored from Steps already stored", async (t) => {
    const users = await createUsers(2);
    const [requester, recipient] = users;
    t.after(() => removeUsers(users));
    const month = calendarMonthWindow(new Date(), FRIEND_FIGHT_TIME_ZONE);
    const today = civilDayStamp(new Date(), FRIEND_FIGHT_TIME_ZONE);
    const beforeMonth = civilDayStamp(new Date(Date.parse(month.startsAt) - 3_600_000), FRIEND_FIGHT_TIME_ZONE);
    await uploadSteps(requester, { [beforeMonth]: 9_999, [today]: 4_000 }, FRIEND_FIGHT_TIME_ZONE);

    await changeFriendship(requester, recipient, "request", database);
    assert.equal((await pairRounds(requester, recipient)).length, 0, "a pending request has no fight");
    await changeFriendship(recipient, requester, "accept", database);

    const rounds = await pairRounds(requester, recipient);
    assert.equal(rounds.length, 1);
    const [round] = rounds;
    assert.deepEqual(
        [round.starts_at, round.ends_at, round.time_zone, round.name, round.friends, round.host_id, round.state],
        [month.startsAt, month.endsAt, FRIEND_FIGHT_TIME_ZONE, FRIEND_FIGHT_NAME, true, null, "live"],
    );
    assert.deepEqual(
        [round.owner_id, round.series_name, round.visibility, round.recurring, round.paused, round.current_fight_id],
        [requester, FRIEND_FIGHT_NAME, "invite_only", true, false, round.id],
    );
    assert.deepEqual([round.accepted, round.sourced], [2, 1], "a friend who never synced joins without a source");
    const [made] = await database<{ sources: number }[]>`
        select count(*)::int as sources from public.data_sources where user_id = ${recipient}
    `;
    assert.equal(made.sources, 0, "no Apple Health connection is made up for them");
    const [seriesMembers] = await database<{ accepted: number }[]>`
        select count(*)::int as accepted from public.fight_series_members
        where series_id = ${round.series_id} and state = 'accepted'
    `;
    assert.equal(seriesMembers.accepted, 2);
    assert.equal((await memberScore(round.id, requester)).value, 4_000, "only dates inside the month count");
    await uploadSteps(recipient, { [today]: 2_500 }, FRIEND_FIGHT_TIME_ZONE);
    assert.equal((await memberScore(round.id, recipient)).value, 2_500, "their first day Steps attach their source");

    for (const user of users) {
        const context = await getProviderUploadContext(user, database);
        assert.ok(!context.fight_windows.some((window) => window.fight_id === round.id), "no window total is asked for");
    }
});

test("refresh backfills friendships from before the feature, once, and fills a missing month", async (t) => {
    const users = await createUsers(3);
    const [first, second, third] = users;
    t.after(() => removeUsers(users));
    for (const other of [second, third]) {
        const [low, high] = [first, other].sort();
        await database`
            insert into private.profile_friendships (user_low, user_high, requester_id, state, accepted_at)
            values (${low}, ${high}, ${other}, 'accepted', now())
        `;
    }

    await ensureFriendFights(database, first);
    await ensureFriendFights(database, first);
    await ensureFriendFights(database, second);
    const rounds = [await pairRounds(first, second), await pairRounds(first, third)];
    assert.deepEqual(rounds.map((pair) => pair.length), [1, 1], "one round per friendship, however often refresh runs");
    assert.deepEqual(rounds.map((pair) => pair[0].owner_id), [second, third], "the requester owns the series");
    await database`
        update public.fights set starts_at = starts_at + interval '5 hours', ends_at = ends_at + interval '5 hours'
        where id = ${rounds[1][0].id}
    `;
    await ensureFriendFights(database, third);
    assert.equal((await pairRounds(first, third)).length, 1, "a live round in another zone is not doubled");

    const month = calendarMonthWindow(new Date(), FRIEND_FIGHT_TIME_ZONE);
    const lastMonth = calendarMonthWindow(new Date(Date.parse(month.startsAt) - 1), FRIEND_FIGHT_TIME_ZONE);
    await database`
        update public.fights set starts_at = ${lastMonth.startsAt}, ends_at = ${lastMonth.endsAt},
            state = 'awaiting_final_sync'
        where id = ${rounds[0][0].id}
    `;
    await ensureFriendFights(database, second);
    const filled = await pairRounds(first, second);
    assert.deepEqual(filled.map((round) => [round.starts_at, round.state]),
        [[lastMonth.startsAt, "awaiting_final_sync"], [month.startsAt, "live"]]);
    assert.equal(filled[1].current_fight_id, filled[1].id, "the new month becomes the current round");
    assert.deepEqual([filled[1].accepted, filled[1].sourced], [2, 0]);
});

test("removing a friend cancels the round and pauses the series; refriending resumes the same series", async (t) => {
    const users = await createUsers(2);
    const [first, second] = users;
    t.after(() => removeUsers(users));
    await befriend(first, second);
    const [created] = await pairRounds(first, second);

    await changeFriendship(second, first, "remove", database);
    const [ended] = await pairRounds(first, second);
    assert.deepEqual([ended.id, ended.state, ended.paused], [created.id, "cancelled", true], "nothing is deleted");
    await ensureFriendFights(database, first);
    assert.equal((await pairRounds(first, second))[0].state, "cancelled", "refresh does not restart it");

    await befriend(second, first);
    const resumed = await pairRounds(first, second);
    assert.equal(resumed.length, 1);
    assert.deepEqual(
        [resumed[0].series_id, resumed[0].id, resumed[0].state, resumed[0].paused, resumed[0].accepted],
        [created.series_id, created.id, "live", false, 2],
    );

    // An accept whose fight step failed: refresh resumes it, because they refriended after the pause.
    await changeFriendship(first, second, "remove", database);
    const [low, high] = [first, second].sort();
    await database`
        insert into private.profile_friendships (user_low, user_high, requester_id, state, accepted_at)
        values (${low}, ${high}, ${first}, 'accepted', now())
    `;
    await ensureFriendFights(database, second);
    const healed = await pairRounds(first, second);
    assert.deepEqual(healed.map((round) => [round.id, round.state, round.paused]), [[created.id, "live", false]]);
});

test("leaving a friend round pauses it for good, without a successor", async (t) => {
    const users = await createUsers(2);
    const [owner, friend] = users;
    t.after(() => removeUsers(users));
    await befriend(owner, friend);
    const [round] = await pairRounds(owner, friend);

    await departFightMemberships(owner, round.id, owner, database);
    await ensureFriendFights(database, owner);
    await ensureFriendFights(database, friend);
    const [left] = await pairRounds(owner, friend);
    assert.deepEqual([left.paused, left.state, left.accepted, left.owner_id], [true, "live", 1, owner]);

    const ended = await mintNextRecurringFight(round.id, new Date(Date.parse(round.ends_at) + 1_000), database);
    assert.equal(ended, null, "a paused friend series has no next month");
});

test("every block ends the friend round and refresh keeps it ended", async (t) => {
    const users = await createUsers(6);
    t.after(() => removeUsers(users));
    const blocks = [
        () => blockProfile(users[0], users[1], database),
        () => blockFeedAuthor(users[2], users[3], database),
        () => blockFeedbackAuthor(users[5], users[4], database),
    ];
    for (const [index, block] of blocks.entries()) {
        const [blocker, blocked] = [users[index * 2], users[index * 2 + 1]];
        await befriend(blocker, blocked);
        await block();
        await ensureFriendFights(database, blocker);
        await ensureFriendFights(database, blocked);
        const rounds = await pairRounds(blocker, blocked);
        assert.deepEqual(rounds.map((round) => [round.state, round.paused]), [["cancelled", true]], `block ${index}`);
    }
});

test("the next friend round runs to the end of the next calendar month", async (t) => {
    const users = await createUsers(2);
    const [first, second] = users;
    t.after(() => removeUsers(users));
    await befriend(first, second);
    const [round] = await pairRounds(first, second);

    const nextId = await mintNextRecurringFight(round.id, new Date(Date.parse(round.ends_at) + 1_000), database);
    assert.ok(nextId);
    const rounds = await pairRounds(first, second);
    const next = rounds.find((item) => item.id === nextId);
    assert.ok(next);
    const following = calendarMonthWindow(new Date(round.ends_at), FRIEND_FIGHT_TIME_ZONE);
    assert.deepEqual(
        [next.starts_at, next.ends_at, next.friends, next.name, next.accepted, next.sourced, next.current_fight_id],
        [round.ends_at, following.endsAt, true, FRIEND_FIGHT_NAME, 2, 0, nextId],
    );
    const [made] = await database<{ sources: number }[]>`
        select count(*)::int as sources from public.data_sources where user_id = any(${database.array(users)}::uuid[])
    `;
    assert.equal(made.sources, 0, "minting makes up no Apple Health connection either");
});

test("a friend's own app open closes their ended round and starts the next month", async (t) => {
    const users = await createUsers(2);
    const [first, second] = users;
    t.after(() => removeUsers(users));
    await befriend(first, second);
    const [round] = await pairRounds(first, second);
    const endedAt = new Date(Date.now() - 60_000).toISOString();
    await database`update public.fights set ends_at = ${endedAt} where id = ${round.id}`;

    await closeDueFightsForUser(second, admin, new Date(), database);
    const rounds = await pairRounds(first, second);
    assert.deepEqual(rounds.map((item) => [item.id === round.id, item.state]),
        [[true, "awaiting_final_sync"], [false, "live"]]);
    assert.equal(rounds[1].starts_at, new Date(endedAt).toISOString());
});

test("each friend is scored by their own local days and completes once their last day is", async (t) => {
    const users = await createUsers(2);
    const [east, west] = users;
    t.after(() => removeUsers(users));
    await befriend(east, west);
    const [round] = await pairRounds(east, west);
    const day = civilDayStamp(new Date(Date.now() - 2 * 86_400_000), FRIEND_FIGHT_TIME_ZONE);
    const dayBefore = civilDayStamp(new Date(Date.now() - 3 * 86_400_000), FRIEND_FIGHT_TIME_ZONE);
    const bounds = civilDayBounds(day, FRIEND_FIGHT_TIME_ZONE);
    await database`
        update public.fights set starts_at = ${bounds.startsAt.toISOString()}, ends_at = ${bounds.endsAt.toISOString()},
            state = 'awaiting_final_sync'
        where id = ${round.id}
    `;

    await uploadSteps(east, { [dayBefore]: 1_000, [day]: 6_000 }, "Pacific/Kiritimati");
    // Synced after the round's UTC end but before her own midnight: her last day is still running.
    await uploadSteps(west, { [day]: 2_000 }, "America/Los_Angeles", new Date(bounds.endsAt.getTime() + 3 * 3_600_000));
    assert.deepEqual(await memberScore(round.id, east), { value: 6_000, complete: true },
        "his local date counts, though most of it was the day before in UTC");
    assert.deepEqual(await memberScore(round.id, west), { value: 2_000, complete: false },
        "her local day is not over yet");

    await uploadSteps(west, { [day]: 7_500 }, "America/Los_Angeles");
    assert.deepEqual(await memberScore(round.id, west), { value: 7_500, complete: true });
    const [ranks] = await database<{ east: number; west: number }[]>`
        select max(rank) filter (where user_id = ${east}) as east, max(rank) filter (where user_id = ${west}) as west
        from public.fight_members where fight_id = ${round.id}
    `;
    assert.deepEqual(ranks, { east: 2, west: 1 });
});

test(
    "either friend may change the action, and nothing else; nobody joins or is invited",
    // NOTE: once direct access closes, every service-role fight update fails on allow_score_correction.
    { skip: env.SUPABASE_CLIENT_ACCESS_CLOSED && "service-role fight updates fail with direct access closed" },
    async (t) => {
        const users = await createUsers(3);
        const [owner, friend, stranger] = users;
        t.after(() => removeUsers(users));
        await befriend(owner, friend);
        const [round] = await pairRounds(owner, friend);

        await updateFight(friend, round.id, {
            name: "Renamed",
            actionText: "Buy the coffee",
            visibility: "joinable",
            recurring: false,
            endsAt: new Date(Date.now() + 86_400_000).toISOString(),
            inviteHandles: ["anyone"],
            removeUserIds: [owner],
        }, admin, new Date(), database);
        const [edited] = await database<{ name: string; action_text: string; ends_at: string; visibility: string; recurring: boolean }[]>`
            select fight.name, fight.action_text,
                to_char(fight.ends_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as ends_at,
                series.visibility::text as visibility, series.recurring
            from public.fights as fight join public.fight_series as series on series.id = fight.series_id
            where fight.id = ${round.id}
        `;
        assert.deepEqual(edited, {
            name: FRIEND_FIGHT_NAME, action_text: "Buy the coffee", ends_at: round.ends_at,
            visibility: "invite_only", recurring: true,
        });
        assert.equal((await pairRounds(owner, friend))[0].accepted, 2, "the pair stays together");
        await assert.rejects(updateFight(stranger, round.id, { actionText: "Nope" }, admin, new Date(), database),
            /Only the two friends/);

        const [{ join_code: joinCode }] = await database<{ join_code: string }[]>`
            select join_code from public.fight_series where id = ${round.series_id}
        `;
        await assert.rejects(createInvite(owner, round.id, "anyone", admin, database), /one on one/);
        await assert.rejects(cancelFight(owner, round.id, admin), /leave it or remove the friend/);
        await assert.rejects(joinFight(stranger, { code: joinCode, start: "now" }, null, admin, new Date(), database),
            /cannot be joined/);
    },
);

test("deleting an account cancels each friend round and keeps the series the friend owns", async (t) => {
    const users = await createUsers(3);
    const [leaving, staying, invited] = users;
    t.after(() => removeUsers(users));
    await befriend(staying, leaving);
    await befriend(leaving, invited);
    const [round] = await pairRounds(staying, leaving);
    const [owned] = await pairRounds(leaving, invited);

    await deleteAccount(leaving, database);
    const [kept] = await database<{
        state: string; series_id: string; paused: boolean; pair: boolean; members: string[]; series_members: string[];
    }[]>`
        select fight.state::text as state, fight.series_id, series.paused_at is not null as paused,
            series.friend_low is not null as pair,
            array(select user_id::text from public.fight_members where fight_id = fight.id) as members,
            array(select user_id::text from public.fight_series_members where series_id = series.id and state = 'accepted')
                as series_members
        from public.fights as fight join public.fight_series as series on series.id = fight.series_id
        where fight.id = ${round.id}
    `;
    assert.deepEqual(kept, {
        state: "cancelled", series_id: round.series_id, paused: true, pair: false,
        members: [staying], series_members: [staying],
    });
    const [gone] = await database<{ series: number; fights: number }[]>`
        select (select count(*)::int from public.fight_series where id = ${owned.series_id}) as series,
            (select count(*)::int from public.fights where id = ${owned.id}) as fights
    `;
    assert.deepEqual(gone, { series: 0, fights: 0 }, "what the account owned goes with it, as before");
});

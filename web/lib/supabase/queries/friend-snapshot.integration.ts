import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import postgres from "postgres";
import { APP_WIDE_JOIN_CODE, randomJoinCode } from "@/lib/domain/fights/join-code";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readFightSnapshot } from "./fight-snapshot-supabase-query";
import { listFriendSuggestions } from "./friend-suggestions-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());

const hour = 3_600_000;
const day = 24 * hour;

async function seedUsers(t: TestContext, count: number) {
    const users = Array.from({ length: count }, () => randomUUID());
    t.after(async () => {
        await database`delete from public.fights where owner_id = any(${database.array(users)}::uuid[])`;
        await database`delete from public.fight_series where owner_id = any(${database.array(users)}::uuid[])`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users (id) values (${id})`;
    return users;
}

async function seedFriendship(requester: string, other: string, state: "pending" | "accepted") {
    const [low, high] = [requester, other].sort();
    await database`
        insert into private.profile_friendships (user_low, user_high, requester_id, state, accepted_at)
        values (${low}, ${high}, ${requester}, ${state}, ${state === "accepted" ? new Date() : null})
    `;
}

async function seedSeries(
    owner: string,
    members: Array<[string, string]>,
    options: { pair?: boolean; joinCode?: string; suggested?: boolean } = {},
) {
    const [low, high] = members.map(([userId]) => userId).sort();
    const [series] = await database<{ id: string }[]>`
        insert into public.fight_series (owner_id, join_code, recurring, duration_seconds, name, time_zone,
            suggested, friend_low, friend_high)
        values (${owner}, ${options.joinCode ?? randomJoinCode()}, true, 2592000, 'Friends', 'UTC',
            ${options.suggested ?? false}, ${options.pair ? low : null}, ${options.pair ? high : null})
        returning id
    `;
    for (const [userId, state] of members) {
        await database`insert into public.fight_series_members (series_id, user_id, state) values (${series.id}, ${userId}, ${state})`;
    }
    return series.id;
}

async function seedFight(fight: {
    owner: string;
    members: Array<[string, string, number?]>;
    friends?: boolean;
    state?: string;
    endsAt?: Date;
    seriesId?: string;
    hostId?: string;
}) {
    const id = randomUUID();
    const endsAt = fight.endsAt ?? new Date(Date.now() + 20 * day);
    await database`
        insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy,
            friends, series_id, host_id)
        values (${id}, ${fight.owner}, 'Friends', ${fight.state ?? "live"}, ${new Date(endsAt.getTime() - 30 * day)},
            ${endsAt}, 'UTC', 'highest_total', 'shared', ${fight.friends ?? false}, ${fight.seriesId ?? null},
            ${fight.hostId ?? null})
    `;
    for (const [userId, state, steps] of fight.members) {
        await database`
            insert into public.fight_members (fight_id, user_id, state, accepted_at)
            values (${id}, ${userId}, ${state}, ${state === "accepted" ? new Date() : null})
        `;
        if (steps !== undefined) {
            await database`update public.fight_members set current_value = ${steps} where fight_id = ${id} and user_id = ${userId}`;
        }
    }
    return id;
}

test("friends mode returns this month's rounds and, for a week, each pair's last round, only for current friends", async (t) => {
    const users = await seedUsers(t, 10);
    const [me, ana, ben, dana, cleo, stranger, requester, invitee, blockedRequester, gone] = users;
    for (const friend of [ana, ben, dana]) await seedFriendship(friend, me, "accepted");
    await seedFriendship(ana, ben, "accepted");
    await seedFriendship(requester, me, "pending");
    await seedFriendship(me, invitee, "pending");
    await seedFriendship(blockedRequester, me, "pending");
    await database`insert into private.feedback_blocks (blocker_id, blocked_id) values (${me}, ${blockedRequester})`;
    await seedFriendship(gone, me, "pending");
    await database`update public.profiles set deleted_at = now() where user_id = ${gone}`;

    const now = Date.now();
    const pair = (friend: string) => seedSeries(me, [[me, "accepted"], [friend, "accepted"]], { pair: true });
    const [anaSeries, benSeries, danaSeries, cleoSeries] = [await pair(ana), await pair(ben), await pair(dana), await pair(cleo)];

    // The 1st: last month's round waits for its final sync while this month's has started.
    const anaNow = await seedFight({ owner: me, friends: true, seriesId: anaSeries, members: [[me, "accepted", 5_000], [ana, "accepted", 3_000]] });
    const anaLast = await seedFight({
        owner: me, friends: true, seriesId: anaSeries, state: "awaiting_final_sync", endsAt: new Date(now - 2 * hour),
        members: [[me, "accepted", 9_000], [ana, "accepted", 1_000]],
    });
    await seedFight({ owner: me, friends: true, seriesId: anaSeries, state: "cancelled", endsAt: new Date(now - hour), members: [[me, "accepted"], [ana, "accepted"]] });
    await seedFight({ owner: me, friends: true, seriesId: anaSeries, state: "final", endsAt: new Date(now - 31 * day), members: [[me, "accepted"], [ana, "accepted"]] });
    const benNow = await seedFight({ owner: ben, friends: true, seriesId: benSeries, members: [[me, "accepted", 1_000], [ben, "accepted", 2_000]] });
    const benLast = await seedFight({
        owner: ben, friends: true, seriesId: benSeries, state: "final", endsAt: new Date(now - 6 * day - 20 * hour),
        members: [[me, "accepted"], [ben, "accepted"]],
    });
    await seedFight({
        owner: dana, friends: true, seriesId: danaSeries, state: "final", endsAt: new Date(now - 7 * day - hour),
        members: [[me, "accepted"], [dana, "accepted"]],
    });
    await seedFight({ owner: me, friends: true, seriesId: cleoSeries, members: [[me, "accepted", 8_000], [cleo, "accepted", 1]] });
    await seedFight({
        owner: me, friends: true, seriesId: cleoSeries, state: "awaiting_final_sync", endsAt: new Date(now - 3 * hour),
        members: [[me, "accepted"], [cleo, "accepted"]],
    });
    await seedFight({ owner: ana, friends: true, members: [[ana, "accepted", 100], [ben, "accepted"]] });
    const ordinary = await seedFight({ owner: me, members: [[me, "accepted", 700], [stranger, "accepted", 600]] });

    const home = await readFightSnapshot(me, "UTC", database);
    assert.deepEqual(home.fights.map((fight) => fight.id), [ordinary]);
    assert.deepEqual(home.fights.map((fight) => fight.friends), [false]);
    assert.ok(home.members.every((member) => member.fight_id === ordinary));
    assert.deepEqual(home.friends, { rounds: 2, leading: 1, requests: 1 },
        "only this month's rounds with current friends count; blocked, deleted and outgoing requests do not");
    assert.equal(home.hosted, null);

    const hosted = await readFightSnapshot(me, "UTC", database, true);
    assert.deepEqual(hosted.fights, [], "the hosted flag never returns friend rounds");

    const friends = await readFightSnapshot(me, "UTC", database, false, true);
    assert.deepEqual(friends.fights.map((fight) => fight.id).sort(), [anaNow, anaLast, benNow, benLast].sort(),
        "one current and at most one last round per pair: no cancelled, older, week-old or unfriended rounds");
    assert.ok(friends.fights.every((fight) => fight.friends === true));
    assert.deepEqual(
        friends.fights.filter((fight) => Date.parse(fight.ends_at) > now).map((fight) => fight.id).sort(),
        [anaNow, benNow].sort(),
        "on the 1st each friend appears once in this month and once in last month",
    );
    assert.deepEqual(new Set(friends.members.map((member) => member.fight_id)), new Set([anaNow, anaLast, benNow, benLast]));
    assert.deepEqual(friends.friends, home.friends);

    const anaHome = await readFightSnapshot(ana, "UTC", database);
    assert.deepEqual(anaHome.fights, []);
    assert.deepEqual(anaHome.friends, { rounds: 2, leading: 1, requests: 0 });

    await database`update public.fight_members set state = 'withdrawn' where fight_id = ${benNow} and user_id = ${ben}`;
    const afterLeaving = await readFightSnapshot(me, "UTC", database, false, true);
    assert.deepEqual(afterLeaving.fights.map((fight) => fight.id).sort(), [anaNow, anaLast, benLast].sort(),
        "a round where one friend no longer races is not current");
    assert.deepEqual(afterLeaving.friends, { rounds: 1, leading: 1, requests: 1 });

    const [low, high] = [me, ana].sort();
    await database`delete from private.profile_friendships where user_low = ${low} and user_high = ${high}`;
    const afterUnfriending = await readFightSnapshot(me, "UTC", database, false, true);
    assert.deepEqual(afterUnfriending.fights.map((fight) => fight.id), [benLast],
        "an unfriended pair's rounds disappear at once, even before they are cancelled");
    assert.deepEqual(afterUnfriending.friends, { rounds: 0, leading: 0, requests: 1 });

    const strangerHome = await readFightSnapshot(stranger, "UTC", database);
    assert.deepEqual(strangerHome.friends, { rounds: 0, leading: 0, requests: 0 }, "the card is present with no friends");
});

test("suggestions rank real past opponents and leave out friends, requests, blocks, deletions, and automatic Fights", async (t) => {
    const users = await seedUsers(t, 17);
    const [me, top, recent, older, sitOut, friend, outgoing, incoming, blockedByMe, blockedMe, deleted, founder,
        exFriend, leftSeries, appWide, suggested, stillInSeries] = users;
    await seedFriendship(me, friend, "accepted");
    await seedFriendship(me, outgoing, "pending");
    await seedFriendship(incoming, me, "pending");
    await database`insert into private.feedback_blocks (blocker_id, blocked_id) values (${me}, ${blockedByMe})`;
    await database`insert into private.profile_blocks (blocker_id, blocked_id) values (${blockedMe}, ${me})`;
    await database`update public.profiles set deleted_at = now() where user_id = ${deleted}`;

    const now = Date.now();
    const excluded = [friend, outgoing, incoming, blockedByMe, blockedMe, deleted];
    for (const daysAgo of [80, 70, 60]) {
        await seedFight({
            owner: me, endsAt: new Date(now - daysAgo * day),
            members: [[me, "accepted"], [top, "accepted"], ...excluded.map((id): [string, string] => [id, "accepted"])],
        });
    }
    for (const daysAgo of [90, 10]) {
        await seedFight({ owner: recent, endsAt: new Date(now - daysAgo * day), members: [[me, "accepted"], [recent, "accepted"]] });
    }
    for (const daysAgo of [90, 40]) {
        await seedFight({ owner: older, endsAt: new Date(now - daysAgo * day), members: [[me, "accepted"], [older, "deferred"]] });
    }
    await seedFight({ owner: sitOut, members: [[me, "deferred"], [sitOut, "accepted"]] });
    await seedFight({ owner: me, hostId: founder, members: [[me, "accepted"], [founder, "accepted"]] });
    const declinedFight = await seedFight({ owner: me, members: [[me, "accepted"], [founder, "invited"]] });
    await database`update public.fight_members set state = 'declined' where fight_id = ${declinedFight} and user_id = ${founder}`;

    const exFriendSeries = await seedSeries(me, [[me, "accepted"], [exFriend, "accepted"]], { pair: true });
    await seedFight({ owner: me, friends: true, state: "final", seriesId: exFriendSeries, endsAt: new Date(now - 20 * day),
        members: [[me, "accepted"], [exFriend, "accepted"]] });
    const repeating = await seedSeries(me, [[me, "accepted"], [leftSeries, "withdrawn"], [stillInSeries, "accepted"]]);
    await seedFight({ owner: me, state: "final", seriesId: repeating, endsAt: new Date(now - 20 * day),
        members: [[me, "accepted"], [leftSeries, "accepted"], [stillInSeries, "accepted"]] });
    await database`
        insert into public.fight_series (owner_id, join_code, duration_seconds, name, time_zone)
        values (${appWide}, ${APP_WIDE_JOIN_CODE}, 2592000, 'Everyone', 'UTC')
        on conflict do nothing
    `;
    const [{ id: appWideSeries }] = await database<{ id: string }[]>`
        select id from public.fight_series where join_code = ${APP_WIDE_JOIN_CODE}
    `;
    await seedFight({ owner: appWide, seriesId: appWideSeries, members: [[me, "accepted"], [appWide, "accepted"]] });
    const suggestedSeries = await seedSeries(suggested, [[me, "accepted"], [suggested, "accepted"]], { suggested: true });
    await seedFight({ owner: suggested, seriesId: suggestedSeries, members: [[me, "accepted"], [suggested, "accepted"]] });

    const suggestions = await listFriendSuggestions(me, database);
    assert.deepEqual(
        suggestions.people.map((person) => [person.user_id, person.shared_fights]),
        [[top, 3], [recent, 2], [older, 2], [sitOut, 1], [stillInSeries, 1]],
        "most shared Fights first, then the most recent shared Fight",
    );
    const [profile] = await database<{ handle: string; display_name: string }[]>`
        select handle, display_name from public.profiles where user_id = ${top}
    `;
    assert.deepEqual(suggestions.people[0], {
        user_id: top, handle: profile.handle, display_name: profile.display_name,
        companion_id: null, avatar_url: null, shared_fights: 3,
    });
    assert.deepEqual((await listFriendSuggestions(founder, database)).people, [], "a founder round alone suggests nobody");
    assert.deepEqual((await listFriendSuggestions(exFriend, database)).people, [], "a friend round never brings an ex-friend back");
});

test("suggestions return at most ten people", async (t) => {
    const [me, ...others] = await seedUsers(t, 12);
    await seedFight({ owner: me, members: [[me, "accepted"], ...others.map((id): [string, string] => [id, "accepted"])] });
    assert.equal((await listFriendSuggestions(me, database)).people.length, 10);
});

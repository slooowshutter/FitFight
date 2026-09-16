import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { ApiError } from "@/lib/http";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { defaultProfileSettings, profilePageQuerySchema } from "@/lib/types/profiles/shared-profile";
import { friendsQuerySchema } from "@/lib/types/friends/friendship";
import { readSharedProfile, readProfileHistory, readProfileSettings, updateProfileSettings } from "./shared-profiles-supabase-query";
import { blockProfile, changeFriendship, listProfileFriends } from "./profile-friends-supabase-query";
import { pruneProfileEvents, recordProfileView } from "./profile-events-supabase-query";
import { departFightMemberships } from "./membership-departure-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());

test("private profiles require mutual acceptance and enforce sharing on every read", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [viewer, target, stranger] = users;
    t.after(async () => { await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`; });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    assert.deepEqual(await readProfileSettings(target, database), defaultProfileSettings);
    assert.equal((await readSharedProfile(viewer, target, undefined, database)).access, "private");
    await updateProfileSettings(target, { competitive: true }, database);
    await database`insert into public.friendships(requester_id, addressee_id, state) values (${viewer}, ${target}, 'accepted')`;
    assert.equal((await readSharedProfile(viewer, target, undefined, database)).record, null);

    await assert.rejects(changeFriendship(viewer, viewer, "request", database), (error: unknown) => error instanceof ApiError && error.status === 400);
    const requests = await Promise.all([
        changeFriendship(viewer, target, "request", database), changeFriendship(target, viewer, "request", database),
    ]);
    assert.deepEqual(requests.map((response) => response.friendship).sort(), ["incoming", "outgoing"]);
    const first = requests[0].friendship === "outgoing" ? viewer : target;
    const recipient = first === viewer ? target : viewer;
    await assert.rejects(changeFriendship(first, recipient, "accept", database), (error: unknown) => error instanceof ApiError && error.status === 403);
    await changeFriendship(recipient, first, "accept", database);
    await changeFriendship(recipient, first, "accept", database);
    const shared = await readSharedProfile(viewer, target, undefined, database);
    assert.equal(shared.access, "shared");
    assert.equal(shared.friendship, "friends");
    assert.equal(shared.record?.played, 0);
    assert.equal(shared.activity, null);
    assert.equal("referral_code" in shared.identity, false);
    assert.equal("companion_prompt" in shared.identity, false);
    const friends = await listProfileFriends(viewer, friendsQuerySchema.parse({}), database);
    assert.equal(friends.people.length, 1);
    assert.equal(friends.people[0].user_id, target);

    for (const competitive of [false, true]) {
        for (const audience of ["private", "public"] as const) {
            await updateProfileSettings(target, { competitive, audience }, database);
            assert.equal((await readSharedProfile(stranger, target, undefined, database)).record !== null, competitive && audience === "public");
            assert.equal((await readSharedProfile(viewer, target, undefined, database)).record !== null, competitive);
        }
    }
    await updateProfileSettings(target, { activity_audience: "public", activity_days: 30 }, database);
    assert.equal((await readSharedProfile(stranger, target, undefined, database)).activity?.days, 30);
    await updateProfileSettings(target, { audience: "private" }, database);
    assert.equal((await readProfileSettings(target, database)).activity_audience, "off");
    await assert.rejects(updateProfileSettings(target, { activity_audience: "public" }, database));
    await assert.rejects(updateProfileSettings(target, { artwork_allowed: true }, database));
    await changeFriendship(viewer, target, "remove", database);
    assert.equal((await readSharedProfile(viewer, target, undefined, database)).record, null);
    await changeFriendship(viewer, target, "request", database);
    await blockProfile(target, viewer, database);
    await assert.rejects(changeFriendship(target, viewer, "accept", database));
    await assert.rejects(readSharedProfile(viewer, target, undefined, database));
    await assert.rejects(readSharedProfile(target, viewer, undefined, database));
    assert.equal((await listProfileFriends(viewer, friendsQuerySchema.parse({ kind: "outgoing" }), database)).people.length, 0);
});

test("new profile tables reject mobile reads and writes; deletion cascades both sides", async (t) => {
    const users = [randomUUID(), randomUUID()];
    t.after(async () => { await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`; });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    await changeFriendship(users[0], users[1], "request", database);
    for (const role of ["anon", "authenticated"] as const) {
        await assert.rejects(database.begin(async (sql) => {
            await sql`set local role ${sql.unsafe(role)}`;
            await sql`select * from private.profile_friendships`;
        }));
        await assert.rejects(database.begin(async (sql) => {
            await sql`set local role ${sql.unsafe(role)}`;
            await sql`insert into private.profile_settings(user_id, competitive, audience) values (${users[0]}, true, 'public')`;
        }));
    }
    await database`delete from auth.users where id = ${users[1]}`;
    const [count] = await database`select count(*)::int n from private.profile_friendships where user_low = ${users[0]} or user_high = ${users[0]}`;
    assert.equal(count.n, 0);
    await assert.rejects(readSharedProfile(users[0], users[1], undefined, database));
});

test("withdrawal is recorded atomically and later visibility edits never reclassify a result", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [owner, opponent, stranger] = users;
    const fightId = randomUUID();
    const seriesId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from public.fight_series where id = ${seriesId}`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    await database`insert into public.fight_series(id, owner_id, visibility, duration_seconds, name, time_zone, join_code)
        values (${seriesId}, ${owner}, 'invite_only', 259200, 'Private title', 'UTC', ${randomJoinCode()})`;
    await database`insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, series_id)
        values (${fightId}, ${owner}, 'Private title', 'live', now() - interval '1 hour', now() + interval '1 hour', 'UTC', 'highest_total', 'shared', ${seriesId})`;
    await database`update public.fight_series set current_fight_id = ${fightId} where id = ${seriesId}`;
    for (const userId of [owner, opponent]) {
        await database`insert into public.fight_members(fight_id, user_id, state, accepted_at) values (${fightId}, ${userId}, 'accepted', now())`;
    }
    await updateProfileSettings(owner, { competitive: true, audience: "public" }, database);
    assert.equal((await readSharedProfile(opponent, owner, undefined, database)).access, "shared");
    await departFightMemberships(opponent, fightId, opponent, database);
    await database.begin(async (sql) => {
        await sql`select id from public.fights where id = ${fightId} for update`;
        await sql`update public.fight_members set rank = 1, current_value = 1000, final_steps_complete = true where fight_id = ${fightId} and user_id = ${owner}`;
        await sql`update public.fights set state = 'final' where id = ${fightId}`;
    });
    const own = await readSharedProfile(opponent, opponent, undefined, database);
    assert.equal(own.record?.played, 1);
    assert.equal(own.record?.wins, 0);
    const publicView = await readSharedProfile(stranger, owner, undefined, database);
    assert.equal(publicView.record?.categories.private.wins, 1);
    await database`update public.fight_series set visibility = 'joinable' where id = ${seriesId}`;
    assert.equal((await readSharedProfile(stranger, owner, undefined, database)).record?.categories.private.wins, 1);
    const history = await readProfileHistory(stranger, owner, profilePageQuerySchema.parse({}), database);
    assert.equal(history.results[0].fight_id, null);
    assert.equal(history.results[0].name, null);
    assert.equal(history.results[0].placement, 1);
    assert.equal(history.results[0].field_size, 2);
    await database`update public.fight_members set state = 'withdrawn' where fight_id = ${fightId} and user_id = ${owner}`;
    assert.equal((await readSharedProfile(owner, owner, undefined, database)).record?.wins, 1);
});

test("view replay, rolling qualification, privacy locks, and inactive-user retention", async (t) => {
    const users = [randomUUID(), randomUUID()];
    const [viewer, target] = users;
    process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED = "true";
    t.after(async () => {
        delete process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    const event = { event_id: randomUUID(), source: "friends" as const };
    assert.equal((await recordProfileView(viewer, viewer, event, database)).recorded, false);
    assert.equal((await recordProfileView(viewer, target, event, database)).recorded, false);
    await updateProfileSettings(target, { audience: "public" }, database);
    await Promise.all([recordProfileView(viewer, target, event, database), recordProfileView(viewer, target, event, database)]);
    await recordProfileView(viewer, target, { ...event, event_id: randomUUID() }, database);
    const [count] = await database`select count(*)::int total, count(*) filter (where qualifying)::int qualified from private.profile_events where actor_id = ${viewer}`;
    assert.equal(count.total, 2);
    assert.equal(count.qualified, 1);
    await database`update private.profile_events set created_at = now() - interval '31 minutes' where actor_id = ${viewer}`;
    await recordProfileView(viewer, target, { ...event, event_id: randomUUID() }, database);
    const [qualified] = await database`select count(*)::int n from private.profile_events where actor_id = ${viewer} and qualifying`;
    assert.equal(qualified.n, 2);
    await database`update private.profile_events set created_at = now() - interval '31 days' where actor_id = ${viewer}`;
    await pruneProfileEvents(database);
    const [remaining] = await database`select count(*)::int n from private.profile_events where actor_id = ${viewer}`;
    assert.equal(remaining.n, 0);
});

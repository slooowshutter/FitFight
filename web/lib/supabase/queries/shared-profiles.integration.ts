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
import { deleteAccount } from "./delete-account-supabase-query";
import { departFightMemberships } from "./membership-departure-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SERVICE_ROLE_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());

test("private history IDs and cursors cannot correlate participants across profiles", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [owner, opponent, stranger] = users;
    const fightIds = [randomUUID(), randomUUID()];
    t.after(async () => {
        await database`delete from public.fights where owner_id = ${owner}`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    for (const fightId of fightIds) {
        await database`insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
            values (${fightId}, ${owner}, 'Private pair', 'live', now() - interval '1 hour', now() + interval '1 hour', 'UTC', 'highest_total', 'shared')`;
        for (const userId of [owner, opponent]) {
            await database`insert into public.fight_members(fight_id, user_id, state, accepted_at)
                values (${fightId}, ${userId}, 'accepted', now())`;
        }
        await database`update public.fight_members set rank = 1, current_value = 1000, final_steps_complete = true where fight_id = ${fightId}`;
        await database`update public.fights set state = 'final' where id = ${fightId}`;
    }
    for (const userId of [owner, opponent]) await updateProfileSettings(userId, { competitive: true, audience: "public" }, database);

    const query = profilePageQuerySchema.parse({ limit: 1 });
    const first = await readProfileHistory(stranger, owner, query, database);
    const other = await readProfileHistory(stranger, opponent, query, database);
    assert.equal(first.results[0].fight_id, null);
    assert.equal(first.results[0].name, null);
    assert.equal(first.results[0].field_size, 2);
    assert.notEqual(first.results[0].id, other.results[0].id);
    assert.ok(first.next_cursor && other.next_cursor);
    assert.equal(fightIds.includes(first.results[0].id), false);
    assert.equal(fightIds.includes(first.next_cursor), false);
    assert.notEqual(first.next_cursor, other.next_cursor);
    assert.deepEqual(await readProfileHistory(stranger, owner, query, database), first);
    const next = await readProfileHistory(stranger, owner, { ...query, cursor: first.next_cursor }, database);
    assert.equal(next.results.length, 1);
    assert.notEqual(next.results[0].id, first.results[0].id);
    assert.equal(next.next_cursor, null);
    for (const cursor of [other.next_cursor, fightIds[0]]) {
        await assert.rejects(readProfileHistory(stranger, owner, { ...query, cursor }, database),
            (error: unknown) => error instanceof ApiError && error.status === 400);
    }
    const own = await readProfileHistory(owner, owner, query, database);
    assert.equal(own.results[0].id, first.results[0].id);
    assert.ok(own.results[0].fight_id && fightIds.includes(own.results[0].fight_id));
    assert.equal(own.results[0].name, "Private pair");
});

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
        await sql`update public.fight_members set rank = 1, current_value = 1000, final_value = 1000, final_steps_complete = true, finalized_at = now() where fight_id = ${fightId} and user_id = ${owner}`;
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

test("account deletion preserves a frozen group draw and cannot create a duel", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [owner, opponent, departing] = users;
    const fightId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    await database`insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${owner}, 'Group draw', 'live', now() - interval '1 hour', now() + interval '1 hour', 'UTC', 'highest_total', 'shared')`;
    for (const id of users) {
        await database`insert into public.fight_members(fight_id, user_id, state, accepted_at) values (${fightId}, ${id}, 'accepted', now())`;
    }
    await database`update public.fight_members set current_value = case when user_id = ${opponent} then 500 else 1000 end,
        rank = case when user_id = ${opponent} then 3 else 1 end, final_steps_complete = true where fight_id = ${fightId}`;
    await database`update public.fights set state = 'final' where id = ${fightId}`;
    await updateProfileSettings(owner, { competitive: true, audience: "public" }, database);
    assert.equal((await readSharedProfile(owner, owner, undefined, database)).record?.wins, 0);
    await deleteAccount(departing, database);
    const afterDeletion = await readSharedProfile(opponent, owner, undefined, database);
    assert.equal(afterDeletion.record?.played, 1);
    assert.equal(afterDeletion.record?.wins, 0);
    assert.equal(afterDeletion.rivalry?.wins, 0);
    assert.equal(afterDeletion.rivalry?.losses, 0);
    assert.equal(afterDeletion.rivalry?.draws, 0);
    const history = await readProfileHistory(owner, owner, profilePageQuerySchema.parse({}), database);
    assert.equal(history.results[0].field_size, 3);
    assert.equal(history.results[0].result, "draw");
    const [erased] = await database`select count(*)::int n from private.fight_participation_records where user_id = ${departing}`;
    assert.equal(erased.n, 0);
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
    const [archived] = await database`select events::int, qualifying::int from private.profile_event_totals where kind = 'view' and source = 'friends'`;
    assert.ok(archived.events >= 3);
    assert.ok(archived.qualifying >= 2);
});

test("only active accepted opponents see private records, with independent bounded activity", async (t) => {
    const users = Array.from({ length: 5 }, () => randomUUID());
    const [owner, opponent, invited, deferred, stranger] = users;
    const fightId = randomUUID();
    const sourceId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    await database`insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${owner}, 'Opponent access', 'live', now() - interval '1 hour', now() + interval '1 day', 'UTC', 'highest_total', 'shared')`;
    for (const [id, state] of [[owner, "accepted"], [opponent, "accepted"], [invited, "invited"], [deferred, "deferred"]]) {
        await database`insert into public.fight_members(fight_id, user_id, state) values (${fightId}, ${id}, ${state})`;
    }
    await database`insert into public.data_sources(id, user_id, provider, source_label, connection_route) values (${sourceId}, ${owner}, 'apple_health', 'Apple Health', 'healthkit')`;
    await database`insert into public.metric_days(user_id, source_id, metric, day, value, time_zone, unit, input_hash, normalization_version, calculation_version)
        select ${owner}, ${sourceId}, 'steps', current_date - day, 1000, 'UTC', 'steps', repeat('0', 64), 1, 1 from generate_series(0, 40) day`;
    await updateProfileSettings(owner, { competitive: true, activity_audience: "opponents", activity_days: 7 }, database);
    const shared = await readSharedProfile(opponent, owner, undefined, database);
    assert.equal(shared.access, "shared");
    assert.equal(shared.activity?.values.length, 7);
    assert.equal(shared.activity.values[0].time_zone, "UTC");
    for (const id of [invited, deferred, stranger]) {
        const profile = await readSharedProfile(id, owner, undefined, database);
        assert.equal(profile.record, null);
        assert.equal(profile.activity, null);
    }
    await updateProfileSettings(owner, { activity_days: 30 }, database);
    assert.equal((await readSharedProfile(opponent, owner, undefined, database)).activity?.values.length, 30);
    await database`update public.fights set starts_at = now() + interval '1 hour' where id = ${fightId}`;
    assert.equal((await readSharedProfile(opponent, owner, undefined, database)).record, null);
    await database`update public.fights set starts_at = now() - interval '1 day', ends_at = now() - interval '1 hour', state = 'final' where id = ${fightId}`;
    assert.equal((await readSharedProfile(opponent, owner, undefined, database)).record, null);
    assert.equal((await readProfileHistory(opponent, owner, profilePageQuerySchema.parse({ shared: "true" }), database)).results.length, 1);
});

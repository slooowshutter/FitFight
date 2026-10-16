import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { setTimeout } from "node:timers/promises";
import postgres from "postgres";
import { notificationDeliveryRowSchema } from "@/lib/types/notifications/notification-delivery";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readNotificationContent } from "./notification-content-supabase-query";
import { enqueueFriendsResultsNotifications } from "./notification-intents-supabase-query";
import { processNotificationOutbox } from "./process-notification-outbox-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";
import { enqueueScheduledNotifications } from "./scheduled-notifications-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 4 });
after(() => database.end());

const startsAt = "2026-10-01T00:00:00.000Z";
const endsAt = "2026-11-01T00:00:00.000Z";

test("friend rounds batch their round-end pushes while a normal fight keeps its own", async (t) => {
    delete process.env.APNS_KEY_ID;
    delete process.env.APNS_PRIVATE_KEY;
    delete process.env.APNS_TOKEN_ENCRYPTION_KEY;
    const users = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
    const [me, alice, bob, carol] = users;
    const sources: Record<string, string> = Object.fromEntries(users.map((user) => [user, randomUUID()]));
    const [withAlice, withBob, withCarol, normal] = [randomUUID(), randomUUID(), randomUUID(), randomUUID()];
    const fights = [withAlice, withBob, withCarol, normal];
    t.after(async () => {
        await database`delete from public.fights where id in ${database(fights)}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users) {
        await database`insert into auth.users (id) values (${user})`;
        await database`
            insert into public.data_sources (id, user_id, provider, source_label, connection_route)
            values (${sources[user]}, ${user}, 'apple_health', 'Apple Health', 'healthkit')
        `;
    }
    for (const [fightId, opponent, friends] of [
        [withAlice, alice, true],
        [withBob, bob, true],
        [withCarol, carol, true],
        [normal, alice, false],
    ] as const) {
        await database`
            insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, friends)
            values (${fightId}, ${me}, ${friends ? "Friends" : "Normal fight"}, 'live', ${startsAt}, ${endsAt},
                'UTC', 'highest_total', 'shared', ${friends})
        `;
        for (const user of [me, opponent]) {
            await database`
                insert into public.fight_members (fight_id, user_id, state, selected_source_id)
                values (${fightId}, ${user}, 'accepted', ${sources[user]})
            `;
        }
    }
    async function completeSteps(fightId: string, user: string, value: number) {
        await database`
            insert into private.fight_score_snapshots (
                fight_id, user_id, source_id, cutoff_at, value, input_hash, calculation_version
            ) values (${fightId}, ${user}, ${sources[user]}, ${endsAt}, ${value}, repeat('a', 64), 1)
        `;
    }
    async function intents(fightIds: string[]) {
        return database<{ user_id: string; fight_id: string; kind: string; idempotency_key: string }[]>`
            select user_id, fight_id, kind, idempotency_key from private.notification_intents
            where fight_id in ${database(fightIds)} order by kind, user_id
        `;
    }
    const friendRounds: string[] = [withAlice, withBob, withCarol];

    await enqueueScheduledNotifications(database, new Date("2026-10-31T01:00:00Z"));
    assert.deepEqual((await intents(friendRounds)).map((row) => row.kind), [], "no ending reminder for friend rounds");
    assert.deepEqual((await intents([normal])).map((row) => row.kind), ["ending_24h", "ending_24h"]);

    await completeSteps(withAlice, alice, 3_000);
    await completeSteps(withBob, bob, 8_000);
    await completeSteps(withCarol, carol, 1_000);
    await completeSteps(normal, alice, 3_000);
    const ended = new Date("2026-11-01T01:00:00Z");
    for (const fightId of fights) await recalculateFight(fightId, ended, database);
    await enqueueScheduledNotifications(database, ended);
    const syncs = await intents(friendRounds);
    assert.deepEqual(
        syncs.map((row) => [row.user_id, row.kind, row.idempotency_key]),
        [[me, "friends_sync", `${me}:friends_sync:2026-10`]],
        "one sync push for the only person behind, and no per-fight pushes",
    );
    assert.ok(friendRounds.includes(syncs[0].fight_id));
    assert.deepEqual(
        (await intents([normal])).map((row) => [row.kind, row.user_id]).sort(),
        [["ending_24h", alice], ["ending_24h", me], ["fight_ended", alice], ["fight_ended", me], ["final_sync", me]].sort(),
    );

    const stray = randomUUID();
    await database`
        insert into private.notification_intents (id, idempotency_key, user_id, fight_id, kind, slot, not_before, expires_at, route, copy_key)
        values (${stray}, ${stray}, ${alice}, ${withAlice}, 'fight_ended', 't0', ${endsAt}, '2026-11-01T02:00:00Z',
            ${"/fights/" + withAlice}, 'fight_ended_everyone')
    `;
    await processNotificationOutbox(ended, database);
    const [strayStatus] = await database`select status, skip_reason from private.notification_intents where id = ${stray}`;
    assert.deepEqual({ ...strayStatus }, { status: "skipped", skip_reason: "superseded" });
    const [syncStatus] = await database`select status from private.notification_intents where kind = 'friends_sync' and user_id = ${me}`;
    assert.equal(syncStatus.status, "pending");

    for (const fightId of [...friendRounds, normal]) await completeSteps(fightId, me, 5_000);
    const finished = new Date("2026-11-01T02:00:00Z");
    await recalculateFight(withAlice, finished, database);
    assert.deepEqual(
        (await intents(friendRounds)).filter((row) => row.kind === "friends_results").map((row) => row.user_id),
        [alice],
        "results wait for each person's last friend round",
    );
    // Hold the bob round's finalization open: the carol round must wait and then see it final.
    let lastRound = Promise.resolve();
    await database.begin(async (sql) => {
        await sql`update public.fights set state = 'final' where id = ${withBob}`;
        await enqueueFriendsResultsNotifications(sql, withBob, finished);
        lastRound = recalculateFight(withCarol, finished, database);
        let waiting = false;
        for (let attempt = 0; attempt < 100 && !waiting; attempt += 1) {
            const [lock] = await database`
                select exists (
                    select 1 from pg_locks
                    where locktype = 'advisory' and not granted
                        and database = (select oid from pg_database where datname = current_database())
                ) as waiting
            `;
            waiting = lock.waiting;
            if (!waiting) await setTimeout(10);
        }
        assert.equal(waiting, true, "the carol round waits for the month lock");
    });
    await lastRound;
    await recalculateFight(normal, finished, database);

    const results = (await intents(friendRounds)).filter((row) => row.kind === "friends_results");
    assert.deepEqual(
        results.map((row) => [row.kind, row.user_id, row.idempotency_key]).sort(),
        [me, alice, bob, carol].map((user) => ["friends_results", user, `${user}:friends_results:2026-10`]).sort(),
        "exactly one results push per person, even when the last rounds finalize together",
    );
    assert.deepEqual(
        (await intents([normal])).filter((row) => row.kind === "fight_finalized").map((row) => row.user_id).sort(),
        [me, alice].sort(),
    );

    const titles = new Map<string, string>();
    for (const user of [me, alice, bob]) {
        const [intent] = await database`
            select * from private.notification_intents where user_id = ${user} and kind = 'friends_results'
        `;
        assert.equal(intent.route, `/fights/${intent.fight_id}?friends=1`);
        const content = await readNotificationContent(notificationDeliveryRowSchema.parse({
            ...intent, fight_state: "final", fight_host_id: null, fight_friends: true, fight_name: "Friends",
            owner_handle: null, ends_at: endsAt, sync_deadline: "2026-11-02T00:00:00Z", time_zone: "UTC",
            member_state: "accepted", final_steps_complete: true, preferences: null,
        }), "en", database);
        titles.set(user, content?.title ?? "");
    }
    assert.equal(titles.get(me), "October: you won 2 of 3 friend fights");
    assert.equal(titles.get(alice), "October: you won 0 of 1 friend fight");
    assert.equal(titles.get(bob), "October: you won 1 of 1 friend fight");
});

test("the friend sync reminder waits for 09:00 local on the 1st and skips anyone who synced overnight", async (t) => {
    delete process.env.APNS_KEY_ID;
    delete process.env.APNS_PRIVATE_KEY;
    delete process.env.APNS_TOKEN_ENCRYPTION_KEY;
    const [west, east] = [randomUUID(), randomUUID()];
    const westSource = randomUUID();
    const round = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${round}`;
        await database`delete from auth.users where id in (${west}, ${east})`;
    });
    for (const [user, zone] of [[west, "America/Phoenix"], [east, "Asia/Tokyo"]]) {
        await database`insert into auth.users (id) values (${user})`;
        await database`update public.profiles set time_zone = ${zone} where id = ${user}`;
    }
    await database`
        insert into public.data_sources (id, user_id, provider, source_label, connection_route)
        values (${westSource}, ${west}, 'apple_health', 'Apple Health', 'healthkit')
    `;
    await database`
        insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, friends)
        values (${round}, ${west}, 'Friends', 'live', ${startsAt}, ${endsAt}, 'UTC', 'highest_total', 'shared', true)
    `;
    await database`
        insert into public.fight_members (fight_id, user_id, state, selected_source_id)
        values (${round}, ${west}, 'accepted', ${westSource}), (${round}, ${east}, 'accepted', null)
    `;

    await recalculateFight(round, new Date("2026-11-01T00:30:00Z"), database);
    const queued = await database<{ user_id: string; not_before: Date }[]>`
        select user_id, not_before from private.notification_intents where fight_id = ${round} and kind = 'friends_sync'
    `;
    assert.deepEqual(
        new Map(queued.map((row) => [row.user_id, row.not_before.toISOString()])),
        new Map([[west, "2026-11-01T16:00:00.000Z"], [east, "2026-11-01T00:00:00.000Z"]]),
        "09:00 in Phoenix is after the round ends; 09:00 in Tokyo is the round's end",
    );

    await database`
        insert into private.fight_score_snapshots (
            fight_id, user_id, source_id, cutoff_at, value, input_hash, calculation_version
        ) values (${round}, ${west}, ${westSource}, ${endsAt}, 4000, repeat('a', 64), 1)
    `;
    await recalculateFight(round, new Date("2026-11-01T10:00:00Z"), database);
    await processNotificationOutbox(new Date("2026-11-01T16:00:00Z"), database);
    const statuses = await database<{ user_id: string; status: string; skip_reason: string | null }[]>`
        select user_id, status, skip_reason from private.notification_intents where fight_id = ${round} and kind = 'friends_sync'
    `;
    assert.deepEqual(
        new Map(statuses.map((row) => [row.user_id, [row.status, row.skip_reason]])),
        new Map([[west, ["skipped", "already_complete"]], [east, ["pending", null]]]),
    );
});

test("a friend round stuck on someone who stopped syncing does not hold back the results push", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [me, alice, sam] = users;
    const sources: Record<string, string> = Object.fromEntries(users.map((user) => [user, randomUUID()]));
    const [withAlice, withSam] = [randomUUID(), randomUUID()];
    t.after(async () => {
        await database`delete from public.fights where id in ${database([withAlice, withSam])}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users) {
        await database`insert into auth.users (id) values (${user})`;
        await database`
            insert into public.data_sources (id, user_id, provider, source_label, connection_route)
            values (${sources[user]}, ${user}, 'apple_health', 'Apple Health', 'healthkit')
        `;
    }
    for (const [fightId, opponent] of [[withAlice, alice], [withSam, sam]] as const) {
        await database`
            insert into public.fights (
                id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, friends, closes_after_grace
            ) values (${fightId}, ${me}, 'Friends', 'live', ${startsAt}, ${endsAt}, 'UTC', 'highest_total', 'shared', true, false)
        `;
        for (const user of [me, opponent]) {
            await database`
                insert into public.fight_members (fight_id, user_id, state, selected_source_id)
                values (${fightId}, ${user}, 'accepted', ${sources[user]})
            `;
        }
    }
    // Sam stopped syncing behind me, so that round waits for him.
    for (const [fightId, user, value] of [[withAlice, me, 5_000], [withAlice, alice, 3_000], [withSam, me, 5_000]] as const) {
        await database`
            insert into private.fight_score_snapshots (
                fight_id, user_id, source_id, cutoff_at, value, input_hash, calculation_version
            ) values (${fightId}, ${user}, ${sources[user]}, ${endsAt}, ${value}, repeat('a', 64), 1)
        `;
    }
    const results = async () => (await database<{ user_id: string }[]>`
        select user_id from private.notification_intents
        where kind = 'friends_results' and user_id in ${database(users)} order by user_id
    `).map((row) => row.user_id);
    for (const fightId of [withAlice, withSam]) await recalculateFight(fightId, new Date("2026-11-01T01:00:00Z"), database);
    assert.deepEqual(await results(), [alice], "my results wait for my last round");
    await enqueueScheduledNotifications(database, new Date("2026-11-01T23:00:00Z"));
    assert.deepEqual(await results(), [alice], "not before a day has passed");
    for (const _ of [1, 2]) await enqueueScheduledNotifications(database, new Date("2026-11-02T01:00:00Z"));
    assert.deepEqual(await results(), [me, alice].sort(), "a day after the month, once each, never for the round still open");
});


import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { setTimeout as delay } from "node:timers/promises";
import { createClient, type RealtimeChannel } from "@supabase/supabase-js";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readFightSnapshot } from "./fight-snapshot-supabase-query";
import { syncHealthKitAggregates } from "./healthkit-aggregates-supabase-query";
import { fightSnapshotSchema } from "@/lib/types/fights/fight-snapshot";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 2 });
const admin = createClient(
    env.SUPABASE_TEST_URL,
    env.SUPABASE_TEST_SERVICE_KEY,
    {
        auth: { persistSession: false, autoRefreshToken: false },
    },
);
after(() => database.end());

async function subscribe(channel: RealtimeChannel, allowed: boolean) {
    await new Promise<void>((resolve, reject) => {
        const timeout = setTimeout(
            () => reject(new Error("Realtime subscription timed out")),
            15_000,
        );
        channel.subscribe((status, error) => {
            if (
                status === "SUBSCRIBED" ||
                status === "CHANNEL_ERROR" ||
                status === "TIMED_OUT"
            ) {
                clearTimeout(timeout);
                if (
                    allowed === (status === "SUBSCRIBED") &&
                    status !== "TIMED_OUT"
                )
                    resolve();
                else
                    reject(
                        error ??
                            new Error(
                                `Unexpected subscription status: ${status}`,
                            ),
                    );
            }
        });
    });
}

test(
    "private fight invalidations follow commits and reconcile both participants",
    { timeout: 60_000 },
    async (t) => {
        const clients = Array.from({ length: 3 }, () =>
            createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_ANON_KEY, {
                auth: { persistSession: false, autoRefreshToken: false },
            }),
        );
        const users: string[] = [];
        const fightId = randomUUID();
        t.after(async () => {
            await Promise.all(
                clients.map((client) => client.removeAllChannels()),
            );
            await database`delete from public.fights where id = ${fightId}`;
            for (const id of users) await admin.auth.admin.deleteUser(id);
        });
        for (const client of clients) {
            const email = `live-${randomUUID()}@example.com`;
            const password = randomUUID();
            const created = await admin.auth.admin.createUser({
                email,
                password,
                email_confirm: true,
            });
            assert.ifError(created.error);
            assert.ok(created.data.user);
            users.push(created.data.user.id);
            const signedIn = await client.auth.signInWithPassword({
                email,
                password,
            });
            assert.ifError(signedIn.error);
        }
        const [owner, peer, outsider] = users;
        const startsAt = new Date(Date.now() - 3_600_000).toISOString();
        const endsAt = new Date(Date.now() + 86_400_000).toISOString();
        await database`
        insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${owner}, 'Live standings', 'live', ${startsAt}, ${endsAt}, 'UTC', 'highest_total', 'shared')
    `;
        await database`
        insert into public.fight_members (fight_id, user_id, state) values
            (${fightId}, ${owner}, 'accepted'), (${fightId}, ${peer}, 'accepted')
    `;
        await database`update public.fight_members set current_value = case when user_id = ${owner} then 8000 else 9000 end
        where fight_id = ${fightId}`;

        const received = [0, 0, 0];
        const feedReceived = [0, 0, 0];
        const replicationReady = new Set<number>();
        const channels = clients.map((client, index) =>
            client
                .channel(`fitfight:fights:${users[index]}`, {
                    config: {
                        private: true,
                        broadcast: { ack: true, replication_ready: true },
                    },
                })
                .on("system", {}, (message: unknown) => {
                    assert.ok(
                        message &&
                            typeof message === "object" &&
                            "status" in message,
                    );
                    if (message.status === "ok") replicationReady.add(index);
                })
                .on("broadcast", { event: "fights_changed" }, (message) => {
                    // Realtime adds a random message ID to our otherwise empty payload.
                    assert.deepEqual(Object.keys(message.payload), ["id"]);
                    assert.equal(typeof message.payload.id, "string");
                    assert.ok(
                        ![fightId, ...users].includes(message.payload.id),
                    );
                    received[index]++;
                })
                .on("broadcast", { event: "feed_changed" }, (message) => {
                    assert.deepEqual(Object.keys(message.payload), ["id"]);
                    feedReceived[index]++;
                }),
        );
        await Promise.all(channels.map((channel) => subscribe(channel, true)));
        for (
            let attempt = 0;
            attempt < 100 && replicationReady.size < 3;
            attempt++
        )
            await delay(50);
        assert.equal(
            replicationReady.size,
            3,
            "Each channel must report that database replication is ready",
        );
        const denied = clients[2].channel(`fitfight:fights:${owner}`, {
            config: { private: true },
        });
        await subscribe(denied, false);
        await clients[2].removeChannel(denied);
        const anonymous = createClient(
            env.SUPABASE_TEST_URL,
            env.SUPABASE_TEST_ANON_KEY,
            {
                auth: { persistSession: false, autoRefreshToken: false },
            },
        );
        t.after(() => anonymous.removeAllChannels());
        await subscribe(
            anonymous.channel(`fitfight:fights:${owner}`, {
                config: { private: true },
            }),
            false,
        );

        // A subscribed client still has no permission to publish server invalidations.
        await assert.rejects(
            database.begin(async (sql) => {
                await sql`set local role authenticated`;
                await sql`select set_config('request.jwt.claim.sub', ${owner}, true)`;
                await sql`insert into realtime.messages (topic, extension, event, payload, private)
            values (${"fitfight:fights:" + owner}, 'broadcast', 'fights_changed', '{}'::jsonb, true)`;
            }),
            /row-level security|permission denied/,
        );

        // Ignore fixture setup messages that may still be passing through WAL replication.
        await delay(500);
        received.fill(0);
        const before =
            await database`select count(*)::int as count from realtime.messages
        where topic = ${"fitfight:fights:" + peer} and event = 'fights_changed'`;
        await assert.rejects(
            database.begin(async (sql) => {
                await sql`update public.fight_members set current_value = 77777 where fight_id = ${fightId} and user_id = ${owner}`;
                const [pending] =
                    await sql`select count(*)::int as count from realtime.messages
            where topic = ${"fitfight:fights:" + peer} and event = 'fights_changed'`;
                assert.equal(pending.count, before[0].count + 1);
                throw new Error("intentional rollback");
            }),
            /intentional rollback/,
        );
        await delay(300);
        assert.deepEqual(received, [0, 0, 0]);
        const [rolledBack] =
            await database`select current_value::int as value from public.fight_members
        where fight_id = ${fightId} and user_id = ${owner}`;
        assert.equal(rolledBack.value, 8000);
        const [afterRollback] =
            await database`select count(*)::int as count from realtime.messages
        where topic = ${"fitfight:fights:" + peer} and event = 'fights_changed'`;
        assert.equal(afterRollback.count, before[0].count);

        const postId = randomUUID();
        await database`insert into public.fight_posts (id, fight_id, audience, author_id, body)
            values (${postId}, ${fightId}, 'fight', ${owner}, 'Live comment regression')`;
        await delay(500);
        feedReceived.fill(0);
        await assert.rejects(database.begin(async (sql) => {
            await sql`insert into public.fight_post_comments (post_id, author_id, body)
                values (${postId}, ${peer}, 'Rolled back comment')`;
            throw new Error('rollback comment');
        }), /rollback comment/);
        await delay(300);
        assert.deepEqual(feedReceived, [0, 0, 0]);
        await database`insert into public.fight_post_comments (post_id, author_id, body)
            values (${postId}, ${peer}, 'Committed comment')`;
        for (let attempt = 0; attempt < 100 && (feedReceived[0] === 0 || feedReceived[1] === 0); attempt++) await delay(50);
        assert.ok(feedReceived[0] > 0 && feedReceived[1] > 0, 'Both phones receive a committed comment invalidation');
        assert.equal(feedReceived[2], 0, 'Unrelated users receive no comment invalidation');

        const cutoff = new Date().toISOString();
        await syncHealthKitAggregates(
            owner,
            {
                complete_through: cutoff,
                time_zone: "UTC",
                merged_days: [],
                fight_aggregates: [
                    {
                        fight_id: fightId,
                        starts_at: startsAt,
                        ends_at: endsAt,
                        cutoff_at: cutoff,
                        steps: 20000,
                    },
                ],
            },
            database,
        );
        for (
            let attempt = 0;
            attempt < 100 && (received[0] === 0 || received[1] === 0);
            attempt++
        )
            await delay(50);
        assert.ok(
            received[0] > 0 && received[1] > 0,
            "Both signed-in phones must receive the committed invalidation",
        );
        assert.equal(
            received[2],
            0,
            "An unrelated user must receive no fight activity",
        );
        const [confirmed] =
            await database`select count(*)::int as count from realtime.messages
        where topic = ${"fitfight:fights:" + peer} and event = 'fights_changed'`;
        assert.ok(
            confirmed.count > before[0].count,
            "Successful writes must actually enqueue a message",
        );
        const snapshots = await Promise.all(
            [owner, peer].map((user) =>
                readFightSnapshot(user, "UTC", database),
            ),
        );
        assert.deepEqual(snapshots[0].members, snapshots[1].members);
        assert.equal(
            snapshots[1].members.find((member) => member.user_id === owner)
                ?.current_value,
            20000,
        );

        process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
        process.env.SUPABASE_SERVICE_ROLE_KEY = env.SUPABASE_TEST_SERVICE_KEY;
        const { POST: refresh } = await import(
            "@/app/api/v1/fights/refresh/route"
        );
        const { POST: snapshot } = await import(
            "@/app/api/v1/fights/snapshot/route"
        );
        const { data: session } = await clients[0].auth.getSession();
        assert.ok(session.session);
        for (const client of [
            { version: "1.0.0", build: "190" },
            { version: "1.1.0", build: "200" },
        ]) {
            const response = await refresh(
                new Request("http://localhost/api/v1/fights/refresh", {
                    method: "POST",
                    body: JSON.stringify({ time_zone: "UTC" }),
                    headers: {
                        Authorization: `Bearer ${session.session.access_token}`,
                        "X-FitFight-Version": client.version,
                        "X-FitFight-Build": client.build,
                    },
                }),
                { params: Promise.resolve({}) },
            );
            assert.equal(response.status, 200);
            const contract = fightSnapshotSchema.parse(await response.json());
            assert.deepEqual(contract.members, snapshots[0].members);
        }
        const liveResponse = await snapshot(
            new Request("http://localhost/api/v1/fights/snapshot", {
                method: "POST",
                body: JSON.stringify({ time_zone: "UTC" }),
                headers: {
                    Authorization: `Bearer ${session.session.access_token}`,
                },
            }),
            { params: Promise.resolve({}) },
        );
        assert.equal(liveResponse.status, 200);
        assert.match(
            liveResponse.headers.get("Cache-Control") ?? "",
            /no-store/,
        );
        assert.doesNotMatch(
            liveResponse.headers.get("Server-Timing") ?? "",
            /maintenance/,
        );
        assert.deepEqual(
            fightSnapshotSchema.parse(await liveResponse.json()).members,
            snapshots[0].members,
        );

        const [beforeNoop] =
            await database`select count(*)::int as count from realtime.messages
        where topic = ${"fitfight:fights:" + owner} and event = 'fights_changed'`;
        await database`update public.fight_members set current_value = current_value where fight_id = ${fightId}`;
        const [afterNoop] =
            await database`select count(*)::int as count from realtime.messages
        where topic = ${"fitfight:fights:" + owner} and event = 'fights_changed'`;
        assert.equal(
            afterNoop.count,
            beforeNoop.count,
            "An unchanged rank or score write must not broadcast again",
        );
        await database`update public.fight_members set last_synced_at = now() where fight_id = ${fightId}`;
        const [afterSync] =
            await database`select count(*)::int as count from realtime.messages
        where topic = ${"fitfight:fights:" + owner} and event = 'fights_changed'`;
        assert.equal(
            afterSync.count,
            beforeNoop.count + 1,
            "Sync freshness changes notify each participant once per statement",
        );

        await clients[1].removeChannel(channels[1]);
        await database`update public.fight_members set current_value = 30000 where fight_id = ${fightId} and user_id = ${peer}`;
        const rejoined = clients[1].channel(`fitfight:fights:${peer}`, {
            config: { private: true },
        });
        await subscribe(rejoined, true);
        const reconciled = await readFightSnapshot(peer, "UTC", database);
        assert.equal(
            reconciled.members.find((member) => member.user_id === peer)
                ?.current_value,
            30000,
        );

        const previous = received[0];
        await database`delete from public.fight_members where fight_id = ${fightId} and user_id = ${owner}`;
        for (
            let attempt = 0;
            attempt < 100 && received[0] === previous;
            attempt++
        )
            await delay(50);
        assert.ok(
            received[0] > previous,
            "A removed participant must be told to reread their access",
        );
        assert.deepEqual(
            (await readFightSnapshot(owner, "UTC", database)).members,
            [],
        );
        assert.deepEqual(
            (await readFightSnapshot(outsider, "UTC", database)).fights,
            [],
        );
    },
);

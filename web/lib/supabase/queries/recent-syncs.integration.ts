import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { GET } from "@/app/api/v1/admin/recent-syncs/route";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { recentSyncsSchema } from "@/lib/types/admin/recent-syncs";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readRecentSyncs } from "./recent-syncs-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 2 });
after(async () => {
    await closeDatabaseClientForTests();
    await database.end();
});

test("recent syncs list each account whose Apple Health upload arrived in the last 7 days, newest first", async (t) => {
    const [recent, sixDays, stale, deleted, never] = [randomUUID(), randomUUID(), randomUUID(), randomUUID(), randomUUID()];
    const users: string[] = [recent, sixDays, stale, deleted, never];
    t.after(async () => {
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const [userId, synced] of [
        [recent, "1 hour"],
        [sixDays, "6 days 23 hours"],
        [stale, "8 days"],
        [deleted, "1 hour"],
        [never, null],
    ] as const) {
        await database`insert into auth.users (id) values (${userId})`;
        await database`
            update public.profiles set handle = ${`rs_${userId.slice(0, 8)}`}, display_name = ${`Synced ${userId.slice(0, 4)}`}
            where user_id = ${userId}
        `;
        await database`
            insert into public.data_sources (user_id, provider, source_label, connection_route, last_success_at)
            values (${userId}, 'apple_health', 'Apple Health', 'healthkit', now() - ${synced}::interval)
        `;
    }
    await database`update public.profiles set deleted_at = now() where user_id = ${deleted}`;

    const listed = (await readRecentSyncs(database)).people.filter((person) => users.includes(person.user_id));
    assert.deepEqual(listed.map((person) => person.user_id), [recent, sixDays]);
    assert.equal(listed[0].handle, `rs_${recent.slice(0, 8)}`);
    assert.equal(listed[0].display_name, `Synced ${recent.slice(0, 4)}`);
    assert.ok(Math.abs(Date.parse(listed[0].last_synced_at) - (Date.now() - 3_600_000)) < 60_000);
});

test("only the FitFight admin reads recent syncs over HTTP", async (t) => {
    const auth = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
        auth: { persistSession: false, autoRefreshToken: false },
    });
    const identities: { userId: string; token: string }[] = [];
    const previousHandles = process.env.FITFIGHT_ADMIN_HANDLES;
    t.after(async () => {
        if (previousHandles === undefined) delete process.env.FITFIGHT_ADMIN_HANDLES;
        else process.env.FITFIGHT_ADMIN_HANDLES = previousHandles;
        if (identities.length) {
            await database`delete from auth.users where id in ${database(identities.map((identity) => identity.userId))}`;
        }
    });
    for (let index = 0; index < 2; index++) {
        const email = `recent-syncs-${randomUUID()}@example.com`;
        const password = randomUUID();
        const created = await auth.auth.admin.createUser({ email, password, email_confirm: true });
        assert.equal(created.error, null);
        assert.ok(created.data.user);
        const client = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_ANON_KEY, {
            auth: { persistSession: false, autoRefreshToken: false },
        });
        const login = await client.auth.signInWithPassword({ email, password });
        assert.equal(login.error, null);
        assert.ok(login.data.session);
        identities.push({ userId: created.data.user.id, token: login.data.session.access_token });
    }
    const [admin, tester] = identities;
    const adminHandle = `rs_${admin.userId.slice(0, 8)}`;
    await database`update public.profiles set handle = ${adminHandle} where user_id = ${admin.userId}`;
    process.env.FITFIGHT_ADMIN_HANDLES = adminHandle;
    await database`
        insert into public.data_sources (user_id, provider, source_label, connection_route, last_success_at)
        values (${tester.userId}, 'apple_health', 'Apple Health', 'healthkit', now())
    `;

    const url = "http://localhost/api/v1/admin/recent-syncs";
    const context = { params: Promise.resolve({}) };
    assert.equal((await GET(new Request(url), context)).status, 401);
    const denied = await GET(new Request(url, { headers: { Authorization: `Bearer ${tester.token}` } }), context);
    assert.equal(denied.status, 403);
    const allowed = await GET(new Request(url, { headers: { Authorization: `Bearer ${admin.token}` } }), context);
    assert.equal(allowed.status, 200);
    assert.equal(allowed.headers.get("cache-control"), "no-store");
    const body = recentSyncsSchema.parse(await allowed.json());
    assert.ok(body.people.some((person) => person.user_id === tester.userId));
    assert.equal(body.people.some((person) => person.user_id === admin.userId), false, "the admin has not synced");
});

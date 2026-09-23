import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { closeDueFights } from "./close-due-fights-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 2 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
});
const end = new Date("2026-09-23T12:00:00.000Z");
const hour = 3_600_000;
after(() => database.end());

async function seedBacklog(t: TestContext, waitingCount: number) {
    const owner = randomUUID();
    const dueFight = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where owner_id = ${owner}`;
        await database`delete from auth.users where id = ${owner}`;
    });
    await database`insert into auth.users (id) values (${owner})`;
    await database`
        insert into public.fights (
            owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
        )
        select ${owner}, 'Waiting for final Steps', 'awaiting_final_sync',
            '2026-09-21T12:00:00Z', '2026-09-22T13:00:00Z', 'UTC',
            'highest_total', 'shared'
        from generate_series(1, ${waitingCount})
    `;
    await database`
        insert into public.fights (
            id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy
        ) values (
            ${dueFight}, ${owner}, 'Due now', 'live', '2026-09-22T12:00:00Z',
            ${end.toISOString()}, 'UTC', 'highest_total', 'shared'
        )
    `;
    await database`
        insert into public.fight_members (fight_id, user_id, state)
        values (${dueFight}, ${owner}, 'accepted')
    `;
    return dueFight;
}

test("a newly ended fight closes despite 25 older fights awaiting final Steps", async (t) => {
    const dueFight = await seedBacklog(t, 25);
    const first = await closeDueFights(admin, end, database);
    assert.deepEqual(first.fightIds, [dueFight]);
    const [fight] = await database`select state from public.fights where id = ${dueFight}`;
    assert.equal(fight.state, "awaiting_final_sync");
    const [firstIntent] = await database`
        select processed_at from private.notification_intents
        where fight_id = ${dueFight} and kind = 'fight_ended'
    `;
    assert.ok(firstIntent.processed_at);

    const second = await closeDueFights(admin, end, database);
    assert.equal(second.closed, 0);
    const [secondIntent] = await database`
        select processed_at from private.notification_intents
        where fight_id = ${dueFight} and kind = 'fight_ended'
    `;
    assert.deepEqual(secondIntent.processed_at, firstIntent.processed_at);
    const [intents] = await database`
        select count(*)::int as n from private.notification_intents
        where fight_id = ${dueFight}
    `;
    assert.equal(intents.n, 2, "end alert and one final-sync request enqueue once");
});

test("a newly ended fight closes beyond the former 200-row read cap", async (t) => {
    const dueFight = await seedBacklog(t, 201);
    const result = await closeDueFights(admin, end, database);
    assert.deepEqual(result.fightIds, [dueFight]);
});

test("the worker finalizes at the 24-hour grace deadline", async (t) => {
    const dueFight = await seedBacklog(t, 0);
    await closeDueFights(admin, end, database);
    const before = await closeDueFights(
        admin,
        new Date(end.getTime() + 24 * hour - 1),
        database,
    );
    assert.equal(before.closed, 0);
    const atDeadline = await closeDueFights(
        admin,
        new Date(end.getTime() + 24 * hour),
        database,
    );
    assert.deepEqual(atDeadline.fightIds, [dueFight]);
    const [fight] = await database`select state from public.fights where id = ${dueFight}`;
    assert.equal(fight.state, "final");
});

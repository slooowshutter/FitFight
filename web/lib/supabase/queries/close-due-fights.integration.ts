import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { closeDueFights, closeDueFightsForUser } from "./close-due-fights-supabase-query";

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

test("rounds that all end at one moment close in one run, not 25 per tick", async (t) => {
    const owner = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where owner_id = ${owner}`;
        await database`delete from auth.users where id = ${owner}`;
    });
    await database`insert into auth.users (id) values (${owner})`;
    const due = await database<{ id: string }[]>`
        insert into public.fights (owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        select ${owner}, 'Friends', 'live', '2026-09-22T12:00:00Z', ${end.toISOString()}, 'UTC', 'highest_total', 'shared'
        from generate_series(1, 60)
        returning id
    `;
    const result = await closeDueFights(admin, end, database);
    assert.ok(due.every((fight) => result.fightIds.includes(fight.id)));
    const [open] = await database<{ n: number }[]>`
        select count(*)::int as n from public.fights where owner_id = ${owner} and state = 'live'
    `;
    assert.equal(open.n, 0);
});

test("the worker never finalizes a fight without a deadline while a final sync is missing", async (t) => {
    const dueFight = await seedBacklog(t, 0);
    await database`update public.fights set closes_after_grace = false where id = ${dueFight}`;
    await closeDueFights(admin, end, database);
    const yearLater = await closeDueFights(admin, new Date(end.getTime() + 365 * 24 * hour), database);
    assert.ok(!yearLater.fightIds.includes(dueFight));
    const [fight] = await database`select state from public.fights where id = ${dueFight}`;
    assert.equal(fight.state, "awaiting_final_sync");
});

test("the worker finalizes a fight without a deadline as soon as no missing final sync can change a rank", async (t) => {
    const [owner, peer] = [randomUUID(), randomUUID()];
    const sources = [randomUUID(), randomUUID()];
    t.after(async () => {
        await database`delete from public.fights where owner_id = ${owner}`;
        await database`delete from auth.users where id in (${owner}, ${peer})`;
    });
    await database`insert into auth.users (id) values (${owner}), (${peer})`;
    for (const [index, userId] of [owner, peer].entries()) {
        await database`
            insert into public.data_sources (id, user_id, provider, source_label, connection_route)
            values (${sources[index]}, ${userId}, 'apple_health', 'Apple Health', 'healthkit')
        `;
    }
    // The peer has not synced since one hour before the end; the owner submitted final Steps.
    async function fightWithPeerAt(peerSteps: number, state = "live") {
        const [fight] = await database<{ id: string }[]>`
            insert into public.fights (
                owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, closes_after_grace
            ) values (
                ${owner}, 'Friends', ${state}, '2026-09-20T12:00:00Z', ${end.toISOString()}, 'UTC', 'highest_total', 'shared', false
            ) returning id
        `;
        for (const [index, userId] of [owner, peer].entries()) {
            const [steps, cutoff] = index === 0 ? [500, end] : [peerSteps, new Date(end.getTime() - hour)];
            await database`
                insert into public.fight_members (fight_id, user_id, state, selected_source_id)
                values (${fight.id}, ${userId}, 'accepted', ${sources[index]})
            `;
            // As an upload leaves them: inserts never carry server-owned scores.
            await database`
                update public.fight_members set current_value = ${steps}, final_steps_complete = ${index === 0}
                where fight_id = ${fight.id} and user_id = ${userId}
            `;
            await database`
                insert into private.fight_score_snapshots (
                    fight_id, user_id, source_id, cutoff_at, value, input_hash, calculation_version
                ) values (${fight.id}, ${userId}, ${sources[index]}, ${cutoff.toISOString()}, ${steps}, repeat('a', 64), 1)
            `;
        }
        return fight.id;
    }
    const ahead = await fightWithPeerAt(900);
    const behind = await fightWithPeerAt(300);
    const result = await closeDueFights(admin, new Date(end.getTime() + hour), database);
    assert.ok(result.fightIds.includes(behind), "the end moves it to awaiting final Steps");
    const later = await closeDueFights(admin, new Date(end.getTime() + 30 * 24 * hour), database);
    assert.ok(!later.fightIds.includes(behind), "a missing member who could still catch up keeps it open");
    const states = await database<{ id: string; state: string }[]>`
        select id, state::text from public.fights where id in (${ahead}, ${behind})
    `;
    assert.deepEqual(
        Object.fromEntries(states.map((row) => [row.id === ahead ? "ahead" : "behind", row.state])),
        { ahead: "final", behind: "awaiting_final_sync" },
    );
    const [winner] = await database`select rank from public.fight_members where fight_id = ${ahead} and user_id = ${peer}`;
    assert.equal(winner.rank, 1, "the missing leader wins on the last synced total");

    // Already waiting when its last needed final sync arrived: the next tick or app refresh closes it.
    const byWorker = await fightWithPeerAt(900, "awaiting_final_sync");
    const tick = await closeDueFights(admin, new Date(end.getTime() + 40 * 24 * hour), database);
    assert.ok(tick.fightIds.includes(byWorker));
    const byRefresh = await fightWithPeerAt(900, "awaiting_final_sync");
    const refresh = await closeDueFightsForUser(owner, admin, new Date(end.getTime() + 40 * 24 * hour), database);
    assert.ok(refresh.fightIds.includes(byRefresh));
    assert.ok(!refresh.fightIds.includes(behind), "a refresh skips a fight still waiting for someone");
    const settled = await database<{ state: string }[]>`
        select state::text from public.fights where id in (${byWorker}, ${byRefresh})
    `;
    assert.deepEqual(settled.map((row) => row.state), ["final", "final"]);
});


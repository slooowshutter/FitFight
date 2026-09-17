import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { listJoinableFights } from "./join-fight-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 1 });
const admin = createClient(
    env.SUPABASE_TEST_URL,
    env.SUPABASE_TEST_SERVICE_KEY,
    {
        auth: { persistSession: false, autoRefreshToken: false },
    },
);
after(() => database.end());

test("joinable list embedding counts accepted/deferred members and keeps empty fights", async (t) => {
    const users = Array.from({ length: 4 }, () => randomUUID());
    const [owner, accepted, deferred, invited] = users;
    const fightIds = [randomUUID(), randomUUID()];
    const now = new Date();
    t.after(async () => {
        await database`delete from public.fights where owner_id = ${owner}`;
        await database`delete from public.fight_series where owner_id = ${owner}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users)
        await database`insert into auth.users (id) values (${user})`;
    for (const fightId of fightIds) {
        const seriesId = randomUUID();
        await database`
            insert into public.fight_series (
                id, owner_id, join_code, visibility, recurring, duration_seconds, name, time_zone,
                suggested, suggested_at
            ) values (
                ${seriesId}, ${owner}, ${randomJoinCode()}, 'joinable', false, 604800, 'List regression', 'UTC',
                true, ${now.toISOString()}
            )
        `;
        await database`
            insert into public.fights (
                id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, series_id
            ) values (
                ${fightId}, ${owner}, 'List regression', 'live', ${now.toISOString()},
                ${new Date(now.getTime() + 604800000).toISOString()}, 'UTC', 'highest_total', 'shared', ${seriesId}
            )
        `;
        await database`update public.fight_series set current_fight_id = ${fightId} where id = ${seriesId}`;
    }
    await database`
        insert into public.fight_members (fight_id, user_id, state) values
            (${fightIds[0]}, ${accepted}, 'accepted'),
            (${fightIds[0]}, ${deferred}, 'deferred'),
            (${fightIds[0]}, ${invited}, 'invited')
    `;
    for (const suggestedOnly of [false, true]) {
        for (const userId of [accepted, deferred, invited]) {
            const summaries = await listJoinableFights(
                userId,
                admin,
                now,
                suggestedOnly,
            );
            const occupied = summaries.find(
                (row) => row.fightId === fightIds[0],
            );
            const empty = summaries.find((row) => row.fightId === fightIds[1]);
            assert.ok(occupied && empty);
            assert.equal(occupied.memberCount, 2);
            assert.equal(occupied.alreadyMember, true);
            assert.deepEqual(occupied, {
                ...occupied,
                membershipState: userId === invited ? "invited" : userId === deferred ? "deferred" : "accepted",
            });
            assert.equal(empty.memberCount, 0);
            assert.equal(empty.alreadyMember, false);
            assert.deepEqual(empty, { ...empty, membershipState: null });
        }
    }
});

test("batched lists advance expired recurring rounds and use the next round's actual roster", async (t) => {
    const users = Array.from({ length: 4 }, () => randomUUID());
    const [owner] = users;
    const seriesId = randomUUID();
    const previousId = randomUUID();
    const nextId = randomUUID();
    const now = new Date();
    t.after(async () => {
        await database`delete from public.fights where series_id = ${seriesId}`;
        await database`delete from public.fight_series where id = ${seriesId}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (const user of users) await database`insert into auth.users(id) values (${user})`;
    await database`insert into public.fight_series(id, owner_id, join_code, visibility, recurring, duration_seconds, name, time_zone, suggested)
        values (${seriesId}, ${owner}, ${randomJoinCode()}, 'joinable', true, 604800, 'Next round', 'UTC', true)`;
    const start = new Date(now.getTime() - 604800000);
    const nextEnd = new Date(now.getTime() + 604800000);
    await database`insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, series_id) values
        (${previousId}, ${owner}, 'Previous round', 'final', ${start}, ${now}, 'UTC', 'highest_total', 'shared', ${seriesId}),
        (${nextId}, ${owner}, 'Next round', 'live', ${now}, ${nextEnd}, 'UTC', 'highest_total', 'shared', ${seriesId})`;
    await database`update public.fight_series set current_fight_id = ${previousId} where id = ${seriesId}`;
    for (const user of users) await database`insert into public.fight_members(fight_id, user_id, state) values (${nextId}, ${user}, 'accepted')`;
    const fights = await listJoinableFights(owner, admin, now, true);
    const next = fights.find((fight) => fight.seriesId === seriesId);
    assert.ok(next);
    assert.equal(next.fightId, nextId);
    assert.equal(next.alreadyMember, true);
    assert.equal(next.memberCount, 4);
    const [series] = await database`select current_fight_id from public.fight_series where id = ${seriesId}`;
    assert.equal(series.current_fight_id, nextId);
});

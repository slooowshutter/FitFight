import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { ApiError } from "@/lib/http";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { getJoinableFightByCode, listJoinableFights } from "./join-fight-supabase-query";
import { updateFight } from "./update-fight-supabase-query";

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
            assert.equal(occupied.membershipState, userId === invited ? "invited" : userId === deferred ? "deferred" : "accepted");
            assert.equal(empty.memberCount, 0);
            assert.equal(empty.alreadyMember, false);
            assert.equal(empty.membershipState, null);
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

test("an owner picks a custom code; a taken code changes nothing and the old code stops working", async (t) => {
    const users = [randomUUID(), randomUUID()];
    const [owner, other] = users;
    const now = new Date();
    t.after(async () => {
        await database`delete from public.fights where owner_id in ${database(users)}`;
        await database`delete from public.fight_series where owner_id in ${database(users)}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    const codes = new Set<string>();
    while (codes.size < 2) codes.add(randomJoinCode());
    const [ownedCode, takenCode] = [...codes];
    const newCode = `GOLFCLUB${randomJoinCode()}`;
    const fightIds: string[] = [];
    for (const [user, code] of [[owner, ownedCode], [other, takenCode]]) {
        const seriesId = randomUUID();
        const fightId = randomUUID();
        await database`insert into auth.users (id) values (${user})`;
        await database`insert into public.fight_series (id, owner_id, join_code, visibility, recurring, duration_seconds, name, time_zone)
            values (${seriesId}, ${user}, ${code}, 'invite_only', false, 604800, 'Code rename', 'UTC')`;
        await database`insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, series_id)
            values (${fightId}, ${user}, 'Code rename', 'live', ${now}, ${new Date(now.getTime() + 604800000)}, 'UTC', 'highest_total', 'shared', ${seriesId})`;
        await database`update public.fight_series set current_fight_id = ${fightId} where id = ${seriesId}`;
        fightIds.push(fightId);
    }

    await assert.rejects(
        updateFight(owner, fightIds[0], { joinCode: takenCode, name: "Renamed" }, admin, now),
        (error: unknown) => error instanceof ApiError && error.status === 409 && error.code === "join_code_taken",
    );
    const [unchanged] = await database`
        select series.join_code, fight.name
        from public.fights as fight join public.fight_series as series on series.id = fight.series_id
        where fight.id = ${fightIds[0]}
    `;
    assert.deepEqual(unchanged, { join_code: ownedCode, name: "Code rename" });

    await updateFight(owner, fightIds[0], { joinCode: newCode }, admin, now);
    const renamed = await getJoinableFightByCode(other, newCode.toLowerCase(), admin, now);
    assert.equal(renamed.fightId, fightIds[0]);
    assert.equal(renamed.joinCode, newCode);
    await assert.rejects(
        getJoinableFightByCode(other, ownedCode, admin, now),
        (error: unknown) => error instanceof ApiError && error.status === 404,
    );
});

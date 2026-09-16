import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { createClient } from "@supabase/supabase-js";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { randomJoinCode } from "@/lib/domain/fights/join-code";
import { canAdministerFights } from "@/lib/admin/can-administer-fights";
import { administerFight } from "./administer-fight-supabase-query";
import { setFightSuggested } from "./suggest-fight-supabase-query";
import { joinFight, listJoinableFights } from "./join-fight-supabase-query";
import { mintNextRecurringFight } from "./mint-recurring-fight-supabase-query";
import { departFightMemberships } from "./membership-departure-supabase-query";
import { recordProfileView, readProfileMeasurements } from "./profile-events-supabase-query";
import { updateProfileSettings } from "./shared-profiles-supabase-query";
import { acceptFightParticipation } from "./accept-fight-participation-supabase-query";
import { startFight } from "./start-fight-supabase-query";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 6 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } });
after(() => database.end());

test("suggestions serialize privacy, joining, stopping and recurring roster changes", async (t) => {
    const users = [randomUUID(), randomUUID(), randomUUID()];
    const [owner, guest, outsider] = users;
    const fightId = randomUUID();
    const seriesId = randomUUID();
    const now = new Date();
    process.env.FITFIGHT_ADMIN_USER_ID = owner;
    t.after(async () => {
        delete process.env.FITFIGHT_ADMIN_USER_ID;
        delete process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED;
        await database`delete from public.fights where series_id = ${seriesId}`;
        await database`delete from public.fight_series where id = ${seriesId}`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    await database`update auth.users set raw_user_meta_data = '{"email":"marc@marclamy.com","admin":true}'::jsonb where id = ${outsider}`;
    assert.equal(canAdministerFights(outsider), false);
    await assert.rejects(setFightSuggested(outsider, fightId, true, database));
    await assert.rejects(readProfileMeasurements(outsider, database));
    await database`insert into public.fight_series(id, owner_id, visibility, recurring, duration_seconds, name, time_zone, join_code)
        values (${seriesId}, ${owner}, 'invite_only', true, 259200, 'Ordinary public fight', 'UTC', ${randomJoinCode()})`;
    await database`insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, series_id)
        values (${fightId}, ${owner}, 'Ordinary public fight', 'live', now() - interval '1 hour', now() + interval '1 hour', 'UTC', 'highest_total', 'shared', ${seriesId})`;
    await database`update public.fight_series set current_fight_id = ${fightId} where id = ${seriesId}`;
    await database`insert into public.fight_members(fight_id, user_id, state, accepted_at) values (${fightId}, ${owner}, 'accepted', now())`;
    await database`insert into public.fight_series_members(series_id, user_id, state) values (${seriesId}, ${owner}, 'accepted')`;
    await assert.rejects(setFightSuggested(owner, fightId, true, database));
    await administerFight(owner, fightId, { visibility: "joinable" }, database);
    await setFightSuggested(owner, fightId, true, database);
    await database`insert into public.fight_members(fight_id, user_id, state) values (${fightId}, ${guest}, 'invited')`;
    await acceptFightParticipation(guest, fightId, undefined, "now", now, undefined, database, admin);
    await acceptFightParticipation(guest, fightId, undefined, "now", now, undefined, database, admin);
    await assert.rejects(acceptFightParticipation(outsider, fightId, undefined, "now", now, undefined, database, admin));
    assert.ok((await listJoinableFights(guest, admin, now, true)).some((fight) => fight.fightId === fightId));
    await Promise.allSettled([
        setFightSuggested(owner, fightId, true, database),
        administerFight(owner, fightId, { visibility: "invite_only" }, database),
        joinFight(guest, { fightId, start: "now" }, null, admin, now, database),
    ]);
    const [privateSeries] = await database`select visibility, suggested from public.fight_series where id = ${seriesId}`;
    assert.equal(privateSeries.visibility, "invite_only");
    assert.equal(privateSeries.suggested, false);
    await assert.rejects(joinFight(outsider, { fightId, start: "now" }, null, admin, now, database));
    assert.equal((await listJoinableFights(outsider, admin, now, true)).some((fight) => fight.fightId === fightId), false);
    await administerFight(owner, fightId, { visibility: "joinable" }, database);
    const [publicSeries] = await database`select suggested from public.fight_series where id = ${seriesId}`;
    assert.equal(publicSeries.suggested, false);
    await joinFight(guest, { fightId, start: "now" }, null, admin, now, database);

    process.env.FITFIGHT_PROFILE_MEASUREMENT_ENABLED = "true";
    await updateProfileSettings(owner, { audience: "public" }, database);
    await recordProfileView(guest, owner, { event_id: randomUUID(), source: "standings" }, database);
    await recalculateFight(fightId, now, database);
    await recalculateFight(fightId, now, database);
    const report = await readProfileMeasurements(owner, database);
    assert.equal(report.groups.find((group) => group.kind === "shared_fight" && group.source === "standings")?.events, 1);

    await database`update public.fights set starts_at = now() - interval '3 hours', ends_at = now() - interval '1 hour' where id = ${fightId}`;
    const [nextId] = await Promise.all([
        mintNextRecurringFight(fightId, now, database),
        departFightMemberships(guest, fightId, guest, database),
    ]);
    assert.ok(nextId);
    assert.equal(await mintNextRecurringFight(fightId, now, database), nextId);
    const [count] = await database`select count(*)::int n from public.fight_members where fight_id = ${nextId} and user_id = ${guest} and state = 'accepted'`;
    assert.equal(count.n, 0);
    await Promise.allSettled([
        administerFight(owner, nextId, { action: "stop_round" }, database),
        startFight(owner, nextId, "now", database),
    ]);
    const [stopped] = await database`select state::text from public.fights where id = ${nextId}`;
    assert.equal(stopped.state, "cancelled");
    await assert.rejects(startFight(owner, nextId, "now", database));
    assert.equal(await mintNextRecurringFight(nextId, new Date(now.getTime() + 86400000), database), null);
    await database`update public.fights set state = 'final' where id = ${fightId}`;
    await assert.rejects(administerFight(owner, fightId, { action: "stop_round" }, database));
    const [final] = await database`select state::text from public.fights where id = ${fightId}`;
    assert.equal(final.state, "final");
});

test("concurrent joins cannot overfill a suggested Fight and ended offers disappear", async (t) => {
    const users = Array.from({ length: 52 }, () => randomUUID());
    const owner = users[0];
    const fightId = randomUUID();
    const seriesId = randomUUID();
    const now = new Date();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from public.fight_series where id = ${seriesId}`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const id of users) await database`insert into auth.users(id) values (${id})`;
    await database`insert into public.fight_series(id, owner_id, visibility, duration_seconds, name, time_zone, join_code, suggested, recurring)
        values (${seriesId}, ${owner}, 'joinable', 7200, 'Capacity', 'UTC', ${randomJoinCode()}, true, false)`;
    await database`insert into public.fights(id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy, series_id)
        values (${fightId}, ${owner}, 'Capacity', 'live', now() - interval '1 hour', now() + interval '1 hour', 'UTC', 'highest_total', 'shared', ${seriesId})`;
    await database`update public.fight_series set current_fight_id = ${fightId} where id = ${seriesId}`;
    for (const id of users.slice(0, 49)) await database`insert into public.fight_members(fight_id, user_id, state) values (${fightId}, ${id}, 'accepted')`;
    const attempts = await Promise.allSettled(users.slice(49, 51).map((id) => joinFight(id, { fightId, start: "now" }, null, admin, now, database)));
    assert.equal(attempts.filter((result) => result.status === "fulfilled").length, 1);
    const [capacity] = await database`select count(*)::int n from public.fight_members where fight_id = ${fightId} and state = 'accepted'`;
    assert.equal(capacity.n, 50);
    assert.equal((await listJoinableFights(users[51], admin, now, true)).some((fight) => fight.fightId === fightId), false);
    await database`update public.fights set ends_at = now() - interval '1 second' where id = ${fightId}`;
    await assert.rejects(joinFight(users[51], { fightId, start: "now" }, null, admin, new Date(), database));
    assert.equal((await listJoinableFights(owner, admin, new Date(), true)).some((fight) => fight.fightId === fightId), false);
});

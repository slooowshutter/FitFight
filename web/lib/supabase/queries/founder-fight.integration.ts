import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { civilDayBounds, civilDayStamp } from "@/lib/scoring/civil-day";
import { closeDatabaseClientForTests } from "@/lib/supabase/postgres";
import { healthKitActivityBatchSchema } from "@/lib/types/healthkit/healthkit-activity-batch";
import { healthKitAggregateSyncSchema } from "@/lib/types/healthkit/healthkit-aggregate";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { receiveHealthKitActivity } from "./activity-pipeline-supabase-query";
import { createInvite } from "./create-invite-supabase-query";
import { createFounderFight, readFounderChallengers } from "./founder-fight-supabase-query";
import { joinFight } from "./join-fight-supabase-query";
import { departFightMemberships } from "./membership-departure-supabase-query";
import { mintNextRecurringFight } from "./mint-recurring-fight-supabase-query";
import { syncHealthKitAggregates } from "./healthkit-aggregates-supabase-query";
import { getProviderUploadContext } from "./provider-uploads-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
const database = postgres(env.DATABASE_URL, { max: 5 });
const admin = createClient(env.SUPABASE_TEST_URL, env.SUPABASE_TEST_SERVICE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
});
after(async () => {
    await closeDatabaseClientForTests();
    await database.end();
});

const zone = "GMT";

async function uploadFounderSteps(founder: string, steps: Record<string, number>) {
    const collectedAt = new Date(Date.now() - 1_000).toISOString();
    return receiveHealthKitActivity(founder, healthKitActivityBatchSchema.parse({
        collected_at: collectedAt,
        time_zone: zone,
        totals: Object.entries(steps).map(([day, value]) => {
            const bounds = civilDayBounds(day, zone);
            return {
                metric: "steps",
                day,
                starts_at: bounds.startsAt.toISOString(),
                ends_at: new Date(Math.min(bounds.endsAt.getTime(), Date.parse(collectedAt))).toISOString(),
                value,
                unit: "steps",
            };
        }),
    }), database);
}

async function founderSteps(fightId: string, founder: string) {
    const [member] = await database<{ value: number | null }[]>`
        select current_value::float8 as value from public.fight_members
        where fight_id = ${fightId} and user_id = ${founder}
    `;
    return member.value;
}

test("a founder fight scores the founder from stored daily Steps and stays off his own surfaces", async (t) => {
    const [founder, challenger] = [randomUUID(), randomUUID()];
    t.after(async () => {
        await database`delete from public.fights where owner_id = ${challenger}`;
        await database`delete from public.fight_series where owner_id = ${challenger}`;
        await database`delete from auth.users where id in (${founder}, ${challenger})`;
    });
    await database`insert into auth.users (id) values (${founder}), (${challenger})`;
    const today = civilDayStamp(new Date(), zone);
    const yesterday = civilDayStamp(new Date(Date.now() - 86_400_000), zone);
    await uploadFounderSteps(founder, { [yesterday]: 7_000, [today]: 3_000 });

    await assert.rejects(createFounderFight(founder, founder, database), /cannot fight yourself/);
    const fight = await createFounderFight(challenger, founder, database);
    assert.equal(fight.state, "live");
    assert.deepEqual(await createFounderFight(challenger, founder, database), fight, "one series per user");

    const [round] = await database<{ starts_at: string; days: number; time_zone: string; host_id: string; series_id: string }[]>`
        select starts_at::text, extract(day from ends_at - starts_at)::int as days, time_zone, host_id, series_id
        from public.fights where id = ${fight.id}
    `;
    assert.equal(new Date(round.starts_at).toISOString(), civilDayBounds(today, zone).startsAt.toISOString());
    assert.deepEqual([round.days, round.time_zone, round.host_id], [30, zone, founder]);
    assert.equal(await founderSteps(fight.id, founder), 3_000, "only days inside the round count");

    await uploadFounderSteps(founder, { [today]: 5_000 });
    assert.equal(await founderSteps(fight.id, founder), 5_000, "his activity sync rescores every founder fight");

    const founderContext = await getProviderUploadContext(founder, database);
    assert.ok(!founderContext.fight_windows.some((window) => window.fight_id === fight.id));
    const founderSync = await syncHealthKitAggregates(founder, healthKitAggregateSyncSchema.parse({
        complete_through: new Date(Date.now() - 1_000).toISOString(),
        time_zone: zone,
        merged_days: [],
        fight_aggregates: [],
    }), database);
    assert.equal(founderSync.processing, "processed", "his Steps sync never carries founder fights");
    const challengerContext = await getProviderUploadContext(challenger, database);
    assert.ok(challengerContext.fight_windows.some((window) => window.fight_id === fight.id));

    const [{ join_code: joinCode }] = await database<{ join_code: string }[]>`
        select join_code from public.fight_series where id = ${round.series_id}
    `;
    await assert.rejects(createInvite(challenger, fight.id, "anyone", admin, database), /one on one/);
    await assert.rejects(joinFight(randomUUID(), { code: joinCode, start: "now" }, null, admin, new Date(), database),
        /cannot be joined/);

    const record = await readFounderChallengers(founder, database);
    assert.deepEqual(record.challengers.map((row) => [row.user_id, row.day, row.days, row.founder_steps, row.wins]),
        [[challenger, 1, 30, 5_000, 0]]);

    await departFightMemberships(challenger, fight.id, challenger, database);
    const [series] = await database<{ paused: boolean; owner_id: string }[]>`
        select paused_at is not null as paused, owner_id from public.fight_series where id = ${round.series_id}
    `;
    assert.deepEqual(series, { paused: true, owner_id: challenger }, "leaving ends the series without a successor");
});

test("the next founder round keeps its host", async (t) => {
    const [founder, challenger] = [randomUUID(), randomUUID()];
    t.after(async () => {
        await database`delete from public.fights where owner_id = ${challenger}`;
        await database`delete from public.fight_series where owner_id = ${challenger}`;
        await database`delete from auth.users where id in (${founder}, ${challenger})`;
    });
    await database`insert into auth.users (id) values (${founder}), (${challenger})`;
    await uploadFounderSteps(founder, { [civilDayStamp(new Date(), zone)]: 1_000 });
    const fight = await createFounderFight(challenger, founder, database);
    const [round] = await database<{ ends_at: string }[]>`select ends_at::text from public.fights where id = ${fight.id}`;

    const nextId = await mintNextRecurringFight(fight.id, new Date(Date.parse(round.ends_at) + 1_000), database);
    assert.ok(nextId);
    const [next] = await database<{ host_id: string; members: number }[]>`
        select fight.host_id, (select count(*)::int from public.fight_members where fight_id = fight.id and state = 'accepted') as members
        from public.fights as fight where id = ${nextId}
    `;
    assert.deepEqual(next, { host_id: founder, members: 2 });
});

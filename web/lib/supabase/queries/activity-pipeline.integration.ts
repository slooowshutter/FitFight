import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import postgres from "postgres";
import { civilDayBounds, civilDayStamp } from "@/lib/scoring/civil-day";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { healthKitActivityBatchSchema } from "@/lib/types/healthkit/healthkit-activity-batch";
import { healthKitAggregateSyncSchema } from "@/lib/types/healthkit/healthkit-aggregate";
import {
    processActivity,
    receiveHealthKitActivity,
} from "./activity-pipeline-supabase-query";
import { syncHealthKitAggregates } from "./healthkit-aggregates-supabase-query";
import { readSharedProfile } from "./shared-profiles-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 5 });
after(() => database.end());

const zone = "Europe/Paris";

async function fixture(t: TestContext) {
    const owner = randomUUID();
    const rival = randomUUID();
    const fightId = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fightId}`;
        await database`delete from auth.users where id in (${owner}, ${rival})`;
    });
    await database`insert into auth.users (id) values (${owner}), (${rival})`;
    const [fight] = await database<{ starts_at: string; ends_at: string }[]>`
        insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fightId}, ${owner}, 'Pipeline fixture', 'live',
            date_trunc('day', now() - interval '2 days'), date_trunc('day', now() + interval '5 days'),
            ${zone}, 'highest_total', 'shared')
        returning starts_at::text, ends_at::text
    `;
    for (const userId of [owner, rival]) {
        await database`
            insert into public.fight_members (fight_id, user_id, state, accepted_at)
            values (${fightId}, ${userId}, 'accepted', now())
        `;
    }
    return {
        owner,
        rival,
        fightId,
        startsAt: new Date(fight.starts_at).toISOString(),
        endsAt: new Date(fight.ends_at).toISOString(),
    };
}

function dayTotal(metric: string, day: string, value: number, collectedAt: string) {
    const bounds = civilDayBounds(day, zone);
    return {
        metric,
        day,
        starts_at: bounds.startsAt.toISOString(),
        ends_at: new Date(
            Math.min(bounds.endsAt.getTime(), Date.parse(collectedAt)),
        ).toISOString(),
        value,
        unit: metric === "steps" ? "steps" : "kcal",
    };
}

function workout(id: string, startedAt: string, minutes: number, type = "running") {
    return {
        healthkit_uuid: id,
        started_at: startedAt,
        ended_at: new Date(Date.parse(startedAt) + minutes * 60_000).toISOString(),
        activity_type: type,
        duration_seconds: minutes * 60,
        distance_m: minutes * 150,
        energy_kcal: minutes * 10,
    };
}

async function metrics(userId: string) {
    return database<{ scope: string; scope_key: string; metric: string; value: number }[]>`
        select scope, scope_key, metric, value::float8 as value
        from private.activity_metrics where user_id = ${userId}
        order by scope, scope_key, metric
    `;
}

test("an installed build's Steps upload is received, resolved, and published like before", async (t) => {
    const f = await fixture(t);
    const completeThrough = new Date(Date.now() - 1_000).toISOString();
    const today = civilDayStamp(new Date(completeThrough), zone);
    const request = healthKitAggregateSyncSchema.parse({
        complete_through: completeThrough,
        time_zone: zone,
        merged_days: [dayTotal("steps", today, 4_321, completeThrough)].map(
            ({ day, starts_at, ends_at, value }) => ({ day, starts_at, ends_at, steps: value }),
        ),
        fight_aggregates: [
            {
                fight_id: f.fightId,
                starts_at: f.startsAt,
                ends_at: f.endsAt,
                cutoff_at: completeThrough,
                steps: 12_000,
            },
        ],
        activity_days: [
            { ...dayTotal("active_energy", today, 480, completeThrough) },
            { ...dayTotal("active_energy", today, 480, completeThrough), metric: "workout_count", value: 9, unit: "count" },
        ],
        workouts: [workout(randomUUID(), new Date(Date.now() - 3_600_000).toISOString(), 30)],
    });

    const first = await syncHealthKitAggregates(f.owner, request, database);
    assert.equal(first.processing, "processed");
    const [member] = await database`
        select current_value::float8 as value, rank, selected_source_id is not null as sourced
        from public.fight_members where fight_id = ${f.fightId} and user_id = ${f.owner}
    `;
    assert.deepEqual(member, { value: 12_000, rank: 1, sourced: true });
    const [mirror] = await database`select steps from public.step_days where user_id = ${f.owner} and day = ${today}`;
    assert.equal(mirror.steps, 4_321, "Older builds still read Fight-day calendar Steps");
    const resolved = await metrics(f.owner);
    assert.ok(resolved.some((row) => row.scope === "fight_window" && row.value === 12_000));
    assert.ok(resolved.some((row) => row.metric === "steps" && row.scope === "day" && row.value === 4_321));
    assert.ok(resolved.some((row) => row.metric === "active_energy" && row.value === 480));
    const count = resolved.find((row) => row.metric === "workout_count");
    assert.equal(count?.value, 1, "Workout counts come from workout records, not the client's sum");

    const [before] = await database`select count(*)::int as rows from private.activity_raw where user_id = ${f.owner}`;
    const second = await syncHealthKitAggregates(f.owner, request, database);
    assert.equal(second.processing, "processed");
    const [afterRetry] = await database`select count(*)::int as rows from private.activity_raw where user_id = ${f.owner}`;
    assert.equal(afterRetry.rows, before.rows, "An exact retry adds no raw rows");
    assert.deepEqual(await metrics(f.owner), resolved, "A retry never increments a total");
});

test("two devices, deletions, stale replays and corrections converge on one effective history", async (t) => {
    const f = await fixture(t);
    const collectedAt = new Date(Date.now() - 60_000).toISOString();
    const later = new Date(Date.now() - 1_000).toISOString();
    const yesterday = civilDayStamp(new Date(Date.now() - 86_400_000), zone);
    const run = workout(randomUUID(), civilDayBounds(yesterday, zone).startsAt.toISOString().replace(/T.*/, "T09:00:00.000Z"), 40);
    const walk = workout(randomUUID(), run.ended_at, 20, "walking");

    const phone = healthKitActivityBatchSchema.parse({
        collected_at: collectedAt,
        time_zone: zone,
        totals: [dayTotal("steps", yesterday, 9_000, collectedAt)],
        workouts: [run, walk],
    });
    assert.deepEqual(await receiveHealthKitActivity(f.owner, phone, database), { received: 3, processing: "processed" });
    const watch = healthKitActivityBatchSchema.parse({ ...phone, collected_at: later, totals: [] });
    await receiveHealthKitActivity(f.owner, watch, database);
    const workoutRows = await database`
        select record_key from private.activity_raw where user_id = ${f.owner} and record_kind = 'workout'
    `;
    assert.equal(workoutRows.length, 2, "The same workout from a second device is one record");
    let resolved = await metrics(f.owner);
    assert.equal(resolved.find((row) => row.metric === "workout_count")?.value, 2);
    assert.equal(resolved.find((row) => row.metric === "workout_time")?.value, 3_600);
    assert.ok(resolved.some((row) => row.scope === "workout" && row.metric === "distance" && row.value === 6_000));
    assert.ok(resolved.some((row) => row.scope === "workout" && row.metric === "active_energy" && row.value === 400));

    await receiveHealthKitActivity(f.owner, healthKitActivityBatchSchema.parse({
        collected_at: later, time_zone: zone, deleted_workouts: [run.healthkit_uuid.toUpperCase()],
    }), database);
    await receiveHealthKitActivity(f.owner, healthKitActivityBatchSchema.parse({
        collected_at: new Date().toISOString(), time_zone: zone, workouts: [run],
    }), database);
    resolved = await metrics(f.owner);
    assert.equal(new Set(resolved.filter((row) => row.scope === "workout").map((row) => row.scope_key)).size,
        1, "A replay cannot resurrect a deleted workout");
    assert.equal(resolved.find((row) => row.metric === "workout_count")?.value, 1);
    assert.equal(resolved.find((row) => row.metric === "walk_run_workout_distance")?.value, 3_000);

    await receiveHealthKitActivity(f.owner, healthKitActivityBatchSchema.parse({
        collected_at: new Date(Date.now() + 1_000).toISOString(),
        time_zone: zone,
        workouts: [{ ...walk, distance_m: null }],
    }), database);
    resolved = await metrics(f.owner);
    assert.ok(!resolved.some((row) => row.scope === "workout" && row.metric === "distance"),
        "A corrected workout removes an absent measurement");
    assert.ok(!resolved.some((row) => row.metric === "walk_run_workout_distance"),
        "Derived distance disappears when its only input is removed");

    for (const [value, at] of [[9_500, later], [9_000, new Date().toISOString()]] as const) {
        await receiveHealthKitActivity(f.owner, healthKitActivityBatchSchema.parse({
            collected_at: at, time_zone: zone, totals: [dayTotal("steps", yesterday, value, at)],
        }), database);
    }
    resolved = await metrics(f.owner);
    assert.equal(
        resolved.find((row) => row.scope === "day" && row.metric === "steps")?.value,
        9_000,
        "A correction that returns to an earlier total selects it again",
    );
    const shared = await readSharedProfile(f.owner, f.owner, undefined, database);
    assert.equal(shared.step_statistics?.best_day?.steps, 9_000, "Profiles read the corrected measurement");
});

test("a processing failure keeps the received page, and the worker resumes it", async (t) => {
    const f = await fixture(t);
    const collectedAt = new Date(Date.now() - 1_000).toISOString();
    const day = civilDayStamp(new Date(collectedAt), zone);
    await database`alter table private.activity_metrics add constraint activity_metrics_test_block check (metric <> 'active_energy')`;
    t.after(() => database`alter table private.activity_metrics drop constraint if exists activity_metrics_test_block`);
    const page = healthKitActivityBatchSchema.parse({
        collected_at: collectedAt,
        time_zone: zone,
        totals: [dayTotal("active_energy", day, 300, collectedAt)],
    });
    assert.deepEqual(await receiveHealthKitActivity(f.owner, page, database), { received: 1, processing: "pending" });
    const [failed] = await database`select processing_state, processing_error is not null as has_error from private.activity_raw where user_id = ${f.owner}`;
    assert.deepEqual(failed, { processing_state: "failed", has_error: true });
    await database`update private.activity_raw set processing_attempts = 5 where user_id = ${f.owner}`;
    assert.equal(await processActivity({ userId: f.owner }, database), "pending",
        "Exhausted failures remain unprocessed in the acknowledgement");
    await database`update private.activity_raw set processing_attempts = 1 where user_id = ${f.owner}`;

    await database`alter table private.activity_metrics drop constraint activity_metrics_test_block`;
    assert.deepEqual(await receiveHealthKitActivity(f.owner, page, database), { received: 1, processing: "processed" },
        "Resending an acknowledged page adds nothing and lets the pending work finish");
    await processActivity({ limit: 500, budgetMs: 1_000 }, database);
    const [processed] = await database`select processing_state from private.activity_raw where user_id = ${f.owner}`;
    assert.equal(processed.processing_state, "processed");
    assert.equal((await metrics(f.owner)).find((row) => row.metric === "active_energy")?.value, 300);
});

test("late data cannot change a final Fight, and workouts never add to merged daily totals", async (t) => {
    const f = await fixture(t);
    const completeThrough = new Date(Date.now() - 1_000).toISOString();
    const aggregate = {
        fight_id: f.fightId, starts_at: f.startsAt, ends_at: f.endsAt, cutoff_at: completeThrough, steps: 5_000,
    };
    await syncHealthKitAggregates(f.owner, healthKitAggregateSyncSchema.parse({
        complete_through: completeThrough, time_zone: zone, merged_days: [], fight_aggregates: [aggregate],
    }), database);
    await database`update public.fights set state = 'final' where id = ${f.fightId}`;
    const lateAt = new Date().toISOString();
    await database`
        insert into private.activity_raw (user_id, source_id, record_kind, record_type, record_key, starts_at, ends_at,
            time_zone, payload, payload_hash, collected_at)
        select ${f.owner}, id, 'total', 'steps', ${`fight:${f.fightId}`}, ${f.startsAt}, ${lateAt}, ${zone},
            ${database.json({ ...aggregate, cutoff_at: lateAt, time_zone: zone, steps: 99_999, step_checkpoints: null })},
            repeat('a', 64), ${lateAt}
        from public.data_sources where user_id = ${f.owner}
    `;
    await processActivity({ userId: f.owner }, database);
    const [member] = await database`select final_value::float8 as value from public.fight_members where fight_id = ${f.fightId} and user_id = ${f.owner}`;
    assert.equal(member.value, 5_000, "A finalized result keeps its frozen value");

    const day = civilDayStamp(new Date(completeThrough), zone);
    await receiveHealthKitActivity(f.owner, healthKitActivityBatchSchema.parse({
        collected_at: completeThrough,
        time_zone: zone,
        totals: [dayTotal("active_energy", day, 700, completeThrough)],
        workouts: [workout(randomUUID(), new Date(Date.now() - 7_200_000).toISOString(), 30)],
    }), database);
    const resolved = await metrics(f.owner);
    assert.equal(resolved.find((row) => row.metric === "active_energy")?.value, 700,
        "Workout energy is never added to Apple's merged daily energy");
});

test("the newest reading is published without finalizing, and an exact-end reading completes the member", async (t) => {
    const f = await fixture(t);
    const midFight = new Date(Date.now() - 1_000).toISOString();
    const upload = (completeThrough: string, cutoffAt: string, steps: number) =>
        syncHealthKitAggregates(f.owner, healthKitAggregateSyncSchema.parse({
            complete_through: completeThrough, time_zone: zone, merged_days: [],
            fight_aggregates: [{ fight_id: f.fightId, starts_at: f.startsAt, ends_at: f.endsAt, cutoff_at: cutoffAt, steps }],
        }), database);
    await upload(midFight, midFight, 7_000);
    let [member] = await database`
        select current_value::float8 as value, final_value, finalized_at, final_steps_complete, rank
        from public.fight_members where fight_id = ${f.fightId} and user_id = ${f.owner}
    `;
    assert.deepEqual(member, { value: 7_000, final_value: null, finalized_at: null, final_steps_complete: false, rank: 1 });

    await database`
        insert into private.notification_intents (idempotency_key, user_id, fight_id, kind, slot, not_before, expires_at, route, copy_key)
        values (${`test:${f.fightId}`}, ${f.owner}, ${f.fightId}, 'grace_reminder', 't12', now(), now() + interval '1 day', '/', 'test')
    `;
    await database`update public.fights set ends_at = ${midFight}::timestamptz + interval '1 second', state = 'awaiting_final_sync' where id = ${f.fightId}`;
    const [ended] = await database<{ ends_at: string }[]>`select ends_at::text from public.fights where id = ${f.fightId}`;
    const endsAt = new Date(ended.ends_at).toISOString();
    await syncHealthKitAggregates(f.owner, healthKitAggregateSyncSchema.parse({
        complete_through: new Date().toISOString(), time_zone: zone, merged_days: [],
        fight_aggregates: [{ fight_id: f.fightId, starts_at: f.startsAt, ends_at: endsAt, cutoff_at: endsAt, steps: 7_500 }],
    }), database);
    [member] = await database`
        select current_value::float8 as value, finalized_at, final_steps_complete
        from public.fight_members where fight_id = ${f.fightId} and user_id = ${f.owner}
    `;
    assert.deepEqual(member, { value: 7_500, finalized_at: null, final_steps_complete: true });
    const [intent] = await database`select status from private.notification_intents where fight_id = ${f.fightId}`;
    assert.equal(intent.status, "skipped", "Complete members get no grace reminder");
});

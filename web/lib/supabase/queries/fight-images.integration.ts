import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import {
    claimNextFightImage,
    enqueueChangedFightImages,
    finishFightImageAttempt,
    saveFightImageRun,
} from "./fight-images-supabase-query";
import { readFightSnapshot } from "./fight-snapshot-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 2 });
after(() => database.end());

const image = "https://supabase.tryblend.ai/storage/v1/object/public/generated/a/group.png";

test("a fight image waits for two runners, folds changes, respects the daily allowance and shows only to members", async (t) => {
    const [owner, peer, outsider] = [randomUUID(), randomUUID(), randomUUID()];
    const fight = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fight}`;
        await database`delete from auth.users where id in (${owner}, ${peer}, ${outsider})`;
    });
    await database`insert into auth.users (id) values (${owner}), (${peer}), (${outsider})`;
    await database`
        insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fight}, ${owner}, 'Group image', 'live', now() - interval '1 day', now() + interval '6 days',
            'UTC', 'highest_total', 'shared')
    `;
    await database`
        insert into public.fight_members (fight_id, user_id, state, accepted_at)
        values (${fight}, ${owner}, 'accepted', now() - interval '1 minute')
    `;
    const rows = () => database`
        select status, due_at > now() + interval '59 minutes' as waits_an_hour, attempts, error
        from private.fight_group_images where fight_id = ${fight} order by created_at, id
    `;

    await enqueueChangedFightImages(database);
    assert.equal((await rows()).length, 0, "one runner gets no image");

    await database`
        insert into public.fight_members (fight_id, user_id, state, accepted_at)
        values (${fight}, ${peer}, 'invited', null)
    `;
    await enqueueChangedFightImages(database);
    assert.equal((await rows()).length, 0, "an invitation is not a runner");

    await database`update public.fight_members set state = 'accepted', accepted_at = now() where fight_id = ${fight} and user_id = ${peer}`;
    await enqueueChangedFightImages(database);
    await database`update public.profiles set companion_id = 'fox' where id = ${peer}`;
    await enqueueChangedFightImages(database);
    assert.deepEqual(
        (await rows()).map((row) => [row.status, row.waits_an_hour]),
        [["waiting", true]],
        "a join and a companion change inside the hour fold into one image",
    );
    assert.equal(await claimNextFightImage(database), null, "nothing starts before the hour");

    await database`update private.fight_group_images set due_at = now() - interval '1 second' where fight_id = ${fight}`;
    const claimed = await claimNextFightImage(database);
    assert.ok(claimed);
    assert.equal(claimed.job.status, "running");
    assert.equal(claimed.job.attempts, 1);
    assert.deepEqual(
        claimed.cast.map((row) => [row.user_id, row.is_owner, row.companion_id]),
        [[owner, true, null], [peer, false, "fox"]],
    );
    await saveFightImageRun(claimed.job.id, { layout: "trail", runners: [], workflowId: "workflow", inputs: {}, runId: "run-1" }, database);
    await finishFightImageAttempt(claimed.job.id, { runId: "run-1", imageUrl: image, check: "{}", problems: [], pass: true }, database);

    const member = await readFightSnapshot(peer, "UTC", database);
    assert.equal(member.fights.find((item) => item.id === fight)?.group_image_url, image);
    for (const role of ["anon", "authenticated"]) {
        await assert.rejects(database.begin(async (sql) => {
            await sql`set local role ${sql(role)}`;
            await sql`select * from private.fight_group_images`;
        }), /permission denied/);
    }
    const outsiderSees = await database.begin(async (sql) => {
        await sql`set local role fitfight_backend_reader`;
        await sql`select set_config('request.jwt.claims', ${JSON.stringify({ sub: outsider, role: "authenticated" })}, true)`;
        return sql`select image_url from private.fight_group_images where fight_id = ${fight}`;
    });
    assert.equal(outsiderSees.length, 0, "the backend reader sees an image only for a member");

    await enqueueChangedFightImages(database);
    assert.equal((await rows()).length, 1, "the same runners and companions do not draw again");

    await database`update public.profiles set companion_id = 'otter' where id = ${owner}`;
    await enqueueChangedFightImages(database);
    await database`update private.fight_group_images set due_at = now() - interval '1 second' where fight_id = ${fight} and status = 'waiting'`;
    const second = await claimNextFightImage(database);
    assert.ok(second);
    await database`update private.fight_group_images set run_id = 'run-2' where id = ${second.job.id}`;
    const failure = { imageUrl: null, check: null, problems: ["facing left: 1"], pass: false };
    await finishFightImageAttempt(second.job.id, { ...failure, runId: "run-older" }, database);
    const [stillRunning] = await database`select status from private.fight_group_images where id = ${second.job.id}`;
    assert.equal(stillRunning.status, "running", "a cron holding an older run cannot close the current attempt");
    await finishFightImageAttempt(second.job.id, { ...failure, runId: "run-2" }, database);

    await database`update public.profiles set companion_id = 'fox' where id = ${owner}`;
    await enqueueChangedFightImages(database);
    await database`update private.fight_group_images set due_at = now() - interval '1 second' where fight_id = ${fight} and status = 'waiting'`;
    assert.equal(await claimNextFightImage(database), null, "a third image in 24 hours waits");
    const [held] = await database`
        select due_at > now() + interval '23 hours' as next_day from private.fight_group_images
        where fight_id = ${fight} and status = 'waiting'
    `;
    assert.equal(held.next_day, true, "it is pushed to when the first of the two frees");
    assert.equal(
        member.fights.find((item) => item.id === fight)?.group_image_url,
        (await readFightSnapshot(owner, "UTC", database)).fights.find((item) => item.id === fight)?.group_image_url,
        "a failed image keeps the last ready one",
    );

    await database`update private.fight_group_images set due_at = now() - interval '1 second' where fight_id = ${fight} and status = 'waiting'`;
    await database`update private.fight_group_images set started_at = now() - interval '25 hours' where fight_id = ${fight} and status <> 'waiting'`;
    await database`update public.fights set ends_at = now() - interval '1 minute' where id = ${fight}`;
    assert.equal(await claimNextFightImage(database), null);
    assert.deepEqual(
        (await rows()).map((row) => row.status),
        ["ready", "failed", "cancelled"],
        "a fight that ended cancels its waiting image and keeps every row",
    );
});

test("a fight whose image could not start queues again; a judged failure waits for a new change", async (t) => {
    const [owner, peer] = [randomUUID(), randomUUID()];
    const fight = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where id = ${fight}`;
        await database`delete from auth.users where id in (${owner}, ${peer})`;
    });
    await database`insert into auth.users (id) values (${owner}), (${peer})`;
    await database`
        insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
        values (${fight}, ${owner}, 'Group image retry', 'scheduled', now() + interval '1 day', now() + interval '8 days',
            'UTC', 'highest_total', 'shared')
    `;
    await database`
        insert into public.fight_members (fight_id, user_id, state, accepted_at)
        values (${fight}, ${owner}, 'accepted', now() - interval '2 minutes'), (${fight}, ${peer}, 'accepted', now())
    `;
    const open = async () => {
        await enqueueChangedFightImages(database);
        const [row] = await database`
            select count(*)::int as n from private.fight_group_images where fight_id = ${fight} and status = 'waiting'
        `;
        return row.n;
    };
    const claimAndFail = async (requeue: boolean) => {
        await database`update private.fight_group_images set due_at = now() - interval '1 second' where fight_id = ${fight} and status = 'waiting'`;
        const claimed = await claimNextFightImage(database);
        assert.equal(claimed?.job.fight_id, fight);
        await finishFightImageAttempt(
            claimed.job.id,
            { runId: null, imageUrl: null, check: null, problems: ["start failed: Blend 502"], pass: false, requeue },
            database,
        );
    };

    assert.equal(await open(), 1);
    await claimAndFail(true);
    assert.equal(await open(), 1, "a start that never reached Blend tries again");
    await claimAndFail(false);
    assert.equal(await open(), 0, "a judged failure keeps the previous image until the runners change");
});

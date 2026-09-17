import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import postgres from "postgres";
import { readFightSnapshot } from "./fight-snapshot-supabase-query";
import { closeDueFightsForUser } from "./close-due-fights-supabase-query";
import { syncHealthKitAggregates } from "./healthkit-aggregates-supabase-query";
import { healthKitAggregateSyncSchema } from "@/lib/types/healthkit/healthkit-aggregate";

const databaseURL = process.env.DATABASE_URL;
if (
    process.env.CI !== "true" ||
    !databaseURL ||
    !["localhost", "127.0.0.1"].includes(new URL(databaseURL).hostname)
) {
    throw new Error(
        "These tests require the disposable local database in cloud CI",
    );
}
const database = postgres(databaseURL, { max: 1 });
after(() => database.end());

async function fixture(t: TestContext) {
    const users = Array.from({ length: 6 }, () => randomUUID());
    const [owner, peer, invited, declined, outsider, deferred] = users;
    const shared = randomUUID();
    const ownerOnly = randomUUID();
    const unrelated = randomUUID();
    t.after(async () => {
        await database`delete from public.fights where owner_id = any(${database.array(users)}::uuid[])`;
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    for (const userId of users) {
        await database`insert into auth.users (id) values (${userId})`;
    }
    for (const fight of [
        {
            id: shared,
            owner,
            starts: "2026-03-28T23:00:00Z",
            ends: "2026-03-29T22:00:00Z",
        },
        {
            id: ownerOnly,
            owner,
            starts: "2026-03-01T00:00:00Z",
            ends: "2026-03-31T00:00:00Z",
        },
        {
            id: unrelated,
            owner: outsider,
            starts: "2026-03-01T00:00:00Z",
            ends: "2026-03-31T00:00:00Z",
        },
    ]) {
        await database`
            insert into public.fights (id, owner_id, name, state, starts_at, ends_at, time_zone, outcome_rule, goal_policy)
            values (${fight.id}, ${fight.owner}, 'Snapshot fixture', 'live', ${fight.starts}, ${fight.ends},
                'Europe/Paris', 'highest_total', 'shared')
        `;
    }
    for (const member of [
        { fight: shared, user: owner, state: "accepted" },
        { fight: shared, user: peer, state: "accepted" },
        { fight: shared, user: invited, state: "invited" },
        { fight: shared, user: declined, state: "declined" },
        { fight: shared, user: deferred, state: "deferred" },
        { fight: ownerOnly, user: peer, state: "accepted" },
        { fight: unrelated, user: peer, state: "accepted" },
        { fight: unrelated, user: outsider, state: "accepted" },
    ]) {
        await database`
            insert into public.fight_members (fight_id, user_id, state)
            values (${member.fight}, ${member.user}, ${member.state})
        `;
    }
    for (const userId of [owner, peer, outsider]) {
        for (const day of ["2026-03-05", "2026-03-29", "2026-03-30"]) {
            await database`insert into public.step_days (user_id, day, steps) values (${userId}, ${day}, 123)`;
        }
    }
    return {
        owner,
        peer,
        invited,
        declined,
        outsider,
        deferred,
        shared,
        ownerOnly,
        unrelated,
    };
}

test("snapshot preserves invited, declined, owner-only and day-specific RLS access", async (t) => {
    const f = await fixture(t);
    const owner = await readFightSnapshot(f.owner, "Europe/Paris", database);
    assert.deepEqual(
        new Set(owner.fights.map((fight) => fight.id)),
        new Set([f.shared, f.ownerOnly]),
    );
    assert.ok(owner.members.every((member) => member.fight_id === f.shared));
    assert.deepEqual(
        owner.step_days
            .filter((day) => day.user_id === f.peer)
            .map((day) => day.day),
        ["2026-03-29"],
    );
    assert.equal(
        owner.step_days.filter((day) => day.user_id === f.owner).length,
        3,
    );
    assert.ok(!owner.step_days.some((day) => day.user_id === f.outsider));

    const outsider = await readFightSnapshot(
        f.outsider,
        "Europe/Paris",
        database,
    );
    assert.deepEqual(
        outsider.fights.map((fight) => fight.id),
        [f.unrelated],
    );

    const invited = await readFightSnapshot(
        f.invited,
        "Europe/Paris",
        database,
    );
    assert.deepEqual(
        invited.fights.map((fight) => fight.id),
        [f.shared],
    );
    assert.deepEqual(
        invited.members.map((member) => member.user_id),
        [f.invited],
    );
    assert.deepEqual(
        new Set(invited.profiles.map((profile) => profile.user_id)),
        new Set([f.owner, f.invited]),
    );
    assert.deepEqual(invited.step_days, []);

    const deferred = await readFightSnapshot(
        f.deferred,
        "Europe/Paris",
        database,
    );
    assert.deepEqual(
        deferred.fights.map((fight) => fight.id),
        [f.shared],
    );
    assert.equal(deferred.members.length, 5);
    assert.deepEqual(
        new Set(deferred.step_days.map((day) => day.user_id)),
        new Set([f.owner, f.peer]),
    );
    assert.ok(deferred.step_days.every((day) => day.day === "2026-03-29"));

    const declined = await readFightSnapshot(
        f.declined,
        "Europe/Paris",
        database,
    );
    assert.deepEqual(declined, {
        fights: [],
        members: [],
        profiles: [],
        series: [],
        step_days: [],
    });

    // max: 1 forces this assertion to inspect the same pooled connection used above.
    const [connection] = await database`
        select current_user = session_user as restored_role,
            nullif(current_setting('request.jwt.claim.sub', true), '') is null as cleared_subject,
            nullif(current_setting('request.jwt.claims', true), '') is null as cleared_claims
    `;
    assert.equal(connection.restored_role, true);
    assert.equal(connection.cleared_subject, true);
    assert.equal(connection.cleared_claims, true);
});

test("failed snapshot transactions also clear the pooled role and user claims", async (t) => {
    const f = await fixture(t);
    await assert.rejects(
        readFightSnapshot(f.owner, "Mars/Olympus", database),
        /time zone/,
    );
    const [connection] = await database`
        select current_user = session_user as restored_role,
            nullif(current_setting('request.jwt.claim.sub', true), '') is null as cleared_subject,
            nullif(current_setting('request.jwt.claims', true), '') is null as cleared_claims
    `;
    assert.equal(connection.restored_role, true);
    assert.equal(connection.cleared_subject, true);
    assert.equal(connection.cleared_claims, true);
});

test("snapshot handles a DST day without exposing a midnight cutoff day or deleted profiles", async (t) => {
    const f = await fixture(t);
    await database`delete from public.fights where id = ${f.ownerOnly}`;
    await database`update public.profiles set deleted_at = now() where user_id = ${f.invited}`;
    const snapshot = await readFightSnapshot(f.owner, "Europe/Paris", database);
    assert.deepEqual(
        new Set(snapshot.step_days.map((day) => day.day)),
        new Set(["2026-03-29"]),
    );
    assert.ok(
        !snapshot.profiles.some((profile) => profile.user_id === f.invited),
    );

    const peer = await readFightSnapshot(f.peer, "Europe/Paris", database);
    assert.ok(peer.fights.some((fight) => fight.id === f.unrelated));
    assert.ok(peer.members.some((member) => member.user_id === f.outsider));
    const ownerAgain = await readFightSnapshot(
        f.owner,
        "Europe/Paris",
        database,
    );
    assert.ok(!ownerAgain.fights.some((fight) => fight.id === f.unrelated));
    assert.ok(
        !ownerAgain.members.some((member) => member.user_id === f.outsider),
    );
});

test("refresh maintenance closes only the caller's accepted fights", async (t) => {
    const f = await fixture(t);
    const admin = {
        from: () => {
            throw new Error("fixture has no recurring series");
        },
    };
    const result = await closeDueFightsForUser(
        f.owner,
        admin as never,
        new Date("2026-09-05T12:00:00Z"),
        database,
    );
    assert.deepEqual(result.fightIds, [f.shared]);
    const rows =
        await database`select id, state from public.fights where id = any(${database.array(
            [f.shared, f.ownerOnly, f.unrelated],
        )}::uuid[])`;
    assert.equal(rows.find((row) => row.id === f.shared)?.state, "final");
    assert.equal(rows.find((row) => row.id === f.ownerOnly)?.state, "live");
    assert.equal(rows.find((row) => row.id === f.unrelated)?.state, "live");
});

test("Fight chart and score share a revision through corrections, legacy uploads, and finalization", async (t) => {
    const f = await fixture(t);
    await database`delete from public.fights where id = any(${database.array([f.ownerOnly, f.unrelated])}::uuid[])`;
    await database`update public.fights set starts_at = '2026-03-29T10:00:00Z', ends_at = '2026-04-01T10:00:00Z'
        where id = ${f.shared}`;
    const upload = {
        complete_through: "2026-03-30T12:00:00Z",
        time_zone: "America/New_York",
        merged_days: [],
        fight_aggregates: [
            {
                fight_id: f.shared,
                starts_at: "2026-03-29T10:00:00Z",
                ends_at: "2026-04-01T10:00:00Z",
                cutoff_at: "2026-03-30T12:00:00Z",
                steps: 6000,
                step_checkpoints: [
                    {
                        day: "2026-03-29",
                        cutoff_at: "2026-03-29T22:00:00Z",
                        steps: 4000,
                    },
                    {
                        day: "2026-03-30",
                        cutoff_at: "2026-03-30T12:00:00Z",
                        steps: 6000,
                    },
                ],
            },
        ],
    };
    await syncHealthKitAggregates(
        f.owner,
        healthKitAggregateSyncSchema.parse(upload),
        database,
    );
    const peerUpload = structuredClone(upload);
    peerUpload.fight_aggregates[0].steps = 9000;
    peerUpload.fight_aggregates[0].step_checkpoints[1].steps = 9000;
    await syncHealthKitAggregates(
        f.peer,
        healthKitAggregateSyncSchema.parse(peerUpload),
        database,
    );
    const owner = await readFightSnapshot(
        f.owner,
        "Pacific/Auckland",
        database,
    );
    const peer = await readFightSnapshot(f.peer, "America/New_York", database);
    assert.deepEqual(owner.members, peer.members);
    for (const member of owner.members.filter(
        (row) => row.state === "accepted",
    )) {
        assert.equal(
            member.step_checkpoints?.at(-1)?.steps,
            member.current_value,
        );
    }
    assert.equal(owner.members.find((row) => row.user_id === f.peer)?.rank, 1);
    assert.equal(
        owner.members.find((row) => row.user_id === f.owner)
            ?.step_checkpoints?.[0].steps,
        4000,
    );
    assert.ok(
        owner.step_days.every((day) => day.steps === 123),
        "Legacy calendar days cannot determine Fight history",
    );
    const deferred = await readFightSnapshot(f.deferred, "UTC", database);
    assert.deepEqual(deferred.members, owner.members);
    for (const userId of [f.invited, f.declined, f.outsider]) {
        const hidden = await readFightSnapshot(userId, "UTC", database);
        assert.ok(
            hidden.members.every((member) => member.step_checkpoints == null),
        );
    }
    await assert.rejects(
        database.begin(async (sql) => {
            await sql`set local role authenticated`;
            await sql`select step_checkpoints from private.fight_score_snapshots`;
        }),
        /permission denied/,
    );

    const corrected = structuredClone(upload);
    corrected.fight_aggregates[0].steps = 5000;
    corrected.fight_aggregates[0].step_checkpoints[0].steps = 3000;
    corrected.fight_aggregates[0].step_checkpoints[1].steps = 5000;
    await syncHealthKitAggregates(
        f.owner,
        healthKitAggregateSyncSchema.parse(corrected),
        database,
    );
    await syncHealthKitAggregates(
        f.owner,
        healthKitAggregateSyncSchema.parse(upload),
        database,
    );
    const afterCorrection = await readFightSnapshot(f.owner, "UTC", database);
    const correctedMember = afterCorrection.members.find(
        (member) => member.user_id === f.owner,
    );
    assert.equal(
        correctedMember?.current_value,
        5000,
        "Replay cannot replace a newer correction",
    );
    assert.deepEqual(
        correctedMember?.step_checkpoints,
        corrected.fight_aggregates[0].step_checkpoints,
    );

    const legacy = {
        complete_through: "2026-03-30T13:00:00Z",
        time_zone: "UTC",
        merged_days: [],
        fight_aggregates: [
            {
                fight_id: f.shared,
                starts_at: upload.fight_aggregates[0].starts_at,
                ends_at: upload.fight_aggregates[0].ends_at,
                cutoff_at: "2026-03-30T13:00:00Z",
                steps: 6500,
            },
        ],
    };
    await syncHealthKitAggregates(
        f.owner,
        healthKitAggregateSyncSchema.parse(legacy),
        database,
    );
    const afterLegacy = await readFightSnapshot(f.owner, "UTC", database);
    const legacyMember = afterLegacy.members.find(
        (member) => member.user_id === f.owner,
    );
    assert.equal(legacyMember?.current_value, 6500);
    assert.equal(
        legacyMember?.step_checkpoints,
        null,
        "Score-only uploads keep their total without inventing daily checkpoints",
    );
    assert.notDeepEqual(
        legacyMember?.step_checkpoints,
        corrected.fight_aggregates[0].step_checkpoints,
        "Older clients keep scoring without attaching stale chart history",
    );
    assert.ok(
        afterLegacy.step_days.every((day) => day.steps === 123),
        "Legacy calendar days cannot determine Fight history",
    );

    await database`update public.fights set state = 'final' where id = ${f.shared}`;
    await database`update private.fight_score_snapshots set step_checkpoints = '[]'::jsonb
        where fight_id = ${f.shared} and is_final`;
    const final = await readFightSnapshot(f.peer, "UTC", database);
    assert.deepEqual(
        final.members.find((member) => member.user_id === f.peer)
            ?.step_checkpoints,
        peerUpload.fight_aggregates[0].step_checkpoints,
        "Final chart history freezes with its total",
    );
});

test("legacy uploads on different days retain totals without fabricating daily history", async (t) => {
    const f = await fixture(t);
    await database`delete from public.fights where id = any(${database.array([f.ownerOnly, f.unrelated])}::uuid[])`;
    await database`update public.fights set starts_at = '2026-03-29T10:00:00Z', ends_at = '2026-04-01T10:00:00Z'
        where id = ${f.shared}`;
    const first = {
        complete_through: "2026-03-29T18:00:00Z",
        time_zone: "America/New_York",
        merged_days: [],
        fight_aggregates: [
            {
                fight_id: f.shared,
                starts_at: "2026-03-29T10:00:00Z",
                ends_at: "2026-04-01T10:00:00Z",
                cutoff_at: "2026-03-29T18:00:00Z",
                steps: 10000,
            },
        ],
    };
    await syncHealthKitAggregates(
        f.owner,
        healthKitAggregateSyncSchema.parse(first),
        database,
    );
    const second = structuredClone(first);
    second.complete_through = "2026-03-30T21:00:00Z";
    second.fight_aggregates[0].cutoff_at = "2026-03-30T21:00:00Z";
    second.fight_aggregates[0].steps = 8000;
    await syncHealthKitAggregates(
        f.owner,
        healthKitAggregateSyncSchema.parse(second),
        database,
    );
    const snapshot = await readFightSnapshot(f.owner, "UTC", database);
    const member = snapshot.members.find((row) => row.user_id === f.owner);
    assert.equal(member?.current_value, 8000);
    assert.equal(
        member?.step_checkpoints,
        null,
        "Downward corrections and sparse sync times are not daily activity",
    );
    assert.ok(
        snapshot.step_days.every((day) => day.steps === 123),
        "Calendar step_days stay unused",
    );
    const third = structuredClone(second);
    third.complete_through = "2026-03-31T12:00:00Z";
    third.fight_aggregates[0].cutoff_at = third.complete_through;
    third.fight_aggregates[0].steps = 12000;
    await syncHealthKitAggregates(
        f.owner,
        healthKitAggregateSyncSchema.parse(third),
        database,
    );
    const afterIncrease = await readFightSnapshot(f.owner, "UTC", database);
    const increased = afterIncrease.members.find(
        (row) => row.user_id === f.owner,
    );
    assert.equal(increased?.current_value, 12000);
    assert.equal(
        increased?.step_checkpoints,
        null,
        "An increase cannot fill missing day boundaries either",
    );
});

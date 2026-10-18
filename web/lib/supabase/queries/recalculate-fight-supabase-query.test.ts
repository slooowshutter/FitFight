import assert from "node:assert/strict";
import { test } from "node:test";
import postgres, { type Sql } from "postgres";
import { recalculateFight } from "./recalculate-fight-supabase-query";

const json = postgres().json;

test("finalizing a fight uses a bounded number of writes as the roster grows", async () => {
    const statementCounts: number[] = [];
    const fightId = "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7";
    const endsAt = "2026-09-03T16:06:35.093Z";
    for (const memberCount of [2, 20]) {
        const members = Array.from({ length: memberCount }, (_, index) => ({
            user_id: `a0000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
            personal_target: null,
            input_revision: index,
        }));
        const snapshots = members.map((member, index) => ({
            id: `c0000000-0000-4000-8000-${String(index).padStart(12, "0")}`,
            user_id: member.user_id,
            value: String(100 - index),
            cutoff_at: endsAt,
        }));
        const queries: Array<{ query: string; values: readonly unknown[] }> =
            [];
        const transaction = Object.assign(
            (strings: TemplateStringsArray, ...values: unknown[]) => {
                const query = strings.join("?");
                queries.push({ query, values });
                if (query.includes("from public.fights"))
                    return Promise.resolve([
                        {
                            state: "live",
                            starts_at: "2026-08-27T16:06:36.729Z",
                            ends_at: endsAt,
                            grace_ends_at: "2026-09-04T16:06:35.093Z",
                            outcome_rule: "highest_total",
                            stake_minor: null,
                            default_goal_value: null,
                            host_id: null,
                            friends: false,
                        },
                    ]);
                if (query.includes("from public.fight_members"))
                    return Promise.resolve(members);
                if (query.includes("from private.fight_score_snapshots"))
                    return Promise.resolve(snapshots);
                return Promise.resolve([]);
            },
            { array: (values: readonly unknown[]) => values, json },
        );
        const database = Object.assign(
            () => {
                throw new Error("query must run inside a transaction");
            },
            {
                begin: async (
                    _options: string,
                    callback: (sql: Sql) => Promise<unknown>,
                ) => callback(transaction as unknown as Sql),
            },
        ) as unknown as Sql;

        await recalculateFight(
            fightId,
            new Date("2026-09-03T17:00:00.000Z"),
            database,
        );
        statementCounts.push(queries.length);
        const memberUpdates = queries.filter(({ query }) =>
            query.includes("update public.fight_members"),
        );
        assert.equal(memberUpdates.length, 1);
        assert.ok(
            memberUpdates[0].values.includes(memberCount),
            "every member receives the next common revision",
        );
        assert.ok(
            memberUpdates[0].query.includes("and member.finalized_at is null"),
            "live scores stay mutable until the fight finalizes",
        );
        assert.ok(
            !memberUpdates[0].query.includes("final_value"),
            "member freeze waits for fight finalization",
        );
        const memberPayload = memberUpdates[0].values.find((value) =>
            JSON.stringify(value).includes('"final_steps_complete"'),
        );
        assert.deepEqual(
            memberPayload,
            json(
                members.map((member, index) => ({
                    user_id: member.user_id,
                    current_value: 100 - index,
                    rank: index + 1,
                    outcome_minor: 0,
                    final_steps_complete: true,
                })),
            ),
        );
        const snapshotUpdates = queries.filter(({ query }) =>
            query.includes("set is_final"),
        );
        assert.equal(snapshotUpdates.length, 1);
        assert.deepEqual(snapshotUpdates[0].values, [
            snapshots.map((snapshot) => snapshot.id),
        ]);
        assert.ok(
            queries.some(
                ({ query, values }) =>
                    query.includes("update public.fights set state") &&
                    values.includes("final"),
            ),
        );
    }

    assert.equal(
        statementCounts[1],
        statementCounts[0],
        "roster size must not add database round trips",
    );
    assert.ok(
        statementCounts.every((count) => count <= 9),
        `expected at most 9 statements, got ${statementCounts}`,
    );
});

function mockRecalculateDatabase(input: {
    endsAt: string;
    friends?: boolean;
    graceEndsAt?: string | null;
    members: Array<{
        user_id: string;
        personal_target: null;
        input_revision: number;
    }>;
    snapshots: Array<{
        id: string;
        user_id: string;
        value: string;
        cutoff_at: string;
    }>;
}) {
    const queries: Array<{ query: string; values: readonly unknown[] }> = [];
    const transaction = Object.assign(
        (strings: TemplateStringsArray, ...values: unknown[]) => {
            const query = strings.join("?");
            queries.push({ query, values });
            if (query.includes("from public.fights"))
                return Promise.resolve([
                    {
                        state: "live",
                        starts_at: "2026-08-27T16:06:36.729Z",
                        ends_at: input.endsAt,
                        grace_ends_at:
                            input.graceEndsAt === undefined
                                ? new Date(Date.parse(input.endsAt) + 86_400_000).toISOString()
                                : input.graceEndsAt,
                        outcome_rule: "highest_total",
                        stake_minor: null,
                        default_goal_value: null,
                        host_id: null,
                        friends: input.friends ?? false,
                    },
                ]);
            if (query.includes("from public.fight_members"))
                return Promise.resolve(input.members);
            if (query.includes("from private.fight_score_snapshots"))
                return Promise.resolve(input.snapshots);
            return Promise.resolve([]);
        },
        { array: (values: readonly unknown[]) => values, json },
    );
    const database = Object.assign(
        () => {
            throw new Error("query must run inside a transaction");
        },
        {
            begin: async (
                _options: string,
                callback: (sql: Sql) => Promise<unknown>,
            ) => callback(transaction as unknown as Sql),
        },
    ) as unknown as Sql;
    return { database, queries };
}

const fightId = "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7";
const endsAt = "2026-09-03T16:06:35.093Z";
const trio = [0, 1, 2].map((index) => ({
    user_id: `a0000000-0000-4000-8000-00000000000${index}`,
    personal_target: null,
    input_revision: index,
}));

function trioSnapshots(missingValue: string) {
    return [
        {
            id: "c0000000-0000-4000-8000-000000000000",
            user_id: trio[0].user_id,
            value: missingValue,
            cutoff_at: "2026-09-03T16:00:00.000Z",
        },
        {
            id: "c0000000-0000-4000-8000-000000000001",
            user_id: trio[1].user_id,
            value: "100",
            cutoff_at: endsAt,
        },
        {
            id: "c0000000-0000-4000-8000-000000000002",
            user_id: trio[2].user_id,
            value: "500",
            cutoff_at: endsAt,
        },
    ];
}

function memberPayload(queries: Array<{ query: string; values: readonly unknown[] }>) {
    return queries
        .find(({ query }) => query.includes("update public.fight_members"))
        ?.values.find((value) =>
            JSON.stringify(value).includes('"final_steps_complete"'),
        );
}

function movedTo(
    queries: Array<{ query: string; values: readonly unknown[] }>,
    state: string,
) {
    return queries.some(
        ({ query, values }) =>
            query.includes("update public.fights set state") &&
            values.includes(state),
    );
}

test("a lone missing member already ahead settles the fight at once on their last sync", async () => {
    const { database, queries } = mockRecalculateDatabase({
        endsAt,
        members: trio,
        snapshots: trioSnapshots("9000"),
    });
    await recalculateFight(fightId, new Date("2026-09-03T17:00:00.000Z"), database);
    assert.deepEqual(
        memberPayload(queries),
        json([
            { user_id: trio[0].user_id, current_value: 9000, rank: 1, outcome_minor: 0, final_steps_complete: false },
            { user_id: trio[2].user_id, current_value: 500, rank: 2, outcome_minor: 0, final_steps_complete: true },
            { user_id: trio[1].user_id, current_value: 100, rank: 3, outcome_minor: 0, final_steps_complete: true },
        ]),
    );
    assert.ok(movedTo(queries, "final"));
});

test("a missing member who could still catch up keeps the fight open until its deadline", async () => {
    const ranks = json([
        { user_id: trio[2].user_id, current_value: 500, rank: 1, outcome_minor: 0, final_steps_complete: true },
        { user_id: trio[0].user_id, current_value: 300, rank: 2, outcome_minor: 0, final_steps_complete: false },
        { user_id: trio[1].user_id, current_value: 100, rank: 3, outcome_minor: 0, final_steps_complete: true },
    ]);
    const waiting = mockRecalculateDatabase({ endsAt, members: trio, snapshots: trioSnapshots("300") });
    await recalculateFight(fightId, new Date("2026-09-03T17:00:00.000Z"), waiting.database);
    assert.deepEqual(memberPayload(waiting.queries), ranks);
    assert.ok(movedTo(waiting.queries, "awaiting_final_sync"));
    assert.ok(!movedTo(waiting.queries, "final"));

    const closed = mockRecalculateDatabase({ endsAt, members: trio, snapshots: trioSnapshots("300") });
    await recalculateFight(fightId, new Date("2026-09-05T16:06:35.093Z"), closed.database);
    assert.deepEqual(memberPayload(closed.queries), ranks, "the last synced total counts");
    assert.ok(movedTo(closed.queries, "final"));

    const noDeadline = mockRecalculateDatabase({
        endsAt,
        graceEndsAt: null,
        members: trio,
        snapshots: trioSnapshots("300"),
    });
    await recalculateFight(fightId, new Date("2027-09-03T16:06:35.093Z"), noDeadline.database);
    assert.ok(!movedTo(noDeadline.queries, "final"), "a Fight someone made waits for everyone");
});

test("finalizing with every member incomplete ranks them by last synced totals", async () => {
    const members = trio.slice(0, 2);
    const { database, queries } = mockRecalculateDatabase({
        endsAt,
        members,
        snapshots: [trioSnapshots("42")[0]],
    });
    await recalculateFight(fightId, new Date("2026-09-05T16:06:35.093Z"), database);
    assert.deepEqual(
        memberPayload(queries),
        json([
            { user_id: members[0].user_id, current_value: 42, rank: 1, outcome_minor: 0, final_steps_complete: false },
            { user_id: members[1].user_id, current_value: 0, rank: 2, outcome_minor: 0, final_steps_complete: false },
        ]),
    );
    assert.ok(movedTo(queries, "final"));
});

test("a friend round queues one batched push per person instead of per-fight pushes", async () => {
    const fightId = "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7";
    const endsAt = "2026-11-01T00:00:00.000Z";
    const members = [
        {
            user_id: "a0000000-0000-4000-8000-000000000000",
            personal_target: null,
            input_revision: 0,
        },
        {
            user_id: "a0000000-0000-4000-8000-000000000001",
            personal_target: null,
            input_revision: 0,
        },
    ];
    const snapshots = [
        {
            id: "c0000000-0000-4000-8000-000000000000",
            user_id: members[0].user_id,
            value: "9000",
            cutoff_at: endsAt,
        },
    ];
    const perFightIntent = ({ query }: { query: string }) =>
        query.includes("jsonb_to_recordset") &&
        query.includes("insert into private.notification_intents");

    const awaiting = mockRecalculateDatabase({
        endsAt,
        friends: true,
        members,
        snapshots,
    });
    await recalculateFight(
        fightId,
        new Date("2026-11-01T01:00:00.000Z"),
        awaiting.database,
    );
    assert.ok(
        awaiting.queries.some(
            ({ query, values }) =>
                query.includes("update public.fights set state") &&
                values.includes("awaiting_final_sync"),
        ),
    );
    assert.equal(
        awaiting.queries.filter(({ query }) => query.includes("'friends_sync'"))
            .length,
        1,
    );
    assert.equal(awaiting.queries.filter(perFightIntent).length, 0);

    const finalized = mockRecalculateDatabase({
        endsAt,
        friends: true,
        members,
        snapshots,
    });
    await recalculateFight(
        fightId,
        new Date("2026-11-02T00:00:00.000Z"),
        finalized.database,
    );
    const lock = finalized.queries.findIndex(({ query }) =>
        query.includes("pg_advisory_xact_lock"),
    );
    const results = finalized.queries.findIndex(({ query }) =>
        query.includes("'friends_results'"),
    );
    assert.ok(
        lock >= 0 && results > lock,
        "the month lock is taken before checking the other rounds",
    );
    assert.equal(finalized.queries.filter(perFightIntent).length, 0);
});

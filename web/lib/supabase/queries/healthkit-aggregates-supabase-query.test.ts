import assert from "node:assert/strict";
import { test } from "node:test";
import postgres, { type Sql } from "postgres";
import {
    healthKitAggregateSyncResponseSchema,
    healthKitAggregateSyncSchema,
    parseHealthKitAggregateSync,
} from "@/lib/types/healthkit/healthkit-aggregate";
import { syncHealthKitAggregates } from "./healthkit-aggregates-supabase-query";

const json = postgres().json;

function createDatabaseStub(
    respond: (query: string, values: readonly unknown[]) => unknown[],
) {
    const queries: Array<{ query: string; values: readonly unknown[] }> = [];
    const transaction = ((first: unknown, ...values: unknown[]) => {
        if (!Array.isArray(first) || !("raw" in first)) {
            return { first, values };
        }
        const strings = first as unknown as TemplateStringsArray;
        const query = strings.join("?");
        queries.push({ query, values });
        if (query.includes("as count")) {
            return Promise.resolve([{ count: 0 }]);
        }
        return Promise.resolve(respond(query, values));
    }) as unknown as Sql;
    Object.assign(transaction, {
        array: (values: readonly unknown[]) => values,
        json,
    });
    // Intake runs in a transaction; the resolver's claim and status count run outside one.
    const database = Object.assign(transaction, {
        begin: async (
            _options: string,
            callback: (sql: Sql) => Promise<unknown>,
        ) => callback(transaction),
    });
    return { database, queries };
}

/** The raw records one Steps upload hands to the resolver. */
function receivedRecords(
    queries: Array<{ query: string; values: readonly unknown[] }>,
) {
    const intake = queries.find(({ query }) =>
        query.includes("insert into private.activity_raw"),
    );
    const payload = intake?.values.find(
        (value) =>
            typeof value === "object" && value !== null && "value" in value,
    ) as { value: Array<Record<string, unknown>> } | undefined;
    return (payload?.value ?? []).map((record) => ({
        kind: record.record_kind,
        type: record.record_type,
        key: record.record_key,
        payload: record.payload as Record<string, unknown>,
    }));
}

const validAggregate = {
    complete_through: "2026-08-30T13:53:27.350Z",
    time_zone: "Europe/Paris",
    merged_days: [
        {
            day: "2026-08-30",
            starts_at: "2026-08-29T22:00:00.000Z",
            ends_at: "2026-08-30T13:53:27.350Z",
            steps: 12_345,
        },
    ],
    fight_aggregates: [
        {
            fight_id: "B4C1285D-0232-4D15-B8CC-1A916BA2BBF7",
            starts_at: "2026-08-27T16:06:36.729Z",
            ends_at: "2026-09-03T16:06:35.093Z",
            cutoff_at: "2026-08-30T13:53:27.350Z",
            steps: 42_000,
        },
    ],
};
const sourceRow = {
    id: "333822a8-8577-4d9d-8145-ab5f120ee42f",
    complete_through: validAggregate.complete_through,
    server_now: "2026-08-30T14:00:00.000Z",
};

const checkpointAggregate = {
    ...validAggregate,
    fight_aggregates: [
        {
            ...validAggregate.fight_aggregates[0],
            step_checkpoints: [
                {
                    day: "2026-08-27",
                    cutoff_at: "2026-08-27T22:00:00Z",
                    steps: 5000,
                },
                {
                    day: "2026-08-28",
                    cutoff_at: "2026-08-28T22:00:00Z",
                    steps: 17000,
                },
                {
                    day: "2026-08-29",
                    cutoff_at: "2026-08-29T22:00:00Z",
                    steps: 33000,
                },
                {
                    day: "2026-08-30",
                    cutoff_at: validAggregate.complete_through,
                    steps: 42000,
                },
            ],
        },
    ],
};

test("Fight history must finish at the ranked total and cutoff", () => {
    const input = healthKitAggregateSyncSchema.parse(checkpointAggregate);
    assert.equal(
        input.fight_aggregates[0].step_checkpoints?.at(-1)?.steps,
        42000,
    );
    for (const point of [
        { steps: 42001 },
        { cutoff_at: "2026-08-30T13:00:00Z" },
        { steps: 100 },
    ]) {
        const invalid = structuredClone(checkpointAggregate);
        Object.assign(invalid.fight_aggregates[0].step_checkpoints[3], point);
        assert.equal(
            healthKitAggregateSyncSchema.safeParse(invalid).success,
            false,
        );
    }
    const decreasing = structuredClone(checkpointAggregate);
    decreasing.fight_aggregates[0].step_checkpoints[1].steps = 100;
    assert.equal(
        healthKitAggregateSyncSchema.safeParse(decreasing).success,
        false,
    );
    const duplicate = structuredClone(checkpointAggregate);
    duplicate.fight_aggregates[0].step_checkpoints[1] =
        duplicate.fight_aggregates[0].step_checkpoints[0];
    assert.equal(
        healthKitAggregateSyncSchema.safeParse(duplicate).success,
        false,
    );
});

test("Fight history rejects skipped days and the wrong Fight time zone before writing scores", async () => {
    const { database, queries } = createDatabaseStub((query) => {
        if (query.includes("returning id")) return [sourceRow];
        if (query.includes("from public.fights as fight"))
            return [
                {
                    fight_id:
                        validAggregate.fight_aggregates[0].fight_id.toLowerCase(),
                    starts_at: validAggregate.fight_aggregates[0].starts_at,
                    ends_at: validAggregate.fight_aggregates[0].ends_at,
                    time_zone: "Europe/Paris",
                    outcome_rule: "highest_total",
                    stake_minor: null,
                    default_goal_value: null,
                },
            ];
        return [];
    });
    const skipped = structuredClone(checkpointAggregate);
    skipped.fight_aggregates[0].step_checkpoints.splice(1, 1);
    await assert.rejects(
        syncHealthKitAggregates(
            "5b2216f4-762d-4890-a516-63046a01df31",
            healthKitAggregateSyncSchema.parse(skipped),
            database,
        ),
        /each Fight day/,
    );
    const wrongZone = structuredClone(checkpointAggregate);
    wrongZone.fight_aggregates[0].step_checkpoints[0].cutoff_at =
        "2026-08-28T00:00:00Z";
    await assert.rejects(
        syncHealthKitAggregates(
            "5b2216f4-762d-4890-a516-63046a01df31",
            healthKitAggregateSyncSchema.parse(wrongZone),
            database,
        ),
        /each Fight day/,
    );
    assert.ok(
        queries.every(
            ({ query }) =>
                !query.includes("insert into private.fight_score_snapshots"),
        ),
    );
});

test("Fight history accepts a cutoff just after a Fight-day midnight", async () => {
    const startsAt = "2026-03-28T12:00:00.000Z";
    const endsAt = "2026-03-30T12:00:00.000Z";
    const cutoffAt = "2026-03-29T22:00:00.001Z";
    const { database, queries } = createDatabaseStub((query) => {
        if (query.includes("returning id")) {
            return [
                {
                    ...sourceRow,
                    complete_through: cutoffAt,
                    server_now: "2026-03-30T00:00:00.000Z",
                },
            ];
        }
        if (query.includes("from public.fights as fight")) {
            return [
                {
                    fight_id:
                        validAggregate.fight_aggregates[0].fight_id.toLowerCase(),
                    starts_at: startsAt,
                    ends_at: endsAt,
                    time_zone: "Europe/Paris",
                    outcome_rule: "highest_total",
                    stake_minor: null,
                    default_goal_value: null,
                },
            ];
        }
        if (query.includes("from private.fight_score_snapshots")) {
            return [
                {
                    fight_id:
                        validAggregate.fight_aggregates[0].fight_id.toLowerCase(),
                },
            ];
        }
        if (query.includes("from public.fight_members")) {
            return [
                {
                    fight_id:
                        validAggregate.fight_aggregates[0].fight_id.toLowerCase(),
                    user_id: "5b2216f4-762d-4890-a516-63046a01df31",
                    current_value: "7000",
                    final_value: null,
                    personal_target: null,
                },
            ];
        }
        return [];
    });
    await syncHealthKitAggregates(
        "5b2216f4-762d-4890-a516-63046a01df31",
        healthKitAggregateSyncSchema.parse({
            complete_through: cutoffAt,
            time_zone: "Europe/Paris",
            merged_days: [],
            fight_aggregates: [
                {
                    fight_id: validAggregate.fight_aggregates[0].fight_id,
                    starts_at: startsAt,
                    ends_at: endsAt,
                    cutoff_at: cutoffAt,
                    steps: 7000,
                    step_checkpoints: [
                        {
                            day: "2026-03-28",
                            cutoff_at: "2026-03-28T23:00:00.000Z",
                            steps: 4000,
                        },
                        {
                            day: "2026-03-29",
                            cutoff_at: "2026-03-29T22:00:00.000Z",
                            steps: 7000,
                        },
                        {
                            day: "2026-03-30",
                            cutoff_at: cutoffAt,
                            steps: 7000,
                        },
                    ],
                },
            ],
        }),
        database,
    );
    const [fight] = receivedRecords(queries);
    assert.equal(fight.key, `fight:${validAggregate.fight_aggregates[0].fight_id.toLowerCase()}`);
    assert.equal(fight.payload.cutoff_at, cutoffAt);
    assert.equal((fight.payload.step_checkpoints as unknown[]).length, 3);
});

test("Apple Health aggregate sync accepts one merged total per Fight", () => {
    const parsed = healthKitAggregateSyncSchema.parse(validAggregate);

    assert.equal(parsed.time_zone, "Europe/Paris");
    assert.equal(parsed.merged_days[0]?.steps, 12_345);
    assert.equal(
        parsed.fight_aggregates[0]?.fight_id,
        "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
    );
    assert.equal(parsed.fight_aggregates[0]?.steps, 42_000);
});

test("Apple Health aggregate sync keeps extra activity optional", () => {
    const parsed = healthKitAggregateSyncSchema.parse({
        ...validAggregate,
        activity_days: [
            {
                day: "2026-08-30",
                starts_at: "2026-08-29T22:00:00.000Z",
                ends_at: "2026-08-30T13:53:27.350Z",
                metric: "active_energy",
                value: 420,
                unit: "kcal",
            },
        ],
        workouts: [
            {
                healthkit_uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                started_at: "2026-08-30T08:00:00.000Z",
                ended_at: "2026-08-30T09:00:00.000Z",
                activity_type: "running",
                duration_seconds: 3600,
                distance_m: 10_000,
                energy_kcal: 700,
                effort: 6,
            },
        ],
    });

    assert.equal(parsed.activity_days?.[0]?.metric, "active_energy");
    assert.equal(parsed.workouts?.[0]?.activity_type, "running");
});

test("Apple Health aggregate sync accepts resting energy and workout active minutes", () => {
    const parsed = healthKitAggregateSyncSchema.parse({
        ...validAggregate,
        activity_days: [
            {
                day: "2026-08-30",
                starts_at: "2026-08-29T22:00:00.000Z",
                ends_at: "2026-08-30T13:53:27.350Z",
                metric: "resting_energy",
                value: 1_540,
                unit: "kcal",
            },
        ],
        workouts: [
            {
                healthkit_uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                started_at: "2026-08-30T08:00:00.000Z",
                ended_at: "2026-08-30T09:00:00.000Z",
                activity_type: "running",
                duration_seconds: 3600,
                active_minutes: 58,
            },
        ],
    });

    assert.equal(parsed.activity_days?.[0]?.value, 1_540);
    assert.equal(parsed.workouts?.[0]?.active_minutes, 58);
});

test("Apple Health aggregate sync rejects a mismatched activity unit", () => {
    assert.throws(() =>
        healthKitAggregateSyncSchema.parse({
            ...validAggregate,
            activity_days: [
                {
                    day: "2026-08-30",
                    starts_at: "2026-08-29T22:00:00.000Z",
                    ends_at: "2026-08-30T13:53:27.350Z",
                    metric: "active_energy",
                    value: 420,
                    unit: "steps",
                },
            ],
        }),
    );
});

test("Apple Health aggregate sync keeps Steps when extra activity is invalid", (t) => {
    const warn = t.mock.method(console, "warn", () => {});
    const parsed = parseHealthKitAggregateSync({
        ...validAggregate,
        workouts: [
            {
                healthkit_uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                started_at: "2026-08-30T08:00:00.000Z",
                ended_at: "2026-08-30T18:00:00.000Z",
                activity_type: "running",
                duration_seconds: 3600,
            },
        ],
    });

    assert.equal(parsed.fight_aggregates[0]?.steps, 42_000);
    assert.equal(parsed.workouts, undefined);
    assert.equal(warn.mock.callCount(), 1);
    assert.equal(
        warn.mock.calls[0].arguments[0],
        "fitfight_healthkit_extras_dropped",
    );
});

test("Apple Health aggregate sync rejects raw HealthKit records", () => {
    assert.throws(() =>
        healthKitAggregateSyncSchema.parse({
            ...validAggregate,
            samples: [{ sample_id: "333822a8-8577-4d9d-8145-ab5f120ee42f" }],
        }),
    );
});

test("Apple Health aggregate sync requires the server-authoritative cutoff", () => {
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                fight_aggregates: [
                    {
                        ...validAggregate.fight_aggregates[0],
                        cutoff_at: "2026-08-30T12:00:00.000Z",
                    },
                ],
            }),
        /cutoff_at does not match complete_through/,
    );
});

test("Apple Health aggregate sync rejects an invalid merged-day range", () => {
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                merged_days: [
                    {
                        ...validAggregate.merged_days[0],
                        ends_at: validAggregate.merged_days[0].starts_at,
                    },
                ],
            }),
        /ends_at must follow starts_at/,
    );
});

test("Apple Health aggregate sync rejects duplicate merged days", () => {
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                merged_days: [
                    validAggregate.merged_days[0],
                    validAggregate.merged_days[0],
                ],
            }),
        /duplicate merged day/,
    );
});

test("Apple Health aggregate sync rejects a merged day beyond complete_through", () => {
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                merged_days: [
                    {
                        ...validAggregate.merged_days[0],
                        ends_at: "2026-08-30T22:00:00.000Z",
                    },
                ],
            }),
        /ends_at exceeds complete_through/,
    );
});

test("Apple Health aggregate sync requires complete civil-day bounds", () => {
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                merged_days: [
                    {
                        ...validAggregate.merged_days[0],
                        ends_at: "2026-08-30T13:00:00.000Z",
                    },
                ],
            }),
        /ends_at must equal the effective civil-day end/,
    );
});

test("Apple Health aggregate sync rejects duplicate Fights and invalid time zones", () => {
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                fight_aggregates: [
                    validAggregate.fight_aggregates[0],
                    validAggregate.fight_aggregates[0],
                ],
            }),
        /duplicate Fight aggregate/,
    );
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                time_zone: "Mars/Olympus_Mons",
            }),
        /invalid time zone/,
    );
});

test("Apple Health aggregate sync bounds aggregate counts", () => {
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                merged_days: Array.from(
                    { length: 401 },
                    () => validAggregate.merged_days[0],
                ),
            }),
        /at most 400/,
    );
    assert.throws(
        () =>
            healthKitAggregateSyncSchema.parse({
                ...validAggregate,
                fight_aggregates: Array.from(
                    { length: 101 },
                    () => validAggregate.fight_aggregates[0],
                ),
            }),
        /at most 100/,
    );
});

test("Apple Health aggregate upload query count stays bounded across fights", async () => {
    const statementCounts: number[] = [];
    const userId = "5b2216f4-762d-4890-a516-63046a01df31";
    for (const fightCount of [1, 5]) {
        const input = healthKitAggregateSyncSchema.parse({
            ...validAggregate,
            fight_aggregates: Array.from(
                { length: fightCount },
                (_, index) => ({
                    ...validAggregate.fight_aggregates[0],
                    fight_id: `b4c1285d-0232-4d15-b8cc-${String(index).padStart(12, "0")}`,
                }),
            ),
        });
        const fights = input.fight_aggregates.map((aggregate) => ({
            fight_id: aggregate.fight_id,
            starts_at: aggregate.starts_at,
            ends_at: aggregate.ends_at,
            outcome_rule: "highest_total",
            time_zone: "Europe/Paris",
            stake_minor: null,
            default_goal_value: null,
        }));
        const { database, queries } = createDatabaseStub((query) => {
            if (query.includes("returning id, complete_through"))
                return [sourceRow];
            if (query.includes("from public.fights as fight")) return fights;
            return [];
        });

        const result = await syncHealthKitAggregates(userId, input, database);
        assert.equal(result.synced_fights, fightCount);
        statementCounts.push(queries.length);
        assert.equal(
            receivedRecords(queries).filter((record) =>
                String(record.key).startsWith("fight:"),
            ).length,
            fightCount,
        );
    }

    assert.equal(
        statementCounts[1],
        statementCounts[0],
        "the number of Fights must not add database round trips",
    );
    assert.ok(
        statementCounts.every((count) => count <= 8),
        `expected at most 8 statements, got ${statementCounts}`,
    );
});

test("Apple Health aggregate sync records an empty successful sync transaction", async () => {
    const { database, queries } = createDatabaseStub((query) =>
        query.includes("returning id") ? [sourceRow] : [],
    );
    const input = healthKitAggregateSyncSchema.parse({
        ...validAggregate,
        merged_days: [],
        fight_aggregates: [],
    });

    const result = await syncHealthKitAggregates(
        "5b2216f4-762d-4890-a516-63046a01df31",
        input,
        database,
    );

    assert.deepEqual(result, {
        complete_through: "2026-08-30T13:53:27.350Z",
        synced_days: 0,
        synced_fights: 0,
        processing: "processed",
    });
    assert.deepEqual(
        healthKitAggregateSyncResponseSchema.parse(result),
        result,
    );
    assert.ok(
        queries.some(({ query }) =>
            query.includes("insert into public.data_sources"),
        ),
    );
});

test("Apple Health aggregate sync rejects future complete_through values", async () => {
    const futureCompleteThrough = "2026-08-30T15:00:00.000Z";
    const { database } = createDatabaseStub((query) =>
        query.includes("returning id")
            ? [
                  {
                      ...sourceRow,
                      complete_through: futureCompleteThrough,
                  },
              ]
            : [],
    );
    const input = healthKitAggregateSyncSchema.parse({
        complete_through: futureCompleteThrough,
        time_zone: "Europe/Paris",
        merged_days: [],
        fight_aggregates: [],
    });

    await assert.rejects(
        syncHealthKitAggregates(
            "5b2216f4-762d-4890-a516-63046a01df31",
            input,
            database,
        ),
        /complete_through cannot be in the future/,
    );
});

test("Apple Health aggregate sync rejects a stale checkpoint", async () => {
    const { database } = createDatabaseStub((query) =>
        query.includes("returning id")
            ? [
                  {
                      ...sourceRow,
                      complete_through: "2026-08-30T13:59:00.000Z",
                  },
              ]
            : [],
    );
    const input = healthKitAggregateSyncSchema.parse({
        ...validAggregate,
        merged_days: [],
        fight_aggregates: [],
    });

    await assert.rejects(
        syncHealthKitAggregates(
            "5b2216f4-762d-4890-a516-63046a01df31",
            input,
            database,
        ),
        /Sync is older than current Apple Health data/,
    );
});

test("Apple Health aggregate sync requires every server-context Fight", async () => {
    const { database } = createDatabaseStub((query) => {
        if (query.includes("returning id")) {
            return [sourceRow];
        }
        if (query.includes("from public.fights as fight")) {
            return [
                {
                    fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
                    starts_at: "2026-08-27 16:06:36.729+00",
                    ends_at: "2026-09-03 16:06:35.093+00",
                    outcome_rule: "highest_total",
                    time_zone: "Europe/Paris",
                    stake_minor: null,
                    default_goal_value: null,
                },
            ];
        }
        return [];
    });
    const input = healthKitAggregateSyncSchema.parse({
        ...validAggregate,
        merged_days: [],
        fight_aggregates: [],
    });

    await assert.rejects(
        syncHealthKitAggregates(
            "5b2216f4-762d-4890-a516-63046a01df31",
            input,
            database,
        ),
        /Fight aggregate set does not match sync context/,
    );
});

test("Apple Health aggregate sync rejects a Fight window that differs from the server", async () => {
    const { database } = createDatabaseStub((query) => {
        if (query.includes("returning id")) {
            return [sourceRow];
        }
        if (query.includes("from public.fights as fight")) {
            return [
                {
                    fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
                    starts_at: "2026-08-27 15:06:36.729+00",
                    ends_at: "2026-09-03 16:06:35.093+00",
                    outcome_rule: "highest_total",
                    time_zone: "Europe/Paris",
                    stake_minor: null,
                    default_goal_value: null,
                },
            ];
        }
        return [];
    });
    const input = healthKitAggregateSyncSchema.parse({
        ...validAggregate,
        merged_days: [],
    });

    await assert.rejects(
        syncHealthKitAggregates(
            "5b2216f4-762d-4890-a516-63046a01df31",
            input,
            database,
        ),
        /Fight aggregate does not match sync context/,
    );
});

test("Apple Health aggregate sync rejects merged days outside submitted Fights", async () => {
    const { database } = createDatabaseStub((query) => {
        if (query.includes("returning id")) {
            return [sourceRow];
        }
        if (query.includes("from public.fights as fight")) {
            return [
                {
                    fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
                    starts_at: "2026-08-27 16:06:36.729+00",
                    ends_at: "2026-09-03 16:06:35.093+00",
                    outcome_rule: "highest_total",
                    time_zone: "Europe/Paris",
                    stake_minor: null,
                    default_goal_value: null,
                },
            ];
        }
        return [];
    });
    const input = healthKitAggregateSyncSchema.parse({
        ...validAggregate,
        merged_days: [
            {
                day: "2026-08-25",
                starts_at: "2026-08-24T22:00:00.000Z",
                ends_at: "2026-08-25T22:00:00.000Z",
                steps: 9_000,
            },
        ],
    });

    await assert.rejects(
        syncHealthKitAggregates(
            "5b2216f4-762d-4890-a516-63046a01df31",
            input,
            database,
        ),
        /Merged day does not overlap a submitted Fight/,
    );
});

const liveFightRow = {
    fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
    starts_at: "2026-08-27 16:06:36.729+00",
    ends_at: "2026-09-03 16:06:35.093+00",
    outcome_rule: "highest_total",
    time_zone: "Europe/Paris",
    stake_minor: null,
    default_goal_value: null,
};

test("Apple Health aggregate sync receives every reading before resolving it", async () => {
    const { database, queries } = createDatabaseStub((query) => {
        if (query.includes("returning id, complete_through")) {
            return [sourceRow];
        }
        if (query.includes("from public.fights as fight")) {
            return [liveFightRow];
        }
        return [];
    });

    const result = await syncHealthKitAggregates(
        "5b2216f4-762d-4890-a516-63046a01df31",
        healthKitAggregateSyncSchema.parse({
            ...validAggregate,
            activity_days: [
                {
                    day: "2026-08-30",
                    starts_at: "2026-08-29T22:00:00.000Z",
                    ends_at: "2026-08-30T13:53:27.350Z",
                    metric: "exercise_minutes",
                    value: 32,
                    unit: "min",
                },
            ],
            workouts: [
                {
                    healthkit_uuid: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                    started_at: "2026-08-30T08:00:00.000Z",
                    ended_at: "2026-08-30T09:00:00.000Z",
                    activity_type: "running",
                    duration_seconds: 3600,
                    distance_m: 10_000,
                },
            ],
        }),
        database,
    );

    assert.equal(result.processing, "processed");
    assert.deepEqual(
        receivedRecords(queries).map(({ kind, type, key }) => ({ kind, type, key })),
        [
            { kind: "total", type: "steps", key: "fight:b4c1285d-0232-4d15-b8cc-1a916ba2bbf7" },
            { kind: "total", type: "steps", key: "day:2026-08-30" },
            { kind: "total", type: "exercise_minutes", key: "day:2026-08-30" },
            { kind: "workout", type: "workout", key: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" },
        ],
    );
    const [fight] = receivedRecords(queries);
    assert.deepEqual(fight.payload, {
        fight_id: "b4c1285d-0232-4d15-b8cc-1a916ba2bbf7",
        starts_at: "2026-08-27T16:06:36.729Z",
        ends_at: "2026-09-03T16:06:35.093Z",
        cutoff_at: "2026-08-30T13:53:27.350Z",
        time_zone: "Europe/Paris",
        steps: 42_000,
        step_checkpoints: null,
    });
    const intake = queries.findIndex(({ query }) =>
        query.includes("insert into private.activity_raw"),
    );
    const claim = queries.findIndex(({ query }) =>
        query.includes("set processing_state = 'processing'"),
    );
    assert.ok(intake >= 0 && claim > intake, "Readings are durable before resolution");
    for (const table of [
        "fight_score_snapshots",
        "metric_days",
        "healthkit_activity_days",
        "healthkit_workouts",
        "metric_observations",
        "provider_events",
    ]) {
        assert.ok(
            queries.slice(0, claim).every(({ query }) => !query.includes(table)),
            `${table} is written only by the resolver, if at all`,
        );
    }
});

test("Apple Health aggregate sync claims and reports only the readings it received", async () => {
    const intakeIds = [
        "6f1c1a52-0f55-4c1c-9b61-2f0f5e0f9a01",
        "6f1c1a52-0f55-4c1c-9b61-2f0f5e0f9a02",
    ];
    const { database, queries } = createDatabaseStub((query) => {
        if (query.includes("returning id, complete_through")) {
            return [sourceRow];
        }
        if (query.includes("from public.fights as fight")) {
            return [liveFightRow];
        }
        if (query.includes("insert into private.activity_raw")) {
            return intakeIds.map((id) => ({ id }));
        }
        return [];
    });

    const result = await syncHealthKitAggregates(
        "5b2216f4-762d-4890-a516-63046a01df31",
        healthKitAggregateSyncSchema.parse(validAggregate),
        database,
    );

    assert.equal(result.processing, "processed");
    for (const statement of ["set processing_state = 'processing'", "as count"]) {
        const found = queries.find(({ query }) => query.includes(statement));
        assert.deepEqual(
            found?.values.filter((value) => Array.isArray(value)),
            [intakeIds, intakeIds],
            "A Steps upload never claims or waits on the activity import's rows",
        );
    }
});

test("Apple Health aggregate sync ignores client workout day sums and never infers deletions", async () => {
    const { database, queries } = createDatabaseStub((query) => {
        if (query.includes("returning id, complete_through")) {
            return [sourceRow];
        }
        if (query.includes("from public.fights as fight")) {
            return [liveFightRow];
        }
        return [];
    });

    await syncHealthKitAggregates(
        "5b2216f4-762d-4890-a516-63046a01df31",
        healthKitAggregateSyncSchema.parse({
            ...validAggregate,
            merged_days: [],
            activity_days: [
                {
                    day: "2026-08-30",
                    starts_at: "2026-08-29T22:00:00.000Z",
                    ends_at: "2026-08-30T13:53:27.350Z",
                    metric: "workout_count",
                    value: 3,
                    unit: "count",
                },
            ],
            workouts: [],
        }),
        database,
    );

    assert.deepEqual(
        receivedRecords(queries).map(({ type }) => type),
        ["steps"],
    );
    assert.ok(queries.every(({ query }) => !query.includes("delete from")));
});

test("Apple Health Steps endpoint exposes the authenticated sync route", async () => {
    const route = await import("@/app/api/v1/healthkit/steps/route");

    assert.equal(route.runtime, "nodejs");
    assert.equal(typeof route.POST, "function");
    assert.equal(typeof route.OPTIONS, "function");
});

test("HealthKit diagnostics endpoint exposes the authenticated snapshot route", async () => {
    const route = await import("@/app/api/v1/healthkit/diagnostics/route");

    assert.equal(route.runtime, "nodejs");
    assert.equal(typeof route.POST, "function");
    assert.equal(typeof route.OPTIONS, "function");

    const response = await route.POST(
        new Request("https://fitfight.app/api/v1/healthkit/diagnostics", {
            method: "POST",
        }),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 401);
    assert.equal((await response.json()).code, "unauthorized");
});

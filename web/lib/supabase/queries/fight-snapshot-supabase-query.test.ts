import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { runInNewContext } from "node:vm";
import { ModuleKind, transpileModule } from "typescript";
import { z } from "zod";
import { readFightSnapshot } from "./fight-snapshot-supabase-query";
import { closeDueFightsForUser } from "./close-due-fights-supabase-query";
import {
    fightSnapshotRequestSchema,
    fightSnapshotSchema,
} from "@/lib/types/fights/fight-snapshot";

test("the shared native snapshot fixture preserves the API contract and strips internal fields", () => {
    const fixture = fightSnapshotSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/fight-snapshot.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    assert.deepEqual(
        fightSnapshotSchema.parse({
            ...fixture,
            future_field: true,
            profiles: fixture.profiles.map((profile) => ({
                ...profile,
                internal_column: "private",
            })),
        }),
        fixture,
    );
    assert.equal(fixture.fights[0].grace_ends_at, "2026-09-09T00:00:00Z");
    assert.equal(fixture.members[1].state, "deferred");
    assert.equal(fixture.members[0].current_value, 8500);
    assert.equal(fixture.profiles[0].companion_id, "fox");
    assert.equal(fixture.profiles[1].companion_id, null);
    assert.deepEqual(fixture.hosted, { name: "Fight Marc", rounds: 20, leading: 12 });
});

test("snapshot validates the requested timezone and returns five empty arrays", () => {
    assert.deepEqual(
        fightSnapshotRequestSchema.parse({ time_zone: "Europe/Paris" }),
        { time_zone: "Europe/Paris" },
    );
    assert.deepEqual(
        fightSnapshotRequestSchema.parse({ time_zone: "UTC", hosted: true }),
        { time_zone: "UTC", hosted: true },
    );
    assert.equal(
        fightSnapshotRequestSchema.safeParse({ time_zone: "Mars/Olympus" })
            .success,
        false,
    );
    assert.equal(
        fightSnapshotRequestSchema.safeParse({
            time_zone: "UTC",
            user_id: "someone-else",
        }).success,
        false,
    );
    assert.deepEqual(
        fightSnapshotSchema.parse({
            fights: [],
            members: [],
            profiles: [],
            series: [],
            step_days: [],
            hosted: null,
        }),
        { fights: [], members: [], profiles: [], series: [], step_days: [], hosted: null },
    );
});

test("the friends flag is optional and strict, so older requests keep their meaning", () => {
    assert.deepEqual(
        fightSnapshotRequestSchema.parse({ time_zone: "UTC", friends: true }),
        { time_zone: "UTC", friends: true },
    );
    assert.equal(
        fightSnapshotRequestSchema.safeParse({ time_zone: "UTC", friends: "yes" }).success,
        false,
    );
    assert.equal(
        fightSnapshotRequestSchema.safeParse({ time_zone: "UTC", friends: true, rounds: 3 }).success,
        false,
    );
    const legacy = fightSnapshotRequestSchema.parse({ time_zone: "UTC", hosted: true });
    assert.equal("friends" in legacy, false, "an older request never asks for friend rounds");
});

test("the friend rounds fixture carries the Friends summary and marks every round", () => {
    const raw = JSON.parse(
        readFileSync(
            new URL(
                "../../../../contracts/fixtures/fight-snapshot-friends.json",
                import.meta.url,
            ),
            "utf8",
        ),
    );
    const fixture = fightSnapshotSchema.parse(raw);
    assert.deepEqual(fixture, raw);
    assert.deepEqual(fixture.friends, { rounds: 1, leading: 1, requests: 2 });
    assert.ok(fixture.fights.every((fight) => fight.friends === true));
    assert.equal(fixture.fights[0].name, "Friends");
    assert.equal(fixture.hosted, null);
    assert.ok(fixture.members.every((member) => member.state === "accepted"));
});

test("on the 1st a friend appears in this month and last month, and only this month is counted", () => {
    const raw = JSON.parse(
        readFileSync(
            new URL(
                "../../../../contracts/fixtures/fight-snapshot-friends-month-turn.json",
                import.meta.url,
            ),
            "utf8",
        ),
    );
    const fixture = fightSnapshotSchema.parse(raw);
    assert.deepEqual(fixture, raw);
    const now = Date.parse("2026-11-01T06:00:00Z");
    const [last, current] = fixture.fights;
    assert.equal(last.series_id, current.series_id);
    assert.ok(Date.parse(last.ends_at) <= now && last.state === "awaiting_final_sync");
    assert.ok(Date.parse(current.ends_at) > now && current.state === "live");
    assert.deepEqual(fixture.friends, { rounds: 1, leading: 1, requests: 0 });
});

test("older snapshot responses without friend fields still parse unchanged", () => {
    for (const name of ["fight-snapshot", "fight-snapshot-checkpoints"]) {
        const raw = JSON.parse(
            readFileSync(
                new URL(`../../../../contracts/fixtures/${name}.json`, import.meta.url),
                "utf8",
            ),
        );
        const fixture = fightSnapshotSchema.parse(raw);
        assert.equal("friends" in fixture, false);
        assert.ok(fixture.fights.every((fight) => !("friends" in fight)));
    }
});

test("checkpoint snapshots preserve legacy scores and publish matching cumulative history", () => {
    const fixture = fightSnapshotSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/fight-snapshot-checkpoints.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    assert.equal(
        fixture.members[0].step_checkpoints?.at(-1)?.steps,
        fixture.members[0].current_value,
    );
    assert.equal(fixture.members[1].step_checkpoints, null);
    assert.equal(fixture.step_days[0].steps, 8500);
});

test("snapshot establishes transaction-local caller permissions before its single data query", async () => {
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const snapshot = {
        fights: [],
        members: [],
        profiles: [],
        series: [],
        step_days: [],
        hosted: null,
        friends: { rounds: 0, leading: 0, requests: 2 },
    };
    const friendId = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb";
    const calls: Array<{ query: string; values: unknown[] }> = [];
    const sql = Object.assign(
        async (strings: TemplateStringsArray, ...values: unknown[]) => {
            const query = strings.join("?");
            calls.push({ query, values });
            if (query.includes("private.profile_friendships")) {
                return [{ requests: 2, friend_ids: [friendId] }];
            }
            return query.includes("as snapshot") ? [{ snapshot }] : [];
        },
        { array: (values: unknown[]) => values },
    );
    const database = {
        begin: async (
            options: string,
            callback: (transaction: typeof sql) => Promise<unknown>,
        ) => {
            assert.equal(options, "read only");
            return callback(sql);
        },
    };
    assert.deepEqual(
        await readFightSnapshot(userId, "Europe/Paris", database as never),
        snapshot,
    );
    // Private friendships are read (calls[0]) before the role drops; the visibility
    // condition is a nested fragment (calls[3]) inside the one data query.
    assert.equal(calls.length, 5);
    assert.match(calls[0].query, /friendship.state = 'pending'/);
    assert.match(calls[0].query, /array_agg\(profile.id\) filter \(where friendship.state = 'accepted'\)/);
    assert.match(calls[3].query, /not fight.friends and fight.host_id is distinct from/);
    assert.equal(calls[1].query, "set local role fitfight_backend_reader");
    assert.ok(
        calls[2].query.includes("set_config('request.jwt.claim.sub', ?, true)"),
    );
    assert.deepEqual(calls[2].values, [
        userId,
        JSON.stringify({ sub: userId, role: "authenticated" }),
    ]);
    assert.ok(calls[4].values.includes("Europe/Paris"));
    assert.ok(calls[4].values.includes(2), "the request count reaches the Friends summary");
    assert.ok(
        calls[4].values.some((value) => Array.isArray(value) && value.includes(friendId)),
        "the summary counts only rounds with a current friend",
    );
    assert.match(calls[4].query, /fight.state = 'live' and fight.ends_at > now\(\)\s*\)\s*\) as snapshot/);
    assert.match(calls[4].query, /as grace_ends_at/);
    assert.match(calls[4].query, /avatar_media_id/);
    assert.match(calls[4].query, /companion_id/);
    assert.match(calls[4].query, /select snapshot.value, snapshot.step_checkpoints/);
    assert.doesNotMatch(calls[4].query, /as final_sync_grace_seconds/);
});

test("the friends and hosted flags each select only their own rounds", async () => {
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const snapshot = {
        fights: [],
        members: [],
        profiles: [],
        series: [],
        step_days: [],
        hosted: null,
        friends: { rounds: 0, leading: 0, requests: 0 },
    };
    const filters: string[] = [];
    const database = {
        begin: async (
            _options: string,
            callback: (
                transaction: (
                    strings: TemplateStringsArray,
                    ...values: unknown[]
                ) => Promise<unknown>,
            ) => Promise<unknown>,
        ) =>
            callback(
                Object.assign(
                    async (strings: TemplateStringsArray) => {
                        const query = strings.join("?");
                        if (query.includes("private.profile_friendships")) {
                            return [{ requests: 0, friend_ids: [] }];
                        }
                        if (query.includes("as snapshot")) return [{ snapshot }];
                        if (query.includes("fight.")) filters.push(query);
                        return [];
                    },
                    { array: (values: unknown[]) => values },
                ),
            ),
    };
    await readFightSnapshot(userId, "UTC", database as never, false, true);
    await readFightSnapshot(userId, "UTC", database as never, true);
    assert.equal(filters.length, 2);
    assert.match(filters[0], /^fight\.friends\s+and fight\.id in \(\s*select fight_id from public\.fight_members where user_id = \? and state = 'accepted'/);
    assert.match(filters[0], /friend\.user_id = any\(\?::uuid\[\]\)/);
    assert.match(filters[0], /\(fight\.state = 'live' and fight\.ends_at > now\(\)\)/);
    assert.match(filters[0], /last\.ends_at > now\(\) - interval '7 days'/);
    assert.match(filters[0], /last\.state in \('live', 'awaiting_final_sync', 'final'\)/);
    assert.doesNotMatch(filters[0], /host_id/);
    assert.match(filters[1], /^fight\.host_id = \?/);
    assert.doesNotMatch(filters[1], /friends/);
});

test("snapshot profiles without a photo come back with a null avatar", async () => {
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const snapshot = {
        fights: [],
        members: [],
        profiles: [
            { user_id: userId, handle: "marc", display_name: "Marc Lamy" },
        ],
        series: [],
        step_days: [],
        hosted: null,
        friends: { rounds: 0, leading: 0, requests: 0 },
    };
    const database = {
        begin: async (
            _options: string,
            callback: (
                transaction: (
                    strings: TemplateStringsArray,
                    ...values: unknown[]
                ) => Promise<unknown>,
            ) => Promise<unknown>,
        ) => {
            const sql = Object.assign(
                async (strings: TemplateStringsArray, ..._values: unknown[]) => {
                    const query = strings.join("?");
                    if (query.includes("private.profile_friendships")) {
                        return [{ requests: 0, friend_ids: [] }];
                    }
                    return query.includes("as snapshot") ? [{ snapshot }] : [];
                },
                { array: (values: unknown[]) => values },
            );
            return callback(sql);
        },
    };
    assert.deepEqual(
        await readFightSnapshot(userId, "Europe/Paris", database as never),
        {
            ...snapshot,
            profiles: [
                {
                    user_id: userId,
                    handle: "marc",
                    display_name: "Marc Lamy",
                    avatar: null,
                    companion_id: null,
                },
            ],
        },
    );
});

test("ordinary maintenance uses one database query and never scans unrelated series over REST", async () => {
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const now = new Date("2026-09-05T12:00:00Z");
    let statements = 0;
    const database = async (
        strings: TemplateStringsArray,
        ...values: unknown[]
    ) => {
        const query = strings.join("?");
        // A nested fragment runs inside the statement that embeds it.
        if (query.trimStart().startsWith("case")) return [];
        statements++;
        if (query.includes("coalesce((")) {
            assert.ok(values.includes(userId));
            return [
                {
                    candidates: [
                        {
                            id: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                            state: "live",
                            starts_at: "2026-09-04T12:00:00Z",
                            ends_at: "2026-09-07T12:00:00Z",
                        },
                    ],
                    recurring: [],
                },
            ];
        }
        return [];
    };
    const admin = {
        from: () => {
            throw new Error("ordinary refresh must not scan REST tables");
        },
    };
    assert.deepEqual(
        await closeDueFightsForUser(
            userId,
            admin as never,
            now,
            database as never,
        ),
        {
            checked: 1,
            closed: 0,
            fightIds: [],
        },
    );
    assert.equal(statements, 1);
});

test("refresh endpoint rejects unauthenticated requests before maintenance and emits timing", async () => {
    const { POST } = await import("@/app/api/v1/fights/refresh/route");
    const traceId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const response = await POST(
        new Request("https://fitfight.app/api/v1/fights/refresh", {
            method: "POST",
            headers: { "X-FitFight-Trace-ID": traceId },
        }),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 401);
    assert.equal(response.headers.get("X-FitFight-Trace-ID"), traceId);
    assert.match(
        response.headers.get("Server-Timing") ?? "",
        /auth;dur=[\d.]+, total;dur=[\d.]+/,
    );
    assert.equal((await response.json()).code, "unauthorized");
});

test("refresh answers after the caller's maintenance and delivers notifications after the response", async () => {
    const userId = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
    const snapshot = {
        fights: [],
        members: [],
        profiles: [],
        series: [],
        step_days: [],
        hosted: null,
    };
    const database = {};
    const steps: string[] = [];
    const deferred: Array<() => Promise<unknown>> = [];
    const exports: Record<string, unknown> = {};
    const require = createRequire(import.meta.url);
    // Run the production handler with only its data and delivery boundaries replaced.
    const { outputText } = transpileModule(
        readFileSync(
            new URL(
                "../../../app/api/v1/fights/refresh/route.ts",
                import.meta.url,
            ),
            "utf8",
        ),
        { compilerOptions: { module: ModuleKind.CommonJS } },
    );
    runInNewContext(outputText, {
        exports,
        require(specifier: string) {
            if (specifier === "next/server") {
                return {
                    after: (task: () => Promise<unknown>) =>
                        deferred.push(task),
                };
            }
            if (specifier.endsWith("/auth-supabase-query")) {
                return { verifyUser: async () => ({ userId }) };
            }
            if (specifier.endsWith("/supabase/postgres")) {
                return { createDatabaseClient: () => database };
            }
            if (specifier.endsWith("/app-wide-fight-invite-supabase-query")) {
                return {
                    ensureAppWideFightInvite: async () => {
                        steps.push("invite");
                    },
                };
            }
            if (specifier.endsWith("/close-due-fights-supabase-query")) {
                return {
                    closeDueFightsForUser: async () => {
                        steps.push("close");
                    },
                    processDueNotifications: async (
                        _now: Date,
                        sql: unknown,
                    ) => {
                        assert.equal(sql, database);
                        steps.push("notifications");
                        throw new Error("APNs transport unavailable");
                    },
                };
            }
            if (specifier.endsWith("/friend-fights-supabase-query")) {
                return {
                    ensureFriendFights: async (sql: unknown, user: string) => {
                        assert.equal(sql, database);
                        assert.equal(user, userId);
                        steps.push("friends");
                    },
                };
            }
            if (specifier.endsWith("/fight-snapshot-supabase-query")) {
                return {
                    readFightSnapshot: async () => {
                        steps.push("snapshot");
                        return snapshot;
                    },
                };
            }
            return require(specifier);
        },
    });
    const handler = z.function().parse(exports.POST);
    const response = z.instanceof(Response).parse(
        await handler(
            new Request("https://fitfight.app/api/v1/fights/refresh", {
                method: "POST",
                body: JSON.stringify({ time_zone: "UTC" }),
            }),
            { params: Promise.resolve({}) },
        ),
    );
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), snapshot);
    assert.deepEqual(
        steps,
        ["invite", "close", "friends", "snapshot"],
        "Refresh backfills friend rounds before reading, and must not wait for every account's notifications",
    );
    assert.equal(deferred.length, 1);
    await assert.rejects(deferred[0](), /APNs transport unavailable/);
    assert.deepEqual(steps, ["invite", "close", "friends", "snapshot", "notifications"]);
});

test("live snapshot endpoint authenticates before reading and never caches responses", async () => {
    const { POST } = await import("@/app/api/v1/fights/snapshot/route");
    const response = await POST(
        new Request("https://fitfight.app/api/v1/fights/snapshot", {
            method: "POST",
            body: JSON.stringify({ time_zone: "UTC" }),
        }),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 401);
    assert.match(response.headers.get("Cache-Control") ?? "", /no-store/);
    assert.equal((await response.json()).code, "unauthorized");
});

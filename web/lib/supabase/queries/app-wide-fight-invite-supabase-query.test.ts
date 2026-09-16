import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import { APP_WIDE_JOIN_CODE } from "@/lib/domain/fights/join-code";
import {
    ensureAppWideFightInvite,
    inviteEveryoneToOpenFight,
} from "./app-wide-fight-invite-supabase-query";

const now = new Date("2026-09-16T20:00:00Z");
const seriesId = "b798e7ee-8a94-445b-b290-5f9a02fc4b63";
const fightId = "9c112f63-a449-45f4-b1ee-9af9649583fd";
const ownerId = "87434630-dd64-4465-b79b-fd99e35368be";

const liveSeries = {
    id: seriesId,
    owner_id: ownerId,
    join_code: APP_WIDE_JOIN_CODE,
    visibility: "joinable" as const,
    recurring: true,
    duration_seconds: 604800,
    name: "EVERYBODY ON THE APP",
    action_text: null,
    time_zone: "UTC",
    paused_at: null,
    current_fight_id: fightId,
    created_at: "2026-09-14T22:09:53Z",
    suggested: true,
    suggested_at: "2026-09-14T22:09:53Z",
};

const liveFight = {
    id: fightId,
    owner_id: ownerId,
    name: "EVERYBODY ON THE APP",
    state: "live",
    starts_at: "2026-09-14T22:09:53Z",
    ends_at: "2026-09-21T22:09:53Z",
    time_zone: "UTC",
    series_id: seriesId,
};

function json(body: unknown, status = 200) {
    return Response.json(body, { status });
}

function seriesResponse(url: URL, coded: unknown[], suggested: unknown[]) {
    if (url.searchParams.get("join_code") === `eq.${APP_WIDE_JOIN_CODE}`) {
        return json(coded);
    }
    if (url.searchParams.get("suggested") === "eq.true") {
        return json(suggested);
    }
    throw new Error(`Unexpected series query ${url.search}`);
}

test("missing PGG7 series is a no-op and never invents a fight", async () => {
    const writes: string[] = [];
    const admin = createClient("https://pgg7.example", "test-only-key", {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
            fetch: async (input, init) => {
                const request = new Request(input, init);
                const url = new URL(request.url);
                if (url.pathname.endsWith("/fight_series")) {
                    return seriesResponse(url, [], []);
                }
                writes.push(`${request.method} ${url.pathname}`);
                throw new Error(`Unexpected resource ${url.pathname}`);
            },
        },
    });
    assert.equal(
        await ensureAppWideFightInvite(randomUUID(), admin, now),
        "missing",
    );
    assert.deepEqual(writes, []);
});

test("paused or closed PGG7 fights stay untouched", async () => {
    for (const fixture of [
        {
            series: { ...liveSeries, paused_at: "2026-09-16T00:00:00Z" },
            fight: liveFight,
            expected: "closed" as const,
        },
        {
            series: liveSeries,
            fight: { ...liveFight, state: "final" },
            expected: "closed" as const,
        },
    ]) {
        const writes: string[] = [];
        const admin = createClient("https://pgg7.example", "test-only-key", {
            auth: { persistSession: false, autoRefreshToken: false },
            global: {
                fetch: async (input, init) => {
                    const request = new Request(input, init);
                    const url = new URL(request.url);
                    if (url.pathname.endsWith("/fight_series")) {
                        return seriesResponse(
                            url,
                            [fixture.series],
                            fixture.series.paused_at ? [] : [fixture.series],
                        );
                    }
                    if (url.pathname.endsWith("/fights")) {
                        return json([fixture.fight]);
                    }
                    writes.push(`${request.method} ${url.pathname}`);
                    throw new Error(`Unexpected resource ${url.pathname}`);
                },
            },
        });
        assert.equal(
            await ensureAppWideFightInvite(randomUUID(), admin, now),
            fixture.expected,
        );
        assert.deepEqual(writes, []);
    }
});

test("existing members and invitees are not invited again", async () => {
    for (const state of [
        "accepted",
        "deferred",
        "invited",
        "declined",
        "withdrawn",
        "disqualified",
    ] as const) {
        const writes: string[] = [];
        const admin = createClient("https://pgg7.example", "test-only-key", {
            auth: { persistSession: false, autoRefreshToken: false },
            global: {
                fetch: async (input, init) => {
                    const request = new Request(input, init);
                    const url = new URL(request.url);
                    if (url.pathname.endsWith("/fight_series")) {
                        return seriesResponse(url, [liveSeries], [liveSeries]);
                    }
                    if (url.pathname.endsWith("/fights")) {
                        return json([liveFight]);
                    }
                    if (url.pathname.endsWith("/fight_members")) {
                        assert.equal(request.method, "GET");
                        return json([
                            {
                                fight_id: fightId,
                                user_id: "user",
                                state,
                            },
                        ]);
                    }
                    writes.push(`${request.method} ${url.pathname}`);
                    throw new Error(`Unexpected resource ${url.pathname}`);
                },
            },
        });
        assert.equal(
            await ensureAppWideFightInvite(randomUUID(), admin, now),
            "already",
        );
        assert.deepEqual(writes, []);
    }
});

test("the series owner is not invited to their own fight", async () => {
    const writes: string[] = [];
    const admin = createClient("https://pgg7.example", "test-only-key", {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
            fetch: async (input, init) => {
                const request = new Request(input, init);
                const url = new URL(request.url);
                if (url.pathname.endsWith("/fight_series")) {
                    return seriesResponse(url, [liveSeries], [liveSeries]);
                }
                if (url.pathname.endsWith("/fights")) {
                    return json([liveFight]);
                }
                writes.push(`${request.method} ${url.pathname}`);
                throw new Error(`Unexpected resource ${url.pathname}`);
            },
        },
    });
    assert.equal(await ensureAppWideFightInvite(ownerId, admin, now), "already");
    assert.deepEqual(writes, []);
});

test("a new signed-in user gets an invited membership, not an auto-join", async () => {
    const userId = randomUUID();
    const writes: Array<{ path: string; body: unknown }> = [];
    const admin = createClient("https://pgg7.example", "test-only-key", {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
            fetch: async (input, init) => {
                const request = new Request(input, init);
                const url = new URL(request.url);
                if (url.pathname.endsWith("/fight_series")) {
                    return seriesResponse(url, [liveSeries], [liveSeries]);
                }
                if (url.pathname.endsWith("/fights")) {
                    return json([liveFight]);
                }
                if (url.pathname.endsWith("/fight_members")) {
                    if (request.method === "GET") return json([]);
                    const body = await request.json();
                    writes.push({ path: url.pathname, body });
                    return new Response(null, { status: 201 });
                }
                if (url.pathname.endsWith("/fight_series_members")) {
                    if (request.method === "GET") return json([]);
                    const body = await request.json();
                    writes.push({ path: url.pathname, body });
                    return new Response(null, { status: 201 });
                }
                if (url.pathname.endsWith("/fight_invites")) {
                    const body = await request.json();
                    writes.push({ path: url.pathname, body });
                    return new Response(null, { status: 201 });
                }
                throw new Error(`Unexpected resource ${url.pathname}`);
            },
        },
    });
    assert.equal(await ensureAppWideFightInvite(userId, admin, now), "invited");
    assert.deepEqual(
        writes.map((write) => write.path),
        [
            "/rest/v1/fight_members",
            "/rest/v1/fight_series_members",
            "/rest/v1/fight_invites",
        ],
    );
    assert.deepEqual(writes[0].body, {
        fight_id: fightId,
        user_id: userId,
        state: "invited",
    });
});

test("login also invites the user to another suggested fight", async () => {
    const userId = randomUUID();
    const extraSeries = {
        ...liveSeries,
        id: "11111111-1111-4111-8111-111111111111",
        join_code: "K7M2",
        name: "Office walk",
        current_fight_id: "22222222-2222-4222-8222-222222222222",
    };
    const extraFight = {
        ...liveFight,
        id: extraSeries.current_fight_id,
        series_id: extraSeries.id,
        name: extraSeries.name,
    };
    const invitedFightIds: string[] = [];
    const admin = createClient("https://pgg7.example", "test-only-key", {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
            fetch: async (input, init) => {
                const request = new Request(input, init);
                const url = new URL(request.url);
                if (url.pathname.endsWith("/fight_series")) {
                    return seriesResponse(url, [liveSeries], [extraSeries]);
                }
                if (url.pathname.endsWith("/fights")) {
                    const id = url.searchParams.get("id");
                    const fight =
                        id === `eq.${extraFight.id}` ? extraFight : liveFight;
                    return json([fight]);
                }
                if (url.pathname.endsWith("/fight_members")) {
                    if (request.method === "GET") return json([]);
                    const body = (await request.json()) as { fight_id: string };
                    invitedFightIds.push(body.fight_id);
                    return new Response(null, { status: 201 });
                }
                if (url.pathname.endsWith("/fight_series_members")) {
                    return request.method === "GET"
                        ? json([])
                        : new Response(null, { status: 201 });
                }
                if (url.pathname.endsWith("/fight_invites")) {
                    return new Response(null, { status: 201 });
                }
                throw new Error(`Unexpected resource ${url.pathname}`);
            },
        },
    });
    assert.equal(await ensureAppWideFightInvite(userId, admin, now), "invited");
    assert.deepEqual(invitedFightIds.sort(), [fightId, extraFight.id].sort());
});

test("a concurrent invite insert is treated as already invited", async () => {
    const admin = createClient("https://pgg7.example", "test-only-key", {
        auth: { persistSession: false, autoRefreshToken: false },
        global: {
            fetch: async (input, init) => {
                const request = new Request(input, init);
                const url = new URL(request.url);
                if (url.pathname.endsWith("/fight_series")) {
                    return seriesResponse(url, [liveSeries], [liveSeries]);
                }
                if (url.pathname.endsWith("/fights")) {
                    return json([liveFight]);
                }
                if (url.pathname.endsWith("/fight_members")) {
                    if (request.method === "GET") return json([]);
                    return json(
                        {
                            code: "23505",
                            message: "duplicate key",
                        },
                        409,
                    );
                }
                throw new Error(`Unexpected resource ${url.pathname}`);
            },
        },
    });
    assert.equal(
        await ensureAppWideFightInvite(randomUUID(), admin, now),
        "already",
    );
});

test("suggesting a fight invites every eligible profile once", async () => {
    const extraUser = randomUUID();
    const statements: string[] = [];
    const sql = Object.assign(
        async (strings: TemplateStringsArray) => {
            const query = strings.join("?");
            statements.push(query);
            if (query.includes("insert into public.fight_members")) {
                return [{ user_id: extraUser }];
            }
            return [];
        },
        {},
    );
    const invited = await inviteEveryoneToOpenFight(
        liveSeries,
        liveFight as never,
        sql as never,
    );
    assert.deepEqual(invited, [extraUser]);
    assert.equal(
        statements.some((query) => query.includes("fight_members")),
        true,
    );
    assert.equal(
        statements.some((query) => query.includes("fight_series_members")),
        true,
    );
    assert.equal(
        statements.some((query) => query.includes("fight_invites")),
        true,
    );
});

import assert from "node:assert/strict";
import { test } from "node:test";
import { ApiError } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";

const owner = "11111111-1111-4111-8111-111111111111";
const other = "33333333-3333-4333-8333-333333333333";
const fightId = "22222222-2222-4222-8222-222222222222";
const seriesId = "44444444-4444-4444-8444-444444444444";
const startsAt = "2026-09-14T12:00:00.000Z";
const endsAt = "2026-09-21T12:00:00.000Z";
const now = new Date("2026-09-15T09:00:00.000Z");

function withSupabaseEnv(t: { after: (fn: () => void) => void }) {
    const savedURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const savedKey = process.env.SUPABASE_SECRET_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        process.env.NEXT_PUBLIC_SUPABASE_URL || "https://cancel-fight.example";
    process.env.SUPABASE_SECRET_KEY =
        process.env.SUPABASE_SECRET_KEY || "test-only-key";
    t.after(() => {
        if (savedURL === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = savedURL;
        if (savedKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
        else process.env.SUPABASE_SECRET_KEY = savedKey;
    });
}

test("owner can delete a live fight and pause its series", async (t) => {
    withSupabaseEnv(t);
    const patches: string[] = [];
    t.mock.method(
        globalThis,
        "fetch",
        async (input: RequestInfo | URL, init?: RequestInit) => {
            const request = new Request(input, init);
            const url = new URL(request.url);
            switch (url.pathname) {
                case "/rest/v1/fights":
                    if (request.method === "GET") {
                        return Response.json([
                            {
                                id: fightId,
                                owner_id: owner,
                                name: "Office steps",
                                state: "live",
                                starts_at: startsAt,
                                ends_at: endsAt,
                                action_text: "Cook dinner",
                                series_id: seriesId,
                            },
                        ]);
                    }
                    assert.equal(request.method, "PATCH");
                    patches.push("fight");
                    assert.deepEqual(await request.json(), {
                        state: "cancelled",
                    });
                    return Response.json({ id: fightId, state: "cancelled" });
                case "/rest/v1/fight_series":
                    assert.equal(request.method, "PATCH");
                    patches.push("series");
                    assert.deepEqual(await request.json(), {
                        paused_at: now.toISOString(),
                    });
                    return new Response(null, { status: 204 });
                default:
                    throw new Error(`Unexpected query: ${url.pathname}`);
            }
        },
    );

    const { cancelFight } = await import("./cancel-fight-supabase-query");
    const result = await cancelFight(owner, fightId, createAdminClient(), now);
    assert.deepEqual(result, { id: fightId, state: "cancelled" });
    assert.deepEqual(patches, ["series", "fight"]);
});

test("only the owner can delete, and final fights stay frozen", async (t) => {
    withSupabaseEnv(t);
    t.mock.method(
        globalThis,
        "fetch",
        async (input: RequestInfo | URL, init?: RequestInit) => {
            const request = new Request(input, init);
            const url = new URL(request.url);
            assert.equal(url.pathname, "/rest/v1/fights");
            return Response.json([
                {
                    id: fightId,
                    owner_id: owner,
                    name: "Office steps",
                    state: "final",
                    starts_at: startsAt,
                    ends_at: endsAt,
                    action_text: "Cook dinner",
                    series_id: seriesId,
                },
            ]);
        },
    );

    const { cancelFight } = await import("./cancel-fight-supabase-query");
    await assert.rejects(
        () => cancelFight(other, fightId),
        (error: unknown) => error instanceof ApiError && error.status === 403,
    );
    await assert.rejects(
        () => cancelFight(owner, fightId),
        (error: unknown) =>
            error instanceof ApiError &&
            error.status === 409 &&
            error.message.includes("cannot be cancelled"),
    );
});

test("a cancelled fight still pauses its series on retry", async (t) => {
    withSupabaseEnv(t);
    let seriesPatches = 0;
    t.mock.method(
        globalThis,
        "fetch",
        async (input: RequestInfo | URL, init?: RequestInit) => {
            const request = new Request(input, init);
            const url = new URL(request.url);
            switch (url.pathname) {
                case "/rest/v1/fights":
                    assert.equal(request.method, "GET");
                    return Response.json([
                        {
                            id: fightId,
                            owner_id: owner,
                            name: "Office steps",
                            state: "cancelled",
                            starts_at: startsAt,
                            ends_at: endsAt,
                            action_text: "Cook dinner",
                            series_id: seriesId,
                        },
                    ]);
                case "/rest/v1/fight_series":
                    assert.equal(request.method, "PATCH");
                    seriesPatches += 1;
                    assert.deepEqual(await request.json(), {
                        paused_at: now.toISOString(),
                    });
                    return new Response(null, { status: 204 });
                default:
                    throw new Error(`Unexpected query: ${url.pathname}`);
            }
        },
    );

    const { cancelFight } = await import("./cancel-fight-supabase-query");
    const result = await cancelFight(owner, fightId, createAdminClient(), now);
    assert.deepEqual(result, { id: fightId, state: "cancelled" });
    assert.equal(seriesPatches, 1);
});

test("a failed pause leaves a live fight uncancelled", async (t) => {
    withSupabaseEnv(t);
    let fightPatches = 0;
    t.mock.method(
        globalThis,
        "fetch",
        async (input: RequestInfo | URL, init?: RequestInit) => {
            const request = new Request(input, init);
            const url = new URL(request.url);
            switch (url.pathname) {
                case "/rest/v1/fights":
                    if (request.method === "GET") {
                        return Response.json([
                            {
                                id: fightId,
                                owner_id: owner,
                                name: "Office steps",
                                state: "live",
                                starts_at: startsAt,
                                ends_at: endsAt,
                                action_text: "Cook dinner",
                                series_id: seriesId,
                            },
                        ]);
                    }
                    fightPatches += 1;
                    throw new Error("fight must stay live when pause fails");
                case "/rest/v1/fight_series":
                    assert.equal(request.method, "PATCH");
                    return Response.json(
                        { message: "pause failed", code: "PGRST301" },
                        { status: 400 },
                    );
                default:
                    throw new Error(`Unexpected query: ${url.pathname}`);
            }
        },
    );

    const { cancelFight } = await import("./cancel-fight-supabase-query");
    await assert.rejects(
        () => cancelFight(owner, fightId, createAdminClient(), now),
        (error: unknown) => error instanceof ApiError && error.status === 500,
    );
    assert.equal(fightPatches, 0);
});

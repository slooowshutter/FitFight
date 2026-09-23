import assert from "node:assert/strict";
import { test } from "node:test";
import { createClient } from "@supabase/supabase-js";
import { ApiError } from "@/lib/http";
import { updateFightRequestSchema } from "@/lib/types/fights/update-fight";

const owner = "11111111-1111-4111-8111-111111111111";
const other = "33333333-3333-4333-8333-333333333333";
const fightId = "22222222-2222-4222-8222-222222222222";
const seriesId = "44444444-4444-4444-8444-444444444444";
const startsAt = "2026-09-14T12:00:00.000Z";
const endsAt = "2026-09-21T12:00:00.000Z";

test("owner update accepts title, action, privacy, roster, and window fields", () => {
    const parsed = updateFightRequestSchema.parse({
        name: "Office steps",
        actionText: "Cook dinner",
        visibility: "invite_only",
        recurring: false,
        endsAt,
        inviteHandles: ["leo_runs"],
        removeUserIds: [other],
    });
    assert.equal(parsed.visibility, "invite_only");
    assert.equal(parsed.recurring, false);
    assert.deepEqual(parsed.inviteHandles, ["leo_runs"]);
    assert.deepEqual(parsed.removeUserIds, [other]);
});

test("owner update rejects an empty patch and a reversed window", () => {
    assert.equal(updateFightRequestSchema.safeParse({ timeZone: "Nowhere/Invalid" }).success, false);
    assert.deepEqual(updateFightRequestSchema.parse({ timeZone: "Europe/Paris" }), { timeZone: "Europe/Paris" });
    assert.equal(updateFightRequestSchema.safeParse({}).success, false);
    assert.equal(
        updateFightRequestSchema.safeParse({ inviteHandles: [] }).success,
        false,
    );
    assert.equal(
        updateFightRequestSchema.safeParse({
            startsAt: endsAt,
            endsAt: startsAt,
        }).success,
        false,
    );
});

test("saved Fight zones update before the start and cannot change once that instant passes", async () => {
    const fight = {
        id: fightId, owner_id: owner, name: "Steps Fight", state: "scheduled",
        starts_at: startsAt, ends_at: endsAt, action_text: null, series_id: seriesId, time_zone: "UTC",
    };
    const patches: string[] = [];
    const admin = createClient("https://update-fight.example", "test-only-key", {
        auth: { persistSession: false, autoRefreshToken: false },
        global: { fetch: async (input, init) => {
            const request = new Request(input, init);
            const url = new URL(request.url);
            if (request.method === "GET") return Response.json([fight]);
            assert.equal(request.method, "PATCH");
            assert.deepEqual(await request.json(), { time_zone: "Europe/Paris" });
            patches.push(url.pathname);
            return new Response(null, { status: 204 });
        } },
    });
    const { updateFight } = await import("./update-fight-supabase-query");
    await updateFight(owner, fightId, { timeZone: "Europe/Paris" }, admin, new Date("2026-09-13T12:00:00Z"));
    assert.deepEqual(patches, ["/rest/v1/fights", "/rest/v1/fight_series"]);
    await assert.rejects(
        updateFight(owner, fightId, { timeZone: "Europe/Paris" }, admin, new Date("2026-09-14T12:00:00Z")),
        (error: unknown) => error instanceof ApiError && error.status === 400,
    );
    fight.state = "live";
    await assert.rejects(
        updateFight(owner, fightId, { timeZone: "Europe/Paris" }, admin, new Date("2026-09-13T12:00:00Z")),
        (error: unknown) => error instanceof ApiError && error.status === 400,
    );
    assert.equal(patches.length, 2);
});

test("owner can rename a live fight without touching membership", async (t) => {
    const savedURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const savedKey = process.env.SUPABASE_SECRET_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        process.env.NEXT_PUBLIC_SUPABASE_URL || "https://update-fight.example";
    process.env.SUPABASE_SECRET_KEY =
        process.env.SUPABASE_SECRET_KEY || "test-only-key";
    t.after(() => {
        if (savedURL === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = savedURL;
        if (savedKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
        else process.env.SUPABASE_SECRET_KEY = savedKey;
    });

    const fight = {
        id: fightId,
        owner_id: owner,
        name: "Steps Fight",
        state: "live",
        starts_at: startsAt,
        ends_at: endsAt,
        action_text: "Cook dinner",
        series_id: seriesId,
    };
    let fightPatches = 0;
    let seriesPatches = 0;
    t.mock.method(
        globalThis,
        "fetch",
        async (input: RequestInfo | URL, init?: RequestInit) => {
            const request = new Request(input, init);
            const url = new URL(request.url);
            switch (url.pathname) {
                case "/rest/v1/fights":
                    if (request.method === "GET") return Response.json([fight]);
                    assert.equal(request.method, "PATCH");
                    fightPatches += 1;
                    assert.deepEqual(await request.json(), {
                        name: "Office steps",
                        action_text: "Cook dinner",
                    });
                    return new Response(null, { status: 204 });
                case "/rest/v1/fight_series":
                    if (request.method === "GET") {
                        return Response.json([
                            {
                                id: seriesId,
                                owner_id: owner,
                                visibility: "joinable",
                                recurring: true,
                                duration_seconds: 604800,
                                name: "Steps Fight",
                                action_text: "Cook dinner",
                                current_fight_id: fightId,
                            },
                        ]);
                    }
                    assert.equal(request.method, "PATCH");
                    seriesPatches += 1;
                    assert.deepEqual(await request.json(), {
                        name: "Office steps",
                        action_text: "Cook dinner",
                        visibility: "invite_only",
                    });
                    return new Response(null, { status: 204 });
                default:
                    throw new Error(`Unexpected query: ${url.pathname}`);
            }
        },
    );

    const { updateFight } = await import("./update-fight-supabase-query");
    const result = await updateFight(
        owner,
        fightId,
        updateFightRequestSchema.parse({
            name: "Office steps",
            visibility: "invite_only",
        }),
        undefined,
        new Date("2026-09-15T12:00:00Z"),
    );
    assert.deepEqual(result, { id: fightId, state: "live" });
    assert.equal(fightPatches, 1);
    assert.equal(seriesPatches, 1);
});

test("only the owner can edit, and finished fights stay frozen", async (t) => {
    const savedURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const savedKey = process.env.SUPABASE_SECRET_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        process.env.NEXT_PUBLIC_SUPABASE_URL || "https://update-fight.example";
    process.env.SUPABASE_SECRET_KEY =
        process.env.SUPABASE_SECRET_KEY || "test-only-key";
    t.after(() => {
        if (savedURL === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = savedURL;
        if (savedKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
        else process.env.SUPABASE_SECRET_KEY = savedKey;
    });

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

    const { updateFight } = await import("./update-fight-supabase-query");
    await assert.rejects(
        () =>
            updateFight(
                other,
                fightId,
                updateFightRequestSchema.parse({ name: "Nope" }),
            ),
        (error: unknown) => error instanceof ApiError && error.status === 403,
    );
    await assert.rejects(
        () =>
            updateFight(
                owner,
                fightId,
                updateFightRequestSchema.parse({ name: "Nope" }),
            ),
        (error: unknown) =>
            error instanceof ApiError &&
            error.status === 409 &&
            error.message.includes("no longer be edited"),
    );
});

test("the owner cannot kick themselves", async (t) => {
    const savedURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const savedKey = process.env.SUPABASE_SECRET_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        process.env.NEXT_PUBLIC_SUPABASE_URL || "https://update-fight.example";
    process.env.SUPABASE_SECRET_KEY =
        process.env.SUPABASE_SECRET_KEY || "test-only-key";
    t.after(() => {
        if (savedURL === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = savedURL;
        if (savedKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
        else process.env.SUPABASE_SECRET_KEY = savedKey;
    });

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
                    state: "live",
                    starts_at: startsAt,
                    ends_at: endsAt,
                    action_text: "Cook dinner",
                    series_id: seriesId,
                },
            ]);
        },
    );

    const { updateFight } = await import("./update-fight-supabase-query");
    await assert.rejects(
        () =>
            updateFight(
                owner,
                fightId,
                updateFightRequestSchema.parse({ removeUserIds: [owner] }),
            ),
        (error: unknown) =>
            error instanceof ApiError &&
            error.status === 400 &&
            error.message.includes("owner cannot be removed"),
    );
});

test("start time cannot change after the fight is live", async (t) => {
    const savedURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const savedKey = process.env.SUPABASE_SECRET_KEY;
    process.env.NEXT_PUBLIC_SUPABASE_URL =
        process.env.NEXT_PUBLIC_SUPABASE_URL || "https://update-fight.example";
    process.env.SUPABASE_SECRET_KEY =
        process.env.SUPABASE_SECRET_KEY || "test-only-key";
    t.after(() => {
        if (savedURL === undefined) delete process.env.NEXT_PUBLIC_SUPABASE_URL;
        else process.env.NEXT_PUBLIC_SUPABASE_URL = savedURL;
        if (savedKey === undefined) delete process.env.SUPABASE_SECRET_KEY;
        else process.env.SUPABASE_SECRET_KEY = savedKey;
    });

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
                    state: "live",
                    starts_at: startsAt,
                    ends_at: endsAt,
                    action_text: "Cook dinner",
                    series_id: seriesId,
                },
            ]);
        },
    );

    const { updateFight } = await import("./update-fight-supabase-query");
    await assert.rejects(
        () =>
            updateFight(
                owner,
                fightId,
                updateFightRequestSchema.parse({
                    startsAt: "2026-09-15T12:00:00.000Z",
                }),
            ),
        (error: unknown) =>
            error instanceof ApiError &&
            error.status === 400 &&
            error.message.includes("before the fight begins"),
    );
});

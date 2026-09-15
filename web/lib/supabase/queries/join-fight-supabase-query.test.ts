import assert from "node:assert/strict";
import { test } from "node:test";
import { randomUUID } from "node:crypto";
import { readFileSync } from "node:fs";
import { createClient } from "@supabase/supabase-js";
import {
    JOINABLE_MEMBER_CAP,
    listJoinableFights,
} from "./join-fight-supabase-query";
import {
    joinableFightSummarySchema,
    joinableFightListResponseSchema,
    joinFightRequestSchema,
    leaveFightRequestSchema,
} from "@/lib/types/fights/joinable-fight";

test("join requires a code or fight id", () => {
    assert.equal(joinFightRequestSchema.safeParse({}).success, false);
    assert.equal(joinFightRequestSchema.parse({ code: "K7M2" }).code, "K7M2");
    assert.equal(
        joinFightRequestSchema.parse({
            fightId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        }).fightId,
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    );
});

test("join defaults to this round and can ask for the next round", () => {
    assert.equal(joinFightRequestSchema.parse({ code: "K7M2" }).start, "now");
    assert.equal(
        joinFightRequestSchema.parse({ code: "K7M2", start: "next" }).start,
        "next",
    );
    assert.equal(
        joinFightRequestSchema.safeParse({ code: "K7M2", start: "later" })
            .success,
        false,
    );
});

test("joinable summaries never carry scores", () => {
    const summary = joinableFightSummarySchema.parse({
        fightId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        seriesId: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
        name: "Office steps",
        joinCode: "K7M2",
        ownerHandle: "maya",
        actionText: "Cook dinner",
        startsAt: "2026-09-04T12:00:00.000Z",
        endsAt: "2026-09-11T12:00:00.000Z",
        memberCount: 3,
        recurring: true,
        alreadyMember: false,
        canJoinNext: true,
    });
    assert.equal("score" in summary, false);
    assert.equal("standings" in summary, false);
    assert.equal(summary.memberCount, 3);
    assert.equal(JOINABLE_MEMBER_CAP, 50);
});

test("leave requires a fight id", () => {
    assert.equal(leaveFightRequestSchema.safeParse({}).success, false);
    assert.equal(
        leaveFightRequestSchema.parse({
            fightId: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
        }).fightId,
        "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
    );
});

test("suggested and joinable lists load summaries in one bounded read", async () => {
    const fixture = joinableFightListResponseSchema.parse(
        JSON.parse(
            readFileSync(
                new URL(
                    "../../../../contracts/fixtures/joinable-fights-response.json",
                    import.meta.url,
                ),
                "utf8",
            ),
        ),
    );
    const now = new Date("2026-09-15T12:00:00Z");
    const userId = randomUUID();
    for (const size of [8, 50]) {
        const rows = Array.from({ length: size }, (_, index) => {
            const ownerId = randomUUID();
            const fight = {
                id: index === 0 ? fixture.fights[0].fightId : randomUUID(),
                owner_id: ownerId,
                state: "live",
                starts_at: "2026-09-14T12:00:00Z",
                ends_at: "2026-09-21T12:00:00Z",
                time_zone: "UTC",
                action_text: "Cook dinner",
                roster: [{ count: 3 }],
                membership: index === 0 ? [{ user_id: userId }] : [],
            };
            return {
                id: index === 0 ? fixture.fights[0].seriesId : randomUUID(),
                owner_id: ownerId,
                current_fight_id: fight.id,
                join_code: "K7M2",
                recurring: index % 2 === 0,
                paused_at: null,
                name: `Fight ${index}`,
                owner: { handle: `owner${index}` },
                fight,
            };
        });
        let reads = 0;
        const admin = createClient(
            "https://joinable-audit.example",
            "test-only-key",
            {
                auth: { persistSession: false, autoRefreshToken: false },
                global: {
                    fetch: async (input, init) => {
                        reads += 1;
                        const request = new Request(input, init);
                        const url = new URL(request.url);
                        if (url.pathname.endsWith("/fight_series")) {
                            assert.equal(
                                url.searchParams.get("visibility"),
                                "eq.joinable",
                            );
                            assert.equal(
                                url.searchParams.get("paused_at"),
                                "is.null",
                            );
                            assert.equal(
                                url.searchParams.get("limit"),
                                String(size),
                            );
                            assert.equal(
                                url.searchParams.get("suggested"),
                                size === 8 ? "eq.true" : null,
                            );
                            assert.equal(
                                url.searchParams.get("fight.roster.state"),
                                "in.(accepted,deferred)",
                            );
                            assert.equal(
                                url.searchParams.get("fight.membership.state"),
                                "in.(accepted,deferred)",
                            );
                            assert.equal(
                                url.searchParams.get(
                                    "fight.membership.user_id",
                                ),
                                `eq.${userId}`,
                            );
                            return Response.json(rows);
                        }
                        if (url.pathname.endsWith("/fights")) {
                            return Response.json(
                                rows
                                    .filter(
                                        (row) =>
                                            `eq.${row.fight.id}` ===
                                            url.searchParams.get("id"),
                                    )
                                    .map((row) => row.fight),
                            );
                        }
                        if (url.pathname.endsWith("/profiles")) {
                            return Response.json(
                                rows
                                    .filter(
                                        (row) =>
                                            `eq.${row.owner_id}` ===
                                            url.searchParams.get("user_id"),
                                    )
                                    .map((row) => row.owner),
                            );
                        }
                        if (url.pathname.endsWith("/fight_members")) {
                            if (request.method === "HEAD")
                                return new Response(null, {
                                    headers: { "content-range": "0-2/3" },
                                });
                            return Response.json(
                                url.searchParams.get("fight_id") ===
                                    `eq.${rows[0].fight.id}`
                                    ? [{ fight_id: rows[0].fight.id }]
                                    : [],
                            );
                        }
                        throw new Error(`Unexpected resource ${url.pathname}`);
                    },
                },
            },
        );
        const result = await listJoinableFights(userId, admin, now, size === 8);
        assert.deepEqual({ fights: result.slice(0, 1) }, fixture);
        assert.deepEqual(
            result,
            rows.map((row, index) => ({
                fightId: row.fight.id,
                seriesId: row.id,
                name: row.name,
                joinCode: row.join_code,
                ownerHandle: row.owner.handle,
                actionText: row.fight.action_text,
                startsAt: row.fight.starts_at,
                endsAt: row.fight.ends_at,
                memberCount: 3,
                recurring: row.recurring,
                alreadyMember: index === 0,
                canJoinNext: index !== 0 && row.recurring,
            })),
        );
        assert.equal(
            reads,
            1,
            `${size} summaries should not make ${reads} database round trips`,
        );
    }
});

test("batched lists still advance expired recurring rounds and use the next round's roster", async () => {
    const now = new Date("2026-09-15T12:00:00Z");
    const userId = randomUUID();
    const seriesId = randomUUID();
    const previous = {
        id: randomUUID(),
        series_id: seriesId,
        state: "final",
        starts_at: "2026-09-08T12:00:00Z",
        ends_at: "2026-09-15T12:00:00Z",
        time_zone: "UTC",
        action_text: null,
        roster: [{ count: 2 }],
        membership: [],
    };
    const next = {
        ...previous,
        id: randomUUID(),
        state: "live",
        starts_at: previous.ends_at,
        ends_at: "2026-09-22T12:00:00Z",
        roster: [{ count: 4 }],
        membership: [{ user_id: userId }],
    };
    const series = {
        id: seriesId,
        name: "Next round",
        join_code: "K7M2",
        recurring: true,
        paused_at: null,
        current_fight_id: previous.id,
        owner: { handle: "maya" },
        fight: previous,
    };
    let advanced = false;
    const admin = createClient(
        "https://joinable-audit.example",
        "test-only-key",
        {
            auth: { persistSession: false, autoRefreshToken: false },
            global: {
                fetch: async (input, init) => {
                    const request = new Request(input, init);
                    const url = new URL(request.url);
                    if (url.pathname.endsWith("/fight_series")) {
                        if (request.method === "PATCH") {
                            assert.deepEqual(await request.json(), {
                                current_fight_id: next.id,
                            });
                            advanced = true;
                            return new Response(null, { status: 204 });
                        }
                        return Response.json([series]);
                    }
                    if (url.pathname.endsWith("/fights")) {
                        if (url.searchParams.get("series_id"))
                            return Response.json([{ id: next.id }]);
                        if (url.searchParams.get("id") === `eq.${next.id}`) {
                            assert.equal(
                                url.searchParams.get("roster.state"),
                                "in.(accepted,deferred)",
                            );
                            assert.equal(
                                url.searchParams.get("membership.user_id"),
                                `eq.${userId}`,
                            );
                            return Response.json([next]);
                        }
                        return Response.json([previous]);
                    }
                    throw new Error(`Unexpected resource ${url.pathname}`);
                },
            },
        },
    );
    const result = await listJoinableFights(userId, admin, now, true);
    assert.equal(advanced, true);
    assert.deepEqual(result, [
        {
            fightId: next.id,
            seriesId,
            name: series.name,
            joinCode: series.join_code,
            ownerHandle: "maya",
            actionText: null,
            startsAt: next.starts_at,
            endsAt: next.ends_at,
            memberCount: 4,
            recurring: true,
            alreadyMember: true,
            canJoinNext: false,
        },
    ]);
});

import assert from "node:assert/strict";
import test from "node:test";
import type { Sql } from "postgres";
import { GET, POST } from "@/app/api/v1/snake/scores/route";
import { ApiError } from "@/lib/http";
import { snakeScoreRequestSchema } from "@/lib/types/snake/score";
import { readSnakeRecord, recordSnakeScore } from "./snake-scores-supabase-query";

test("snake scores need a signed-in player and a score the board and the time allow", async () => {
    const url = "https://fitfight.app/api/v1/snake/scores";
    const responses = await Promise.all([
        GET(new Request(url), { params: Promise.resolve({}) }),
        POST(new Request(url, { method: "POST", body: JSON.stringify({ score: 12, duration_ms: 5000 }) }), { params: Promise.resolve({}) }),
    ]);
    assert.ok(responses.every((response) => response.status === 401));
    for (const game of [{ score: 0, duration_ms: 0 }, { score: 12, duration_ms: 960 }, { score: 222, duration_ms: 17_760 }])
        assert.equal(snakeScoreRequestSchema.safeParse(game).success, true, JSON.stringify(game));
    for (const game of [
        { score: -1, duration_ms: 1000 },
        { score: 223, duration_ms: 60_000 },
        { score: 1.5, duration_ms: 1000 },
        { score: 12, duration_ms: 959 },
        { score: 222, duration_ms: 1000 },
        { score: 3 },
        { score: 3, duration_ms: 1000, cheat: true },
    ])
        assert.equal(snakeScoreRequestSchema.safeParse(game).success, false, JSON.stringify(game));
});

test("the record is the highest score, a kept game carries its player and length, and a refused one is a 429", async () => {
    const queries: { text: string; values: unknown[] }[] = [];
    let saved = true;
    const database = Object.assign(async (strings: TemplateStringsArray, ...values: unknown[]) => {
        queries.push({ text: strings.join("?"), values });
        return [{ record: 40, saved }];
    }, { begin: async (callback: (sql: unknown) => Promise<unknown>) => callback(database) }) as unknown as Sql;
    assert.deepEqual(await readSnakeRecord(database), { record: 40 });
    assert.deepEqual(await recordSnakeScore("user-1", { score: 17, duration_ms: 4000 }, database), { record: 40 });
    assert.match(queries[1].text, /pg_advisory_xact_lock/);
    assert.match(queries[2].text, /insert into private\.snake_scores/);
    assert.deepEqual(queries[2].values.slice(0, 3), ["user-1", 17, 4000]);
    saved = false;
    await assert.rejects(
        recordSnakeScore("user-1", { score: 5, duration_ms: 4000 }, database),
        (error) => error instanceof ApiError && error.status === 429 && error.code === "snake_too_soon",
    );
});

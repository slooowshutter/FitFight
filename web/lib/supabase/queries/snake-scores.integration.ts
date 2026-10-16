import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { readSnakeRecord, recordSnakeScore } from "./snake-scores-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
const database = postgres(env.DATABASE_URL, { max: 2 });
after(() => database.end());

test("every Snake game is kept with its length, the record counts it, and impossible or overlapping games are refused", async (context) => {
    const users = [randomUUID(), randomUUID()];
    for (const userId of users) await database`insert into auth.users (id) values (${userId})`;
    context.after(async () => {
        await database`delete from auth.users where id = any(${database.array(users)}::uuid[])`;
    });
    const before = (await readSnakeRecord(database)).record;
    assert.deepEqual(await recordSnakeScore(users[0], { score: 1, duration_ms: 1000 }, database), { record: Math.max(before, 1) });
    assert.deepEqual(await recordSnakeScore(users[1], { score: 222, duration_ms: 17_760 }, database), { record: 222 });
    assert.deepEqual(await readSnakeRecord(database), { record: 222 });
    // A second game right after the first cannot have been played yet.
    await assert.rejects(recordSnakeScore(users[0], { score: 2, duration_ms: 1000 }, database), /Finish a game/);
    const [saved] = await database`select count(*)::int as games from private.snake_scores where user_id = any(${database.array(users)}::uuid[])`;
    assert.equal(saved.games, 2);
    // The table refuses scores the board or the time cannot hold, even without the API in front.
    await assert.rejects(database`insert into private.snake_scores (user_id, score, duration_ms) values (${users[0]}, 223, 60000)`);
    await assert.rejects(database`insert into private.snake_scores (user_id, score, duration_ms) values (${users[0]}, 50, 1000)`);
});

import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { snakeRecordSchema, snakeSaveRowSchema, type SnakeRecord, type SnakeScoreRequest } from "@/lib/types/snake/score";

export async function readSnakeRecord(database: Sql = createDatabaseClient()): Promise<SnakeRecord> {
    const [row] = await database`select coalesce(max(score), 0)::int as record from private.snake_scores`;
    return snakeRecordSchema.parse(row);
}

/**
 * Keeps the game and returns the record including it; the insert is not visible to the same statement's max.
 * A player's games cannot overlap: a new one waits at least its own length, and 5 s, after the last one sent.
 */
export async function recordSnakeScore(
    userId: string,
    game: SnakeScoreRequest,
    database: Sql = createDatabaseClient(),
): Promise<SnakeRecord> {
    const [row] = await database`
        with saved as (
            insert into private.snake_scores (user_id, score, duration_ms)
            select ${userId}, ${game.score}, ${game.duration_ms}
            where not exists (select 1 from private.snake_scores
                where user_id = ${userId}
                    and created_at > now() - make_interval(secs => greatest(5, ${game.duration_ms}::int / 1000.0)))
            returning score)
        select exists (select 1 from saved) as saved,
            greatest((select coalesce(max(score), 0) from private.snake_scores),
                coalesce((select score from saved), 0))::int as record`;
    const result = snakeSaveRowSchema.parse(row);
    if (!result.saved) throw new ApiError(429, "snake_too_soon", "Finish a game before sending another score.");
    return { record: result.record };
}

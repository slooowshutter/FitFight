import { z } from "zod";

/** The snake moves at most once every 80 ms, so each point takes at least that long to play. */
export const snakeMillisecondsPerPoint = 80;

/** A finished game. A 15 by 15 board holds at most 222 points. */
export const snakeScoreRequestSchema = z.object({
    score: z.number().int().min(0).max(222),
    duration_ms: z.number().int().min(0).max(86_400_000),
}).strict().refine((game) => game.duration_ms >= game.score * snakeMillisecondsPerPoint, {
    message: "This score cannot be played in that time",
    path: ["duration_ms"],
});

/** The highest score across all players. */
export const snakeRecordSchema = z.object({
    record: z.number().int().nonnegative(),
});

/** One save: whether the game was kept, and the record after it. */
export const snakeSaveRowSchema = snakeRecordSchema.extend({ saved: z.boolean() });

export type SnakeScoreRequest = z.infer<typeof snakeScoreRequestSchema>;
export type SnakeRecord = z.infer<typeof snakeRecordSchema>;

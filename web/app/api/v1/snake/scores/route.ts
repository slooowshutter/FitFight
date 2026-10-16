import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readSnakeRecord, recordSnakeScore } from "@/lib/supabase/queries/snake-scores-supabase-query";
import { snakeScoreRequestSchema } from "@/lib/types/snake/score";

export const runtime = "nodejs";
export const GET = apiRoute(async (request) => {
    await verifyUser(request);
    return json(await readSnakeRecord());
});

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = snakeScoreRequestSchema.parse(await readJson(request, 1024));
    return json(await recordSnakeScore(userId, input));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

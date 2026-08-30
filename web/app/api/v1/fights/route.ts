import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
  createFight,
  createFightSchema,
} from "@/lib/supabase/queries/create-fight-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const idempotencyKey = request.headers.get("idempotency-key") ?? request.headers.get("Idempotency-Key");
  if (!idempotencyKey?.trim()) {
    throw new ApiError(400, ERROR_CODES.missing_idempotency_key, "Idempotency-Key is required");
  }
  const body = createFightSchema.parse(await readJson(request));
  const fight = await createFight(userId, body);
  return json(fight, 201);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

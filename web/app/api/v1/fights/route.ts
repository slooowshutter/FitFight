import { verifyUser } from "@/server/auth/verifyUser";
import { createFight, createFightSchema } from "@/server/domain/fights/createFight";
import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json, readJson } from "@/server/http";

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

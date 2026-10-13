import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { claimFreeCustomCharacter } from "@/lib/supabase/queries/custom-characters-supabase-query";
import { customCharacterFreeClaimRequestSchema, freeCharacterKeySchema } from "@/lib/types/ai/custom-character";

export const runtime = "nodejs";
/** The app then starts the portraits through /advance; if it cannot, the reconciler does. */
export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const key = freeCharacterKeySchema.safeParse(request.headers.get("Idempotency-Key"));
    if (!key.success)
        throw new ApiError(400, ERROR_CODES.missing_idempotency_key, "A UUID Idempotency-Key is required.");
    const input = customCharacterFreeClaimRequestSchema.parse(await readJson(request, 32_768));
    return json(await claimFreeCustomCharacter(userId, key.data, input.description));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

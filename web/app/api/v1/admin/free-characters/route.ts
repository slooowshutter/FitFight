import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { readAdminViewer, verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { giftFreeCharacters } from "@/lib/supabase/queries/custom-characters-supabase-query";
import { readReferralGrants } from "@/lib/supabase/queries/free-characters-supabase-query";
import { freeCharacterGiftRequestSchema, freeCharacterKeySchema } from "@/lib/types/ai/custom-character";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

async function requireAdmin(request: Request) {
    const { userId } = await verifyUser(request);
    if (!isFitFightAdmin(await readAdminViewer(userId))) {
        throw new ApiError(403, ERROR_CODES.forbidden, "Only the FitFight admin can give free characters.");
    }
    return userId;
}

export const GET = apiRoute(async (request) => {
    await requireAdmin(request);
    return json(await readReferralGrants());
});

export const POST = apiRoute(async (request) => {
    const userId = await requireAdmin(request);
    const key = freeCharacterKeySchema.safeParse(request.headers.get("Idempotency-Key"));
    if (!key.success)
        throw new ApiError(400, ERROR_CODES.missing_idempotency_key, "A UUID Idempotency-Key is required.");
    const input = freeCharacterGiftRequestSchema.parse(await readJson(request, 2048));
    return json(await giftFreeCharacters(userId, key.data, input));
});

export const OPTIONS = corsPreflight;

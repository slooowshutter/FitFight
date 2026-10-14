import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { claimFreeSpecial } from "@/lib/supabase/queries/free-characters-supabase-query";
import { freeCharacterKeySchema } from "@/lib/types/ai/custom-character";
import { specialFreeClaimRequestSchema } from "@/lib/types/companions/specials";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const key = freeCharacterKeySchema.safeParse(request.headers.get("Idempotency-Key"));
    if (!key.success)
        throw new ApiError(400, ERROR_CODES.missing_idempotency_key, "A UUID Idempotency-Key is required.");
    const input = specialFreeClaimRequestSchema.parse(await readJson(request, 1024));
    return json(await claimFreeSpecial(userId, key.data, input.companion_id));
});

export const OPTIONS = corsPreflight;

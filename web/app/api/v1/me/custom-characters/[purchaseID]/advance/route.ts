import { advancePaidCharacter } from "@/lib/domain/ai/paid-character";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { customCharacterAdvanceRequestSchema, customCharacterPurchaseIdSchema } from "@/lib/types/ai/custom-character";

export const runtime = "nodejs";
export const POST = apiRoute<{ purchaseID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const purchaseId = customCharacterPurchaseIdSchema.parse(params.purchaseID);
    const input = customCharacterAdvanceRequestSchema.parse(await readJson(request));
    const result = await advancePaidCharacter(userId, purchaseId, input);
    return json(result, result.status === "generating" ? 202 : 200);
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

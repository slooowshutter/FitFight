import { advanceCompanionLines, readPaidCharacter } from "@/lib/domain/ai/paid-character";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { customCharacterPurchaseIdSchema, customCharacterSuggestionsRequestSchema } from "@/lib/types/ai/custom-character";

export const runtime = "nodejs";
export const POST = apiRoute<{ purchaseID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const purchaseId = customCharacterPurchaseIdSchema.parse(params.purchaseID);
    const input = customCharacterSuggestionsRequestSchema.parse(await readJson(request));
    await advanceCompanionLines(userId, purchaseId, input.attempt_id);
    const character = await readPaidCharacter(userId, purchaseId);
    return json(character, character.suggestions_pending ? 202 : 200);
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

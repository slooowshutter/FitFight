import { readPaidCharacter } from "@/lib/domain/ai/paid-character";
import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { saveCustomCharacterLabel } from "@/lib/supabase/queries/custom-characters-supabase-query";
import { customCharacterLabelRequestSchema, customCharacterPurchaseIdSchema } from "@/lib/types/ai/custom-character";

export const runtime = "nodejs";
export const POST = apiRoute<{ purchaseID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const purchaseId = customCharacterPurchaseIdSchema.parse(params.purchaseID);
    const input = customCharacterLabelRequestSchema.parse(await readJson(request));
    await saveCustomCharacterLabel(userId, purchaseId, input);
    return json(await readPaidCharacter(userId, purchaseId));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

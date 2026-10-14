import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readCustomCharacterStore, recordCustomCharacterTransaction } from "@/lib/supabase/queries/custom-characters-supabase-query";
import { claimsSandbox, verifyCustomCharacterPurchase } from "@/lib/apple/special-purchase";
import { customCharacterClaimRequestSchema } from "@/lib/types/ai/custom-character";

export const runtime = "nodejs";
export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = customCharacterClaimRequestSchema.parse(await readJson(request, 32_768));
    const store = await readCustomCharacterStore(userId, undefined, claimsSandbox(input.signed_transaction));
    const transaction = await verifyCustomCharacterPurchase(input.signed_transaction, {
        environment: store.environment,
        appAccountToken: store.app_account_token,
    });
    return json(await recordCustomCharacterTransaction(transaction, undefined, input.description));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

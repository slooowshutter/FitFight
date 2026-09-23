import { apiRoute, json, readJson, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
    readSpecialStore,
    recordSpecialTransaction,
} from "@/lib/supabase/queries/specials-supabase-query";
import { verifySpecialPurchase } from "@/lib/apple/special-purchase";
import { specialClaimRequestSchema } from "@/lib/types/companions/specials";

export const runtime = "nodejs";
export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = specialClaimRequestSchema.parse(
        await readJson(request, 32_768),
    );
    const store = await readSpecialStore(userId);
    const transaction = await verifySpecialPurchase(input.signed_transaction, {
        environment: store.environment,
        appAccountToken: store.app_account_token,
        companionId: input.companion_id,
    });
    return json(await recordSpecialTransaction(transaction));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

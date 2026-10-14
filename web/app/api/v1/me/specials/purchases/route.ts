import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
    readSpecialStore,
    recordSpecialPurchase,
} from "@/lib/supabase/queries/specials-supabase-query";
import {
    claimsSandbox,
    verifySpecialConsumablePurchase,
} from "@/lib/apple/special-purchase";
import { specialPurchaseRequestSchema } from "@/lib/types/companions/specials";

export const runtime = "nodejs";
export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = specialPurchaseRequestSchema.parse(
        await readJson(request, 32_768),
    );
    const store = await readSpecialStore(
        userId,
        undefined,
        claimsSandbox(input.signed_transaction),
    );
    const transaction = await verifySpecialConsumablePurchase(
        input.signed_transaction,
        {
            environment: store.environment,
            appAccountToken: store.app_account_token,
        },
    );
    return json(await recordSpecialPurchase(transaction, input.companion_id));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { specialCheckout } from "@/lib/supabase/queries/specials-supabase-query";
import { specialCheckoutRequestSchema } from "@/lib/types/companions/specials";

export const runtime = "nodejs";
export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = specialCheckoutRequestSchema.parse(
        await readJson(request, 2_048),
    );
    await specialCheckout(userId, input);
    return json({ saved: true });
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

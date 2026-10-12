import { ApiError, apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { specialCheckoutRequestSchema } from "@/lib/types/companions/specials";

export const runtime = "nodejs";

/**
 * Builds before 12 Oct 2026 reserved a one-of-a-kind edition here before paying. Specials are now one shared
 * consumable, so a reservation is refused before Apple can charge, and a cancel has nothing left to release.
 */
export const POST = apiRoute(async (request) => {
    await verifyUser(request);
    const input = specialCheckoutRequestSchema.parse(
        await readJson(request, 2_048),
    );
    if (input.action === "reserve")
        throw new ApiError(
            410,
            "special_update_required",
            "Update FitFight to buy Specials.",
        );
    return json({ saved: true });
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

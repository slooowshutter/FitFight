import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
    readAccountPreferences,
    updateAccountPreferences,
} from "@/lib/supabase/queries/account-preferences-supabase-query";
import { updateAccountPreferencesRequestSchema } from "@/lib/types/profiles/account-preferences";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await readAccountPreferences(userId));
});

export const PATCH = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const parsed = updateAccountPreferencesRequestSchema.safeParse(await readJson(request));
    if (!parsed.success) throw parsed.error;
    return json(await updateAccountPreferences(userId, parsed.data));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

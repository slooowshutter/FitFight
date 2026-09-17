import { apiRoute, json, readJson, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { readProfileSettings, updateProfileSettings } from "@/lib/supabase/queries/shared-profiles-supabase-query";
import { updateProfileSettingsSchema } from "@/lib/types/profiles/shared-profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json(await readProfileSettings(userId));
});

export const PATCH = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const input = updateProfileSettingsSchema.parse(await readJson(request));
    return json(await updateProfileSettings(userId, input));
});

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { lookupSharedProfile } from "@/lib/supabase/queries/shared-profiles-supabase-query";
import { profileLookupSchema } from "@/lib/types/profiles/shared-profile";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const query = profileLookupSchema.parse(Object.fromEntries(new URL(request.url).searchParams));
    return json(await lookupSharedProfile(userId, query.handle));
});

export const OPTIONS = corsPreflight;

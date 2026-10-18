import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { searchProfiles } from "@/lib/supabase/queries/profile-search-supabase-query";
import { profileSearchRequestSchema } from "@/lib/types/profiles/profile-search";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const query = profileSearchRequestSchema.parse(Object.fromEntries(new URL(request.url).searchParams));
    return json(await searchProfiles(userId, query.q));
});

export const OPTIONS = corsPreflight;

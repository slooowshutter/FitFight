import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { listFeedActivity } from "@/lib/supabase/queries/feed-activity-supabase-query";
import { listFeedActivityQuerySchema } from "@/lib/types/feed/feed-activity";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const search = new URL(request.url).searchParams;
    const query = listFeedActivityQuerySchema.safeParse({
        limit: search.get("limit") ?? undefined,
        cursor: search.get("cursor") ?? undefined,
    });
    if (!query.success) throw query.error;
    return json(await listFeedActivity(userId, query.data));
});

export const OPTIONS = corsPreflight;

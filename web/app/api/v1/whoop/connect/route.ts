import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { startWhoopConnection } from "@/lib/whoop/whoop";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json({ url: await startWhoopConnection(userId) });
});

export const OPTIONS = corsPreflight;

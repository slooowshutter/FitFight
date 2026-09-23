import { apiRoute, json, requireCronSecret } from "@/lib/http";
import { closeDueFights } from "@/lib/supabase/queries/close-due-fights-supabase-query";
import { pruneProfileEvents } from "@/lib/supabase/queries/profile-events-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

async function handle(request: Request) {
    requireCronSecret(request);
    await pruneProfileEvents();
    const result = await closeDueFights();
    return json({ ok: true, ...result });
}

export const GET = apiRoute(handle);
export const POST = apiRoute(handle);

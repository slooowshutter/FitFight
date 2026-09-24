import { apiRoute, json, requireCronSecret } from "@/lib/http";
import { processActivity } from "@/lib/supabase/queries/activity-pipeline-supabase-query";
import { closeDueFights } from "@/lib/supabase/queries/close-due-fights-supabase-query";
import { pruneProfileEvents } from "@/lib/supabase/queries/profile-events-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

async function handle(request: Request) {
    requireCronSecret(request);
    await pruneProfileEvents();
    // Resume received activity first, so a Fight closes with every reading that already arrived.
    const activity = await processActivity({ limit: 500, budgetMs: 20_000 });
    const result = await closeDueFights();
    return json({ ok: true, activity, ...result });
}

export const GET = apiRoute(handle);
export const POST = apiRoute(handle);

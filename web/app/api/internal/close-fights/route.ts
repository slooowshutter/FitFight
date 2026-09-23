import { ApiError, ERROR_CODES, apiRoute, json } from "@/lib/http";
import { processActivity } from "@/lib/supabase/queries/activity-pipeline-supabase-query";
import { closeDueFights } from "@/lib/supabase/queries/close-due-fights-supabase-query";
import { pruneProfileEvents } from "@/lib/supabase/queries/profile-events-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

function requireCron(request: Request): void {
    const secret = process.env.CRON_SECRET ?? process.env.FITFIGHT_CRON_SECRET;
    if (!secret) {
        throw new ApiError(503, ERROR_CODES.config, "Cron secret is not set");
    }
    const header =
        request.headers.get("authorization") ??
        request.headers.get("Authorization") ??
        "";
    const match = /^Bearer\s+(\S+)/i.exec(header.trim());
    if (match?.[1] !== secret) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Unauthorized");
    }
}

async function handle(request: Request) {
    requireCron(request);
    await pruneProfileEvents();
    // Resume received activity first, so a Fight closes with every reading that already arrived.
    const activity = await processActivity({ limit: 500, budgetMs: 20_000 });
    const result = await closeDueFights();
    return json({ ok: true, activity, ...result });
}

export const GET = apiRoute(handle);
export const POST = apiRoute(handle);

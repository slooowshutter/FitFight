import { apiRoute, json, requireCronSecret } from "@/lib/http";
import { enqueueDailyStatusNotifications } from "@/lib/supabase/queries/daily-status-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

async function handle(request: Request) {
    requireCronSecret(request);
    const result = await enqueueDailyStatusNotifications();
    return json({ ok: true, ...result });
}

export const GET = apiRoute(handle);
export const POST = apiRoute(handle);

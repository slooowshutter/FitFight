import { apiRoute, json, requireCronSecret } from "@/lib/http";
import { listWhoopUsersToSync } from "@/lib/supabase/queries/whoop-supabase-query";
import { syncWhoopUser } from "@/lib/whoop/whoop";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

/**
 * Hourly. Catches what webhooks miss: WHOOP sends none for cycles (strain, steps) or body
 * measurements, and gives up on a webhook after five tries.
 */
async function handle(request: Request) {
    requireCronSecret(request);
    const startedAt = Date.now();
    const userIds = await listWhoopUsersToSync();
    let synced = 0;
    let failed = 0;
    // ponytail: one person at a time, about 5 WHOOP requests each. Past ~100 people, the app-wide
    // 10,000 requests a day runs out first; then sync cycles hourly and the rest less often.
    for (const userId of userIds) {
        if (Date.now() - startedAt > 240_000) {
            break;
        }
        try {
            await syncWhoopUser(userId);
            synced += 1;
        } catch {
            // syncWhoopUser saved the error on the connection; one person's failure skips only them.
            failed += 1;
        }
    }
    return json({ ok: true, users: userIds.length, synced, failed });
}

export const GET = apiRoute(handle);
export const POST = apiRoute(handle);

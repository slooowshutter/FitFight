import { apiRoute, json, readJson, requireCronSecret } from "@/lib/http";
import { receiveHealthKitActivity } from "@/lib/supabase/queries/activity-pipeline-supabase-query";
import { readFounderId } from "@/lib/supabase/queries/founder-fight-supabase-query";
import { healthKitActivityBatchSchema } from "@/lib/types/healthkit/healthkit-activity-batch";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Staging sends the founder's TestFlight syncs here, so this environment stores them too. */
export const POST = apiRoute(async (request) => {
    requireCronSecret(request);
    const input = healthKitActivityBatchSchema.parse(await readJson(request));
    return json(await receiveHealthKitActivity(await readFounderId(), input));
});

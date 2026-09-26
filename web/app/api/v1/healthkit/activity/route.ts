import {
    apiRoute,
    corsPreflight,
    json,
    measureRequestStage,
    readJson,
} from "@/lib/http";
import { receiveHealthKitActivity } from "@/lib/supabase/queries/activity-pipeline-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { healthKitActivityBatchSchema } from "@/lib/types/healthkit/healthkit-activity-batch";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request, { timing }) => {
    const { userId } = await measureRequestStage(timing, "auth", () =>
        verifyUser(request),
    );
    const input = healthKitActivityBatchSchema.parse(await readJson(request));
    return json(
        await measureRequestStage(timing, "db", () =>
            receiveHealthKitActivity(userId, input),
        ),
    );
}, "healthkit_activity");

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

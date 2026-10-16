import { after } from "next/server";
import { rewardReferrals } from "@/lib/domain/referrals/referral-rewards";
import {
    apiRoute,
    corsPreflight,
    json,
    measureRequestStage,
    readJson,
} from "@/lib/http";
import { receiveHealthKitActivity } from "@/lib/supabase/queries/activity-pipeline-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { founderUserIds } from "@/lib/types/fights/founder-fight";
import { healthKitActivityBatchSchema } from "@/lib/types/healthkit/healthkit-activity-batch";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request, { timing }) => {
    const { userId } = await measureRequestStage(timing, "auth", () =>
        verifyUser(request),
    );
    const body = await readJson(request);
    const input = healthKitActivityBatchSchema.parse(body);
    after(() => rewardReferrals(userId));
    const received = await measureRequestStage(timing, "db", () =>
        receiveHealthKitActivity(userId, input),
    );
    // Marc syncs from TestFlight, so production would never get his Steps for
    // his profile and the founder rounds it scores from them.
    if (userId === founderUserIds.beta) {
        after(async () => {
            const response = await fetch(
                "https://fitfight.app/api/internal/founder-activity",
                {
                    method: "POST",
                    headers: {
                        "Content-Type": "application/json",
                        Authorization: `Bearer ${process.env.CRON_SECRET}`,
                    },
                    body: JSON.stringify(body),
                },
            );
            if (!response.ok) {
                throw new Error(
                    `Copying the founder's activity to production failed with HTTP ${response.status}`,
                );
            }
        });
    }
    return json(received);
}, "healthkit_activity");

export function OPTIONS(request: Request) {
    return corsPreflight(request);
}

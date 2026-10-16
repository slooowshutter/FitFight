import { timingSafeEqual } from "node:crypto";
import { ApiError, apiRoute, json } from "@/lib/http";
import { reconcileAiRuns } from "@/lib/domain/ai/reconciliation";
import { advanceFightGroupImages } from "@/lib/domain/fight-images/advance";
import { observeAiHttp } from "@/lib/observability/ai-request-log";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export const GET = observeAiHttp(
    apiRoute(async (request) => {
        const secret =
            process.env.CRON_SECRET ?? process.env.FITFIGHT_CRON_SECRET;
        if (!secret)
            throw new ApiError(503, "config", "Cron secret is not set");
        const expected = Buffer.from(`Bearer ${secret}`);
        const received = Buffer.from(
            request.headers.get("authorization") ?? "",
        );
        if (
            expected.length !== received.length ||
            !timingSafeEqual(expected, received)
        ) {
            throw new ApiError(401, "unauthorized", "Unauthorized");
        }
        const started = performance.now();
        const runs = await reconcileAiRuns();
        // Fight group images share this cron, which already runs every minute in production and every five
        // minutes on staging. They get what is left of the 60-second budget after the paid runs.
        const fightImages = await advanceFightGroupImages(started + 52_000);
        return json({ ...runs, fight_images: fightImages });
    }),
    "reconcile",
    "reconciler",
);

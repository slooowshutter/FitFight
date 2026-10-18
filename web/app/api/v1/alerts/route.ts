import { alertsFor } from "@/lib/alerts/in-app-alerts";
import { apiRoute, corsPreflight, json } from "@/lib/http";
import { latestInstallableRelease } from "@/lib/releases/app-release";
import { readAlertFacts } from "@/lib/supabase/queries/alerts-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { alertAppVersionSchema } from "@/lib/types/alerts/in-app-alert";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** The alerts to show now, in order. `?language=fr` picks French; anything else is English. */
export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    const url = new URL(request.url);
    const appVersion = alertAppVersionSchema.parse(request.headers.get("x-fitfight-version"));
    const [facts, latestRelease] = await Promise.all([
        readAlertFacts(userId),
        // Alerts without an update button still show when Apple cannot be read.
        latestInstallableRelease().catch(() => null),
    ]);
    return json({
        alerts: alertsFor(
            { ...facts, appVersion, latestRelease },
            url.searchParams.get("language") === "fr" ? "fr" : "en",
            url.origin,
        ),
    });
});

export const OPTIONS = corsPreflight;

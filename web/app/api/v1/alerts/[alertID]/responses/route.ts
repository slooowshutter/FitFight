import { inAppAlerts } from "@/lib/alerts/in-app-alerts";
import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { recordAlertResponse } from "@/lib/supabase/queries/alerts-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { alertAppVersionSchema, alertResponseRequestSchema } from "@/lib/types/alerts/in-app-alert";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ alertID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    if (!inAppAlerts.some((alert) => alert.id === params.alertID)) {
        throw new ApiError(404, ERROR_CODES.not_found, "Unknown alert");
    }
    const parsed = alertResponseRequestSchema.safeParse(await readJson(request, 1024));
    if (!parsed.success) throw parsed.error;
    const version = alertAppVersionSchema.safeParse(request.headers.get("x-fitfight-version"));
    const build = request.headers.get("x-fitfight-build");
    await recordAlertResponse(
        userId,
        params.alertID,
        parsed.data,
        version.success ? version.data : null,
        build && /^\d{1,10}$/.test(build) ? build : null,
    );
    return json({ recorded: true });
});

export const OPTIONS = corsPreflight;

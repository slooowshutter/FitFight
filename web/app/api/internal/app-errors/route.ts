import { apiRoute, json, readJson, requireBearerSecret } from "@/lib/http";
import { insertAppErrorLog } from "@/lib/supabase/queries/app-error-logs-supabase-query";
import { posthogExceptionWebhookSchema } from "@/lib/types/observability/app-error-log";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request: Request) => {
    requireBearerSecret(
        request,
        process.env.POSTHOG_APP_ERRORS_SECRET,
        "PostHog app errors secret",
    );
    const parsed = posthogExceptionWebhookSchema.safeParse(
        await readJson(request),
    );
    if (!parsed.success) {
        throw parsed.error;
    }
    return json({ ok: true, inserted: await insertAppErrorLog(parsed.data) });
});

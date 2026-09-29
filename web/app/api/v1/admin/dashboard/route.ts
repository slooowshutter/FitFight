import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json } from "@/lib/http";
import { createProductionAnalyticsClient } from "@/lib/supabase/postgres";
import { readAdminDashboard } from "@/lib/supabase/queries/admin-dashboard-supabase-query";
import {
    verifyDashboardAdmin,
    verifyProductionDashboardAdmin,
} from "@/lib/supabase/queries/auth-supabase-query";
import { adminDashboardQuerySchema } from "@/lib/types/admin/admin-dashboard";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export const GET = apiRoute(async (request) => {
    const identities = await verifyDashboardAdmin(request);
    const search = new URL(request.url).searchParams;
    const query = adminDashboardQuerySchema.safeParse({
        section: search.get("section") ?? undefined,
        days: search.get("days") ?? undefined,
        environment: search.get("environment") ?? undefined,
    });
    if (!query.success) throw query.error;
    const { section, days } = query.data;
    const own = process.env.NEXT_PUBLIC_SUPABASE_URL?.includes("pvqntpteehdvhqyctwum")
        ? "production"
        : "staging";
    const environment = query.data.environment ?? own;
    if (environment === own) return json(await readAdminDashboard(section, days, own));
    if (environment !== "production") {
        throw new ApiError(400, ERROR_CODES.validation, "This server only adds production data");
    }
    const production = createProductionAnalyticsClient();
    await verifyProductionDashboardAdmin(identities, production);
    return json(await readAdminDashboard(section, days, "production", production));
});

export const OPTIONS = corsPreflight;

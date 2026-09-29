import { apiRoute, corsPreflight, json } from "@/lib/http";
import { readAdminDashboard } from "@/lib/supabase/queries/admin-dashboard-supabase-query";
import { verifyDashboardAdmin } from "@/lib/supabase/queries/auth-supabase-query";
import { adminDashboardQuerySchema } from "@/lib/types/admin/admin-dashboard";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

export const GET = apiRoute(async (request) => {
    await verifyDashboardAdmin(request);
    const search = new URL(request.url).searchParams;
    const query = adminDashboardQuerySchema.safeParse({
        section: search.get("section") ?? undefined,
        days: search.get("days") ?? undefined,
    });
    if (!query.success) throw query.error;
    return json(await readAdminDashboard(query.data.section, query.data.days));
});

export const OPTIONS = corsPreflight;

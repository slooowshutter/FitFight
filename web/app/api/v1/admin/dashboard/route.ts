import { openAdminDatabase } from "@/lib/admin/open-admin-database";
import { apiRoute, corsPreflight, json } from "@/lib/http";
import { readAdminDashboard } from "@/lib/supabase/queries/admin-dashboard-supabase-query";
import { verifyDashboardAdmin } from "@/lib/supabase/queries/auth-supabase-query";
import { adminDashboardQuerySchema, type AdminDashboard } from "@/lib/types/admin/admin-dashboard";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 60;

// NOTE: a tab's queries keep running after the app stops waiting. Sharing the running or
// five-minute-old result stops repeated taps from queueing behind them on the pool.
const recent = new Map<string, { at: number; dashboard: Promise<AdminDashboard> }>();

export const GET = apiRoute(async (request) => {
    const admin = await verifyDashboardAdmin(request);
    const search = new URL(request.url).searchParams;
    const query = adminDashboardQuerySchema.safeParse({
        section: search.get("section") ?? undefined,
        days: search.get("days") ?? undefined,
        environment: search.get("environment") ?? undefined,
        bucket: search.get("bucket") ?? undefined,
    });
    if (!query.success) throw query.error;
    const { section, days, bucket } = query.data;
    const { environment, database } = await openAdminDatabase(admin, query.data.environment);
    const key = `${environment}:${section}:${days}:${bucket ?? "auto"}`;
    const cached = recent.get(key);
    if (cached && Date.now() - cached.at < 5 * 60_000) return json(await cached.dashboard);
    const dashboard = readAdminDashboard(section, days, environment, database, bucket);
    recent.set(key, { at: Date.now(), dashboard });
    // A failed result is not reused: the next request retries.
    const result = await dashboard.catch((error: unknown) => {
        recent.delete(key);
        throw error;
    });
    if ([...result.cards, ...result.charts, ...result.tables].some((tile) => tile.note?.startsWith("Query failed"))) {
        recent.delete(key);
    }
    return json(result);
});

export const OPTIONS = corsPreflight;

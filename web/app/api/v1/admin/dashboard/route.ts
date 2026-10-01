import type { Sql } from "postgres";
import { ApiError, ERROR_CODES, apiRoute, corsPreflight, json } from "@/lib/http";
import { createProductionAnalyticsClient } from "@/lib/supabase/postgres";
import { readAdminDashboard } from "@/lib/supabase/queries/admin-dashboard-supabase-query";
import {
    verifyDashboardAdmin,
    verifyProductionDashboardAdmin,
} from "@/lib/supabase/queries/auth-supabase-query";
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
    });
    if (!query.success) throw query.error;
    const { section, days } = query.data;
    const own = process.env.NEXT_PUBLIC_SUPABASE_URL?.includes("pvqntpteehdvhqyctwum")
        ? "production"
        : "staging";
    const environment = query.data.environment ?? own;
    let production: Sql | undefined;
    if (environment !== own) {
        if (environment !== "production") {
            throw new ApiError(400, ERROR_CODES.validation, "This server only adds production data");
        }
        production = createProductionAnalyticsClient();
        try {
            await verifyProductionDashboardAdmin(admin, production);
        } catch (error) {
            if (error instanceof ApiError) throw error;
            // The caller is the verified admin; the driver's message names the failing login,
            // host or permission and never contains the connection password.
            throw new ApiError(
                502,
                ERROR_CODES.db_error,
                `Production database: ${error instanceof Error ? error.message : String(error)}`,
            );
        }
    }
    const key = `${environment}:${section}:${days}`;
    const cached = recent.get(key);
    if (cached && Date.now() - cached.at < 5 * 60_000) return json(await cached.dashboard);
    const dashboard = readAdminDashboard(section, days, environment, production);
    recent.set(key, { at: Date.now(), dashboard });
    // A failed result is not reused: the next request retries.
    const result = await dashboard.catch((error: unknown) => {
        recent.delete(key);
        throw error;
    });
    if ([...result.cards, ...result.charts].some((tile) => tile.note?.startsWith("Query failed"))) {
        recent.delete(key);
    }
    return json(result);
});

export const OPTIONS = corsPreflight;

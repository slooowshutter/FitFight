import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient, createProductionAnalyticsClient } from "@/lib/supabase/postgres";
import { verifyProductionDashboardAdmin } from "@/lib/supabase/queries/auth-supabase-query";
import type { AdminDashboardAdmin, AdminDashboardEnvironment } from "@/lib/types/admin/admin-dashboard";

/**
 * The database an admin read uses: this server's own by default. A staging server also reads
 * production, through its read-only analytics connection, once production confirms the admin.
 */
export async function openAdminDatabase(
    admin: AdminDashboardAdmin,
    requested: AdminDashboardEnvironment | undefined,
): Promise<{ environment: AdminDashboardEnvironment; database: Sql }> {
    const own = process.env.NEXT_PUBLIC_SUPABASE_URL?.includes("pvqntpteehdvhqyctwum") ? "production" : "staging";
    const environment = requested ?? own;
    if (environment === own) return { environment, database: createDatabaseClient() };
    if (environment !== "production") {
        throw new ApiError(400, ERROR_CODES.validation, "This server only adds production data");
    }
    const production = createProductionAnalyticsClient();
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
    return { environment, database: production };
}

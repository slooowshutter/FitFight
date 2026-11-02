import { openAdminDatabase } from "@/lib/admin/open-admin-database";
import { apiRoute, corsPreflight, json } from "@/lib/http";
import { readAdminTablePage } from "@/lib/supabase/queries/admin-dashboard-supabase-query";
import { verifyDashboardAdmin } from "@/lib/supabase/queries/auth-supabase-query";
import { adminTableQuerySchema } from "@/lib/types/admin/admin-dashboard";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** "Show more" on a dashboard table: the next rows of the table the dashboard sent. */
export const GET = apiRoute(async (request) => {
    const admin = await verifyDashboardAdmin(request);
    const search = new URL(request.url).searchParams;
    const query = adminTableQuerySchema.safeParse({
        id: search.get("id") ?? undefined,
        environment: search.get("environment") ?? undefined,
        limit: search.get("limit") ?? undefined,
        offset: search.get("offset") ?? undefined,
    });
    if (!query.success) throw query.error;
    const { environment, database } = await openAdminDatabase(
        admin,
        query.data.environment,
    );
    return json(
        await readAdminTablePage(
            query.data.id,
            query.data.limit,
            query.data.offset,
            environment,
            database,
        ),
    );
});

export const OPTIONS = corsPreflight;

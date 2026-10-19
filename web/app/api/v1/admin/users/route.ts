import { openAdminDatabase } from "@/lib/admin/open-admin-database";
import { apiRoute, corsPreflight, json } from "@/lib/http";
import { readAdminUsers } from "@/lib/supabase/queries/admin-dashboard-supabase-query";
import { verifyDashboardAdmin } from "@/lib/supabase/queries/auth-supabase-query";
import { adminUsersQuerySchema } from "@/lib/types/admin/admin-users";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
    const admin = await verifyDashboardAdmin(request);
    const search = new URL(request.url).searchParams;
    const query = adminUsersQuerySchema.safeParse({
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
        await readAdminUsers(
            query.data.limit,
            query.data.offset,
            environment,
            database,
        ),
    );
});

export const OPTIONS = corsPreflight;

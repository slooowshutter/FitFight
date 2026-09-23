import { apiRoute, json, corsPreflight } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { canAdministerFights } from "@/lib/admin/can-administer-fights";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const GET = apiRoute(async (request) => {
    const { userId } = await verifyUser(request);
    return json({ manage_fights: canAdministerFights(userId) });
});
export const OPTIONS = corsPreflight;

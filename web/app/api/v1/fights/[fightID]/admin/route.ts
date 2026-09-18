import { apiRoute, json, readJson, corsPreflight, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { administerFight } from "@/lib/supabase/queries/administer-fight-supabase-query";
import { administerFightRequestSchema } from "@/lib/types/admin/fight-administration";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const PATCH = apiRoute<{ fightID: string }>(async (request, { params }) => {
    const { userId } = await verifyUser(request);
    const fightId = requireUuid(params.fightID, "fightID");
    const input = administerFightRequestSchema.parse(await readJson(request));
    return json(await administerFight(userId, fightId, input));
});
export function OPTIONS(request: Request) { return corsPreflight(request); }

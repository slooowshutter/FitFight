import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { declineMembership } from "@/lib/supabase/queries/decline-membership-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ fightID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  return json(await declineMembership(userId, requireUuid(params.fightID, "fightID")));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getJoinableFightByCode } from "@/lib/supabase/queries/join-fight-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ code: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const fight = await getJoinableFightByCode(userId, params.code);
  return json(fight);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

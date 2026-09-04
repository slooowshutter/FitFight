import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { listJoinableFights } from "@/lib/supabase/queries/join-fight-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const fights = await listJoinableFights(userId);
  return json({ fights });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

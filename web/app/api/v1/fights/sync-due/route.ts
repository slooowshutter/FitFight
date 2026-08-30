import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { closeDueFightsForUser } from "@/lib/supabase/queries/close-due-fights-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const result = await closeDueFightsForUser(userId);
  return json(result);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

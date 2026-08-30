import {
  ensureAppleHealthSource,
  toDataSourceResponse,
} from "@/lib/supabase/queries/apple-health-source-supabase-query";
import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const source = await ensureAppleHealthSource(userId);
  return json(toDataSourceResponse(source));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

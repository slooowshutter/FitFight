import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getProviderUploadContext } from "@/lib/supabase/queries/provider-uploads-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  return json(await getProviderUploadContext(userId));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

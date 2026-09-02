import { apiRoute, corsPreflight, json, requireUuid } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { reportFeatureRequest } from "@/lib/supabase/queries/feature-requests-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute<{ requestID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const requestId = requireUuid(params.requestID, "requestID");
  const result = await reportFeatureRequest(userId, requestId);
  return json(result);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

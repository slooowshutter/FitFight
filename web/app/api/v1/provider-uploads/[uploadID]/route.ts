import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getProviderUpload } from "@/lib/supabase/queries/provider-uploads-supabase-query";
import { providerUploadIdSchema } from "@/lib/types/provider-uploads/provider-upload";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute<{ uploadID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const uploadId = providerUploadIdSchema.parse(params.uploadID);
  return json(await getProviderUpload(userId, uploadId));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

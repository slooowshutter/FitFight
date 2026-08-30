import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { processProviderUpload } from "@/lib/supabase/queries/provider-uploads-supabase-query";
import { providerUploadIdSchema } from "@/lib/types/provider-uploads/provider-upload";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";
export const maxDuration = 300;

export const POST = apiRoute<{ uploadID: string }>(async (request, { params }) => {
  const { userId } = await verifyUser(request);
  const uploadId = providerUploadIdSchema.parse(params.uploadID);
  const result = await processProviderUpload(userId, uploadId);
  return json(result.response, result.cleanupPending ? 202 : 200);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

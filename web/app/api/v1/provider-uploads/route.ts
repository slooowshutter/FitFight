import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { requireProviderArchiveSize } from "@/lib/ingest/provider-archive";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { createProviderUpload } from "@/lib/supabase/queries/provider-uploads-supabase-query";
import { createProviderUploadSchema } from "@/lib/types/provider-uploads/provider-upload";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const input = createProviderUploadSchema.parse(await readJson(request));
  requireProviderArchiveSize(input.byte_size);
  const result = await createProviderUpload(userId, input);
  return json(result.response, result.created ? 201 : 200);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

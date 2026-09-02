import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import {
  createFeatureRequest,
  listFeatureRequests,
} from "@/lib/supabase/queries/feature-requests-supabase-query";
import {
  createFeatureRequestSchema,
  listFeatureRequestsQuerySchema,
} from "@/lib/types/requests/feature-request";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const url = new URL(request.url);
  const kind = url.searchParams.get("kind");
  const parsed = listFeatureRequestsQuerySchema.safeParse({
    kind: kind === null || kind === "" ? undefined : kind,
  });
  if (!parsed.success) {
    throw parsed.error;
  }
  const items = await listFeatureRequests(userId, parsed.data.kind);
  return json({ items });
});

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const parsed = createFeatureRequestSchema.safeParse(await readJson(request, 4_096));
  if (!parsed.success) {
    throw parsed.error;
  }
  const item = await createFeatureRequest(userId, parsed.data);
  return json(item, 201);
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

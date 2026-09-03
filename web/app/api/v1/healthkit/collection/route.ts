import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { syncHealthKitCollection } from "@/lib/supabase/queries/healthkit-collection-supabase-query";
import { healthKitCollectionMaxBytes, healthKitCollectionSyncSchema } from "@/lib/types/healthkit/healthkit-collection";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const input = healthKitCollectionSyncSchema.parse(
    await readJson(request, healthKitCollectionMaxBytes),
  );
  return json(await syncHealthKitCollection(userId, input));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

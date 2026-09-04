import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { saveHealthKitDiagnosticSnapshot } from "@/lib/supabase/queries/healthkit-diagnostics-supabase-query";
import { healthKitDiagnosticSnapshotSchema } from "@/lib/types/healthkit/healthkit-diagnostic";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const input = healthKitDiagnosticSnapshotSchema.parse(await readJson(request));
  return json(await saveHealthKitDiagnosticSnapshot(userId, input));
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

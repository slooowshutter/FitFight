import { apiRoute, corsPreflight, json, readJson } from "@/lib/http";
import { storeAppleAuthorization } from "@/lib/supabase/queries/apple-sign-in-supabase-query";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { appleAuthorizationRequestSchema } from "@/lib/types/apple/apple-sign-in";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const POST = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const body = appleAuthorizationRequestSchema.parse(await readJson(request, 4_096));
  await storeAppleAuthorization(userId, body.authorization_code);
  return json({ stored: true });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

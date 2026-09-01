import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { deleteAccount } from "@/lib/supabase/queries/delete-account-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const DELETE = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  const appleAuthorizationRevoked = await deleteAccount(userId);
  return json({
    apple_authorization_revoked: appleAuthorizationRevoked,
    deleted: true,
  });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

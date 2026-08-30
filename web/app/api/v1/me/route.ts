import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { deleteAccount } from "@/lib/supabase/queries/delete-account-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const DELETE = apiRoute(async (request) => {
  const { userId } = await verifyUser(request);
  await deleteAccount(userId);
  return json({ deleted: true });
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

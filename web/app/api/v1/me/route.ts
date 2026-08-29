import { verifyUser } from "@/server/auth/verifyUser";
import { deleteAccount } from "@/server/domain/account/deleteAccount";
import { apiRoute, corsPreflight, json } from "@/server/http";

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

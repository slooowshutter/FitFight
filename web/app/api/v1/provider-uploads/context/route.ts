import { apiRoute, corsPreflight, json } from "@/lib/http";
import { verifyUser } from "@/lib/supabase/queries/auth-supabase-query";
import { getProviderUploadContext } from "@/lib/supabase/queries/provider-uploads-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

export const GET = apiRoute(async (request) => {
  console.info("[DEBUG-healthkit-context] request_received");
  try {
    console.info("[DEBUG-healthkit-context] authentication_started");
    const { userId } = await verifyUser(request);
    console.info("[DEBUG-healthkit-context] authentication_completed");

    console.info("[DEBUG-healthkit-context] context_query_started");
    const context = await getProviderUploadContext(userId);
    console.info("[DEBUG-healthkit-context] context_query_completed", {
      fight_window_count: context.fight_windows.length,
    });

    console.info("[DEBUG-healthkit-context] response_ready");
    return json(context);
  } catch (error) {
    const code = error && typeof error === "object" && "code" in error
      && typeof error.code === "string" ? error.code : null;
    console.error("[DEBUG-healthkit-context] request_failed", {
      error_name: error instanceof Error ? error.name : "unknown",
      error_code: code,
    });
    throw error;
  }
});

export function OPTIONS(request: Request) {
  return corsPreflight(request);
}

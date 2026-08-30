import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "../http";

function requiredEnv(name: "NEXT_PUBLIC_SUPABASE_URL" | "SUPABASE_SECRET_KEY"): string {
  const value =
    name === "SUPABASE_SECRET_KEY"
      ? process.env.SUPABASE_SECRET_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY
      : process.env.NEXT_PUBLIC_SUPABASE_URL;
  if (!value) {
    throw new ApiError(500, ERROR_CODES.config, `Missing ${name}`);
  }
  return value;
}

let cached: SupabaseClient | null = null;

export function createAdminClient(): SupabaseClient {
  if (cached) {
    return cached;
  }
  const url = requiredEnv("NEXT_PUBLIC_SUPABASE_URL");
  const key = requiredEnv("SUPABASE_SECRET_KEY");
  cached = createClient(url, key, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  return cached;
}

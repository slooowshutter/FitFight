import postgres, { type Sql } from "postgres";
import { ApiError, ERROR_CODES } from "../http";

let cached: Sql | null = null;

function databaseURL(): string {
  console.info("[DEBUG-postgres] configuration_started", {
    has_database_url: Boolean(process.env.DATABASE_URL),
    has_supabase_db_url: Boolean(process.env.SUPABASE_DB_URL),
    has_supabase_api_url: Boolean(process.env.NEXT_PUBLIC_SUPABASE_URL),
  });
  const value = process.env.DATABASE_URL ?? process.env.SUPABASE_DB_URL;
  if (!value) {
    console.error("[DEBUG-postgres] configuration_missing");
    throw new ApiError(500, ERROR_CODES.config, "Missing DATABASE_URL");
  }
  const apiURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
  let parsedDatabaseURL: URL;
  try {
    parsedDatabaseURL = new URL(value);
  } catch {
    console.error("[DEBUG-postgres] database_url_invalid");
    throw new ApiError(500, ERROR_CODES.config, "DATABASE_URL is invalid");
  }
  console.info("[DEBUG-postgres] database_url_parsed", {
    protocol: parsedDatabaseURL.protocol,
    port: parsedDatabaseURL.port || "default",
    host_kind: parsedDatabaseURL.hostname.endsWith(".pooler.supabase.com")
      ? "supabase_pooler"
      : parsedDatabaseURL.hostname.endsWith(".supabase.co")
        ? "supabase_direct"
        : "other",
    has_username: Boolean(parsedDatabaseURL.username),
    has_password: Boolean(parsedDatabaseURL.password),
  });
  if (apiURL) {
    try {
      const projectRef = new URL(apiURL).hostname.split(".")[0];
      const databaseUser = decodeURIComponent(parsedDatabaseURL.username);
      if (projectRef && databaseUser.includes(".") && !databaseUser.endsWith(`.${projectRef}`)) {
        console.error("[DEBUG-postgres] project_reference_mismatch");
        throw new ApiError(
          500,
          ERROR_CODES.config,
          "DATABASE_URL does not match NEXT_PUBLIC_SUPABASE_URL",
        );
      }
    } catch (error) {
      if (error instanceof ApiError) {
        throw error;
      }
      throw new ApiError(500, ERROR_CODES.config, "DATABASE_URL is invalid");
    }
  }
  console.info("[DEBUG-postgres] configuration_completed");
  return value;
}

/**
 * Server-only Postgres connection. Vercel uses Supavisor's transaction pooler,
 * which does not support prepared statements.
 */
export function createDatabaseClient(): Sql {
  if (cached) {
    console.info("[DEBUG-postgres] client_cache_hit");
    return cached;
  }
  console.info("[DEBUG-postgres] client_creation_started");
  cached = postgres(databaseURL(), {
    prepare: false,
    max: 3,
    idle_timeout: 20,
    connect_timeout: 10,
  });
  console.info("[DEBUG-postgres] client_creation_completed");
  return cached;
}

export async function closeDatabaseClientForTests(): Promise<void> {
  if (!cached) {
    return;
  }
  const client = cached;
  cached = null;
  await client.end({ timeout: 5 });
}

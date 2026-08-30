import postgres, { type Sql } from "postgres";
import { ApiError, ERROR_CODES } from "../http";

let cached: Sql | null = null;

function databaseURL(): string {
  const value = process.env.DATABASE_URL ?? process.env.SUPABASE_DB_URL;
  if (!value) {
    throw new ApiError(500, ERROR_CODES.config, "Missing DATABASE_URL");
  }
  const apiURL = process.env.NEXT_PUBLIC_SUPABASE_URL;
  let parsedDatabaseURL: URL;
  try {
    parsedDatabaseURL = new URL(value);
  } catch {
    throw new ApiError(500, ERROR_CODES.config, "DATABASE_URL is invalid");
  }
  if (apiURL) {
    try {
      const projectRef = new URL(apiURL).hostname.split(".")[0];
      const databaseUser = decodeURIComponent(parsedDatabaseURL.username);
      if (projectRef && databaseUser.includes(".") && !databaseUser.endsWith(`.${projectRef}`)) {
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
  return value;
}

/**
 * Server-only Postgres connection. Vercel uses Supavisor's transaction pooler,
 * which does not support prepared statements.
 */
export function createDatabaseClient(): Sql {
  if (cached) {
    return cached;
  }
  cached = postgres(databaseURL(), {
    prepare: false,
    max: 3,
    idle_timeout: 20,
    connect_timeout: 10,
  });
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

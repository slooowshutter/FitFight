import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { removeProviderInboxObjects } from "./provider-uploads-supabase-query";

type HistoryRow = { keep_profile: boolean };

/** Delete private data and login credentials while preserving anonymized Fight history. */
export async function deleteAccount(
  userId: string,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  try {
    await removeProviderInboxObjects(userId, database);
    await database.begin("read write", async (sql) => {
      const [profile] = await sql<{ user_id: string }[]>`
        select user_id from public.profiles
        where user_id = ${userId} and deleted_at is null
        for update
      `;
      if (!profile) {
        throw new ApiError(404, ERROR_CODES.not_found, "Account not found");
      }

      await sql`delete from private.healthkit_step_source_days where user_id = ${userId}`;
      await sql`delete from private.healthkit_step_sample_deletions where user_id = ${userId}`;
      await sql`delete from private.healthkit_step_samples where user_id = ${userId}`;
      await sql`delete from private.healthkit_step_syncs where user_id = ${userId}`;
      await sql`delete from private.fight_score_snapshots where user_id = ${userId}`;
      await sql`delete from private.metric_observations where user_id = ${userId}`;
      await sql`delete from private.provider_events where user_id = ${userId}`;
      await sql`delete from private.provider_uploads where user_id = ${userId}`;
      await sql`delete from public.metric_days where user_id = ${userId}`;
      await sql`delete from public.step_days where user_id = ${userId}`;
      await sql`
        update public.data_sources
        set source_label = 'Deleted source',
            contributing_source_labels = '{}',
            status = 'disconnected',
            revoked_at = now(),
            complete_through = null,
            last_error_code = null
        where user_id = ${userId}
      `;

      await sql`
        update public.profiles
        set deleted_at = now(),
            display_name = 'Deleted User',
            avatar_path = null,
            time_zone = null
        where user_id = ${userId}
      `;

      const [history] = await sql<HistoryRow[]>`
        select exists (
          select 1 from public.fights where owner_id = ${userId}
          union all
          select 1 from public.fight_members where user_id = ${userId}
          union all
          select 1 from public.friendships
          where requester_id = ${userId} or addressee_id = ${userId}
        ) as keep_profile
      `;

      await sql`delete from auth.sessions where user_id = ${userId}`;
      await sql`delete from auth.refresh_tokens where user_id = ${userId}`;
      await sql`delete from auth.identities where user_id = ${userId}`;

      if (!history?.keep_profile) {
        await sql`delete from auth.users where id = ${userId}`;
      } else {
        await sql`
          update auth.users
          set email = null,
              phone = null,
              encrypted_password = '',
              raw_app_meta_data = '{}',
              raw_user_meta_data = '{}',
              updated_at = now()
          where id = ${userId}
        `;
      }
    });
  } catch (error) {
    if (error instanceof ApiError) {
      throw error;
    }
    console.error("account_delete_failed", error instanceof Error ? error.name : "unknown");
    throw new ApiError(500, ERROR_CODES.db_error, "Could not delete account");
  }
}

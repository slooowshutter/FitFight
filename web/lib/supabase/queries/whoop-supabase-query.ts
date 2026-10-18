import type { Sql } from "postgres";
import type { sealAes256Gcm } from "@/lib/crypto/aes-256-gcm";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { insertActivityRaw } from "./activity-pipeline-supabase-query";
import type { ActivityRawRecord } from "@/lib/types/activity/activity-pipeline";
import {
    whoopConnectionRowSchema,
    type WhoopConnectionRow,
} from "@/lib/types/whoop/whoop";

type SealedTokens = ReturnType<typeof sealAes256Gcm>;

/** Starts a WHOOP sign-in. The state is single-use and expires after ten minutes. */
export async function saveWhoopState(
    userId: string,
    state: string,
    database: Sql = createDatabaseClient(),
): Promise<void> {
    await database`
        insert into private.whoop_connections (user_id, oauth_state, oauth_state_expires_at)
        values (${userId}, ${state}, now() + interval '10 minutes')
        on conflict (user_id) do update
        set oauth_state = excluded.oauth_state,
            oauth_state_expires_at = excluded.oauth_state_expires_at
    `;
}

/** True when this account started this sign-in less than ten minutes ago. Each state works once. */
export async function claimWhoopState(
    userId: string,
    state: string,
    database: Sql = createDatabaseClient(),
): Promise<boolean> {
    const rows = await database`
        update private.whoop_connections
        set oauth_state = null, oauth_state_expires_at = null
        where user_id = ${userId} and oauth_state = ${state} and oauth_state_expires_at > now()
        returning id
    `;
    return rows.length === 1;
}

/**
 * Saves a new WHOOP login. One WHOOP account belongs to one FitFight account at a time, so a WHOOP
 * account connected elsewhere moves here; the raw records it already sent stay with the other account.
 */
export async function saveWhoopConnection(
    userId: string,
    whoopUserId: number,
    tokens: SealedTokens,
    accessTokenExpiresAt: Date,
    database: Sql = createDatabaseClient(),
): Promise<void> {
    await database.begin("read write", async (sql) => {
        await sql`
            update private.whoop_connections
            set whoop_user_id = null, tokens_ciphertext = null, tokens_iv = null, tokens_tag = null,
                access_token_expires_at = null, last_error = 'moved_to_another_account'
            where whoop_user_id = ${whoopUserId} and user_id <> ${userId}
        `;
        await sql`
            update private.whoop_connections
            set history_synced_at = case when whoop_user_id = ${whoopUserId} then history_synced_at end,
                whoop_user_id = ${whoopUserId}, tokens_ciphertext = ${tokens.ciphertext},
                tokens_iv = ${tokens.iv}, tokens_tag = ${tokens.tag},
                access_token_expires_at = ${accessTokenExpiresAt}, connected_at = now(), last_error = null
            where user_id = ${userId}
        `;
        await sql`
            insert into public.data_sources (
                user_id, provider, source_label, connection_route, capabilities, status, consent_version,
                connected_at
            ) values (
                ${userId}, 'whoop', 'WHOOP', 'oauth',
                ${sql.array(["cycles", "recovery", "sleep", "workouts", "body"])}::text[], 'healthy', 1, now()
            )
            on conflict (user_id, provider, connection_route) do update
            set status = 'healthy', revoked_at = null, connected_at = now(), last_error_code = null
        `;
    });
}

export async function readWhoopConnection(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<WhoopConnectionRow | null> {
    const [row] = await database`
        select user_id, whoop_user_id, tokens_ciphertext, tokens_iv, tokens_tag, access_token_expires_at,
            last_synced_at, history_synced_at
        from private.whoop_connections
        where user_id = ${userId}
    `;
    return row ? whoopConnectionRowSchema.parse(row) : null;
}

/**
 * Runs `use` while holding the connection's row lock. WHOOP invalidates a refresh token the moment it
 * is used, so two syncs refreshing at once would sign the person out; the lock makes the second wait
 * and reuse the first one's new token. `save(null)` forgets tokens WHOOP no longer accepts.
 */
export async function withLockedWhoopConnection(
    userId: string,
    use: (
        row: WhoopConnectionRow | null,
        save: (
            tokens: SealedTokens | null,
            accessTokenExpiresAt: Date | null,
        ) => Promise<void>,
    ) => Promise<string | null>,
    database: Sql = createDatabaseClient(),
): Promise<string | null> {
    return database.begin("read write", async (sql) => {
        const [row] = await sql`
            select user_id, whoop_user_id, tokens_ciphertext, tokens_iv, tokens_tag,
                access_token_expires_at, last_synced_at, history_synced_at
            from private.whoop_connections
            where user_id = ${userId}
            for update
        `;
        return use(
            row ? whoopConnectionRowSchema.parse(row) : null,
            async (tokens, accessTokenExpiresAt) => {
                await sql`
                    update private.whoop_connections
                    set tokens_ciphertext = ${tokens?.ciphertext ?? null}, tokens_iv = ${tokens?.iv ?? null},
                        tokens_tag = ${tokens?.tag ?? null}, access_token_expires_at = ${accessTokenExpiresAt},
                        last_error = ${tokens ? null : "whoop_access_revoked"}
                    where user_id = ${userId}
                `;
            },
        );
    });
}

export async function findWhoopUser(
    whoopUserId: number,
    database: Sql = createDatabaseClient(),
): Promise<string | null> {
    const [row] = await database<{ user_id: string }[]>`
        select user_id from private.whoop_connections
        where whoop_user_id = ${whoopUserId} and tokens_ciphertext is not null
    `;
    return row?.user_id ?? null;
}

/** People to sync this hour, longest-waiting first, so a run that stops early still rotates through everyone. */
export async function listWhoopUsersToSync(
    database: Sql = createDatabaseClient(),
): Promise<string[]> {
    const rows = await database<{ user_id: string }[]>`
        select user_id from private.whoop_connections
        where tokens_ciphertext is not null
        order by last_synced_at nulls first
    `;
    return rows.map((row) => row.user_id);
}

/**
 * Stores WHOOP records raw, as WHOOP sent them, and records how the sync went. A record whose content
 * changed (a cycle's strain during the day, a rescored sleep) is a new row; identical content is not.
 */
export async function saveWhoopRecords(
    userId: string,
    records: ActivityRawRecord[],
    sync: { history: boolean; error: string | null } | null,
    database: Sql = createDatabaseClient(),
): Promise<void> {
    await database.begin("read write", async (sql) => {
        // A webhook's deletion record is not a sync, so it leaves the sync status alone.
        const [source] = sync
            ? await sql<{ id: string }[]>`
                update public.data_sources
                set last_success_at = case when ${sync.error}::text is null then now() else last_success_at end,
                    last_error_code = ${sync.error}
                where user_id = ${userId} and provider = 'whoop' and connection_route = 'oauth'
                returning id
            `
            : await sql<{ id: string }[]>`
                select id from public.data_sources
                where user_id = ${userId} and provider = 'whoop' and connection_route = 'oauth'
            `;
        await insertActivityRaw(
            sql,
            userId,
            source.id,
            new Date().toISOString(),
            records,
        );
        if (sync) {
            await sql`
                update private.whoop_connections
                set last_synced_at = case when ${sync.error}::text is null then now() else last_synced_at end,
                    history_synced_at = case when ${sync.history && !sync.error} then now() else history_synced_at end,
                    last_error = ${sync.error}
                where user_id = ${userId}
            `;
        }
    });
}

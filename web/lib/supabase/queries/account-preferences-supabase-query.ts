import type { Sql } from "postgres";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    accountPreferencesSchema,
    defaultAccountPreferences,
    type AccountPreferences,
    type UpdateAccountPreferencesRequest,
} from "@/lib/types/profiles/account-preferences";

export async function readAccountPreferences(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<AccountPreferences> {
    const [row] = await database`
        select language, appearance
        from private.account_preferences
        where user_id = ${userId}
    `;
    return row ? accountPreferencesSchema.parse(row) : defaultAccountPreferences;
}

/** Updates only supplied fields, including when two devices save concurrently. */
export async function updateAccountPreferences(
    userId: string,
    input: UpdateAccountPreferencesRequest,
    database: Sql = createDatabaseClient(),
): Promise<AccountPreferences> {
    const [row] = await database`
        insert into private.account_preferences (user_id, language, appearance)
        values (
            ${userId},
            ${input.language ?? defaultAccountPreferences.language},
            ${input.appearance ?? defaultAccountPreferences.appearance}
        )
        on conflict (user_id) do update set
            language = case when ${input.language !== undefined}
                then excluded.language else account_preferences.language end,
            appearance = case when ${input.appearance !== undefined}
                then excluded.appearance else account_preferences.appearance end,
            updated_at = now()
        returning language, appearance
    `;
    return accountPreferencesSchema.parse(row);
}

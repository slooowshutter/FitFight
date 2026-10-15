import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";

/**
 * Dev only: a one-time magic-link token for the account that already uses `email`, or null. Never creates an account,
 * because generating a magic link for an unknown email would sign one up. Nothing is emailed.
 */
export async function mintDevSignInToken(
    email: string,
): Promise<string | null> {
    const [account] = await createDatabaseClient()`
        select id from auth.users where lower(email) = lower(${email}) and deleted_at is null
    `;
    if (!account) return null;
    const { data, error } = await createAdminClient().auth.admin.generateLink({
        type: "magiclink",
        email,
    });
    if (error) throw error;
    return data.properties.hashed_token;
}

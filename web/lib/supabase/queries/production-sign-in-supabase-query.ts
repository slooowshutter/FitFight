import { createClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { authProjects } from "@/lib/supabase/auth-projects";

/** A one-time magic-link token for an existing production account. Nothing is emailed. */
export async function mintProductionSignInToken(
    productionUserId: string,
): Promise<string> {
    // NOTE: Marc keeps this key only in his local web/.env.local (18 Oct 2026), never in Vercel.
    const key = process.env.PRODUCTION_SUPABASE_SECRET_KEY;
    if (!key) {
        throw new ApiError(
            503,
            ERROR_CODES.config,
            "Add production's secret key to web/.env.local as PRODUCTION_SUPABASE_SECRET_KEY (supabase projects api-keys --project-ref pvqntpteehdvhqyctwum --reveal), then restart npm run dev.",
        );
    }
    const production = createClient(
        authProjects.pvqntpteehdvhqyctwum.url,
        key,
        {
            auth: { persistSession: false, autoRefreshToken: false },
        },
    );
    const account = await production.auth.admin.getUserById(productionUserId);
    if (account.error || !account.data.user.email) {
        throw new ApiError(
            502,
            ERROR_CODES.db_error,
            `Production: ${account.error?.message ?? "the account has no sign-in email"}`,
        );
    }
    const link = await production.auth.admin.generateLink({
        type: "magiclink",
        email: account.data.user.email,
    });
    if (link.error) {
        throw new ApiError(
            502,
            ERROR_CODES.db_error,
            `Production: ${link.error.message}`,
        );
    }
    return link.data.properties.hashed_token;
}

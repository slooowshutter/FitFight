import { createClient } from "@supabase/supabase-js";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { authProjects } from "@/lib/supabase/auth-projects";

/** A one-time magic-link token for an existing production account. Nothing is emailed. */
export async function mintProductionSignInToken(
    productionUserId: string,
): Promise<string> {
    // NOTE: Marc keeps this key only in his local web/.env.local (18 Oct 2026), never in Vercel, so a deployed staging
    // server answers 503 and the switch works from localhost only.
    const key = process.env.PRODUCTION_SUPABASE_SECRET_KEY;
    if (!key) {
        throw new ApiError(
            503,
            ERROR_CODES.config,
            "Production opens only from localhost. Signing you in to production needs production's secret key, which is only in web/.env.local on your Mac (PRODUCTION_SUPABASE_SECRET_KEY), never on staging.fitfight.app. The Admin page still shows production numbers here.",
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

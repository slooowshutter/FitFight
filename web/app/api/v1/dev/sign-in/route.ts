import { isLocalDevRequest } from "@/lib/dev/local-dev-request";
import { ApiError, ERROR_CODES, apiRoute, json } from "@/lib/http";
import { mintDevSignInToken } from "@/lib/supabase/queries/dev-sign-in-supabase-query";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/**
 * `next dev` on localhost only: signs the web app in as `DEV_AUTOLOGIN_EMAIL` (same switch as Blend), so local testing
 * skips Apple and Google, which only accept fitfight.app. Vercel runs NODE_ENV=production and has no such variable.
 */
export const POST = apiRoute(async (request) => {
    const email = process.env.DEV_AUTOLOGIN_EMAIL;
    if (!email || !isLocalDevRequest(request)) {
        throw new ApiError(404, ERROR_CODES.not_found, "Not found");
    }
    const tokenHash = await mintDevSignInToken(email);
    if (!tokenHash) {
        throw new ApiError(
            404,
            ERROR_CODES.not_found,
            `No account uses ${email}`,
        );
    }
    return json({ token_hash: tokenHash });
});

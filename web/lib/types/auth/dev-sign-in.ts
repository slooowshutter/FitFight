import { z } from "zod";

/**
 * `POST /api/v1/dev/sign-in` (`next dev` only) and `POST /api/v1/admin/production-sign-in`: a one-time magic-link
 * token the browser trades for a session.
 */
export const signInTokenResponseSchema = z.object({
    token_hash: z.string().min(1),
});

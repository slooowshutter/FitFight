import { z } from "zod";

/** `POST /api/v1/dev/sign-in` (`next dev` only): a one-time magic-link token the browser trades for a session. */
export const devSignInResponseSchema = z.object({
    token_hash: z.string().min(1),
});

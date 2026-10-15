import { z } from "zod";

/** The answer to deleting a post or a feedback request. */
export const deletedResponseSchema = z.object({ deleted: z.literal(true) });

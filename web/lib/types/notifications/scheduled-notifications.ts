import { z } from "zod";

export const digestCandidateSchema = z.object({
    user_id: z.string().uuid(),
    digest_on: z.string(),
});
export const digestEventSchema = z.object({
    id: z.string().uuid(),
    fight_id: z.string().uuid(),
    route: z.string(),
});
export type DigestCandidate = z.infer<typeof digestCandidateSchema>;
export type DigestEvent = z.infer<typeof digestEventSchema>;

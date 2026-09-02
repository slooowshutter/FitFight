import { z } from "zod";

export const requestKindValues = ["feature", "bug"] as const;
export const requestKindSchema = z.enum(requestKindValues);

export const requestStatusValues = ["open", "planned", "shipped"] as const;
export const requestStatusSchema = z.enum(requestStatusValues);

export const createFeatureRequestSchema = z
  .object({
    kind: requestKindSchema,
    title: z.string().trim().min(1).max(80),
    body: z.string().trim().min(1).max(500),
  })
  .strict();

export const listFeatureRequestsQuerySchema = z
  .object({
    kind: requestKindSchema.optional(),
  })
  .strict();

export const featureRequestAuthorSchema = z.object({
  userId: z.string().uuid(),
  handle: z.string(),
  displayName: z.string(),
});

export const featureRequestSchema = z.object({
  id: z.string().uuid(),
  kind: requestKindSchema,
  status: requestStatusSchema,
  title: z.string(),
  body: z.string(),
  voteCount: z.number().int().nonnegative(),
  voted: z.boolean(),
  createdAt: z.string(),
  author: featureRequestAuthorSchema,
});

export const featureRequestListSchema = z.object({
  items: z.array(featureRequestSchema),
});

export const featureRequestRowSchema = z.object({
  id: z.string().uuid(),
  kind: requestKindSchema,
  status: requestStatusSchema,
  title: z.string(),
  body: z.string(),
  created_at: z.coerce.date(),
  author_user_id: z.string().uuid(),
  author_handle: z.string(),
  author_display_name: z.string(),
  vote_count: z.coerce.number().int(),
  voted: z.boolean(),
});

export type RequestKind = z.infer<typeof requestKindSchema>;
export type RequestStatus = z.infer<typeof requestStatusSchema>;
export type CreateFeatureRequest = z.infer<typeof createFeatureRequestSchema>;
export type FeatureRequest = z.infer<typeof featureRequestSchema>;
export type FeatureRequestList = z.infer<typeof featureRequestListSchema>;
export type FeatureRequestRow = z.infer<typeof featureRequestRowSchema>;

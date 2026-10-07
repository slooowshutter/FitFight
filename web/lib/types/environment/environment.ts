import { z } from "zod";

export const environmentNameValues = ["beta", "production"] as const;
export const environmentNameSchema = z.enum(environmentNameValues);

export const environmentResponseSchema = z.object({
    environment: environmentNameSchema,
});

export type EnvironmentName = z.infer<typeof environmentNameSchema>;
export type EnvironmentResponse = z.infer<typeof environmentResponseSchema>;

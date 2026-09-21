import { z } from "zod";

const marketingVersionSchema = z.preprocess(
    (value) =>
        typeof value === "string" && /^\d+\.\d+$/.test(value)
            ? `${value}.0`
            : value,
    z.string().regex(/^\d+\.\d+\.\d+$/),
);

export const appReleaseSchema = z.object({
    version: marketingVersionSchema,
    build: z.number().int().positive().safe(),
    update_url: z.union([
        z.literal("itms-beta://"),
        z.string().regex(/^https:\/\/apps\.apple\.com\/app\/id\d+$/),
    ]),
});

export const appReleasePolicySchema = z.object({
    latest: appReleaseSchema.nullable(),
    review: appReleaseSchema.nullable(),
    internal: appReleaseSchema.nullable().optional(),
    enforced: z.boolean(),
});

const stagingReleaseSchema = appReleaseSchema.extend({
    update_url: z.literal("itms-beta://"),
});
const prodReleaseSchema = appReleaseSchema.extend({
    update_url: z.string().regex(/^https:\/\/apps\.apple\.com\/app\/id\d+$/),
});

export const stagingAppReleasePolicySchema = appReleasePolicySchema.extend({
    latest: stagingReleaseSchema.nullable(),
    review: stagingReleaseSchema.nullable(),
    internal: stagingReleaseSchema.nullable().optional(),
});

export const prodAppReleasePolicySchema = appReleasePolicySchema.extend({
    latest: prodReleaseSchema.nullable(),
    review: prodReleaseSchema.nullable(),
    internal: prodReleaseSchema.nullable().optional(),
});

export const appReleaseManifestSchema = z.object({
    staging: stagingAppReleasePolicySchema,
    prod: prodAppReleasePolicySchema,
});

export const appReleaseProjectValues = [
    "https://zstzbfocunthczzubggz.supabase.co",
    "https://pvqntpteehdvhqyctwum.supabase.co",
] as const;
export const appReleaseProjectSchema = z.enum(appReleaseProjectValues);

export const testFlightAppStorePromptSchema = z.enum(["true", "false"]).optional();

export type AppRelease = z.infer<typeof appReleaseSchema>;
export type AppReleasePolicy = z.infer<typeof appReleasePolicySchema>;
export type AppReleaseManifest = z.infer<typeof appReleaseManifestSchema>;
export type AppReleaseProject = z.infer<typeof appReleaseProjectSchema>;
export type TestFlightAppStorePrompt = z.infer<typeof testFlightAppStorePromptSchema>;

import { z } from "zod";

export const appLanguageValues = ["system", "en", "fr"] as const;
export const appAppearanceValues = ["system", "light", "dark"] as const;
export const appLanguageSchema = z.enum(appLanguageValues);
export const appAppearanceSchema = z.enum(appAppearanceValues);

export const accountPreferencesSchema = z.object({
    language: appLanguageSchema,
    appearance: appAppearanceSchema,
});

export const updateAccountPreferencesRequestSchema = accountPreferencesSchema
    .partial()
    .strict()
    .refine((input) => Object.keys(input).length > 0, {
        message: "Choose a language or appearance",
    });

export type AccountPreferences = z.infer<typeof accountPreferencesSchema>;
export type UpdateAccountPreferencesRequest = z.infer<
    typeof updateAccountPreferencesRequestSchema
>;

export const defaultAccountPreferences: AccountPreferences = {
    language: "system",
    appearance: "system",
};

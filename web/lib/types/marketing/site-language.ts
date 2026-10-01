import { z } from "zod";

export const siteLanguageValues = ["en", "fr"] as const;
export const siteLanguageSchema = z.enum(siteLanguageValues);

export type SiteLanguage = z.infer<typeof siteLanguageSchema>;

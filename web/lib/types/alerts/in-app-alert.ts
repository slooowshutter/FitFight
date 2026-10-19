import { z } from "zod";
import type { InstallableRelease } from "@/lib/types/releases/app-release";

export const alertLanguageValues = ["en", "fr"] as const;
export const alertActionValues = ["update", "open_character", "choose_companion", "new_fight", "dismiss"] as const;
export const alertResponseValues = ["shown", "tapped", "dismissed"] as const;

export const alertActionSchema = z.enum(alertActionValues);

/** `url` is set only for `update`: the App Store, or TestFlight on staging. */
export const inAppAlertSchema = z.object({
    id: z.string(),
    title: z.string(),
    body: z.string(),
    image_url: z.string().url().nullable(),
    buttons: z.array(
        z.object({
            title: z.string(),
            action: alertActionSchema,
            url: z.string().nullable(),
            primary: z.boolean(),
        }),
    ),
});

export const inAppAlertListSchema = z.object({
    alerts: z.array(inAppAlertSchema),
});

export const alertResponseRequestSchema = z
    .object({
        response: z.enum(alertResponseValues),
        action: alertActionSchema.optional(),
    })
    .strict();

export const alertAppVersionSchema = z.string().regex(/^\d{1,6}\.\d{1,6}\.\d{1,6}$/);

export const alertFactsRowSchema = z.object({
    days_since_signup: z.coerce.number().int(),
    fights: z.coerce.number().int(),
    custom_characters: z.coerce.number().int(),
    companion_picture: z.boolean(),
    purchases: z.coerce.number().int(),
    friends: z.coerce.number().int(),
    steps_last_7_days: z.coerce.number(),
    answered: z.array(z.string()),
});

export type AlertLanguage = (typeof alertLanguageValues)[number];
export type AlertAction = z.infer<typeof alertActionSchema>;
export type InAppAlert = z.infer<typeof inAppAlertSchema>;
export type AlertResponseRequest = z.infer<typeof alertResponseRequestSchema>;
export type AlertFactsRow = z.infer<typeof alertFactsRowSchema>;

/** Everything an alert's `who` rule can read. Add a fact here and in readAlertFacts. */
export type AlertFacts = {
    /** The calling app's marketing version, e.g. "1.2.0". */
    appVersion: string;
    /** The newest build people can install here, or null when Apple cannot be read. */
    latestRelease: InstallableRelease | null;
    daysSinceSignup: number;
    /** Fights joined, not counting the app-wide, suggested, founder, and monthly friend fights made for people. */
    fights: number;
    /** Custom characters owned, paid or free. */
    customCharacters: number;
    /** Their picture is companion art: a stock animal, a Special, or a custom character with a portrait. False with no companion or a words-only custom animal. */
    companionPicture: boolean;
    /** Paid custom characters plus Specials bought. */
    purchases: number;
    friends: number;
    /** Apple Health Steps over the 7 days before today. */
    stepsLast7Days: number;
    /** Alerts this person already tapped or closed. */
    answered: ReadonlySet<string>;
};

type AlertText = Record<AlertLanguage, string>;

export type AlertDefinition = {
    /** Stable forever: responses are stored under it. Lowercase letters, digits, hyphens. */
    id: string;
    who: (facts: AlertFacts) => boolean;
    title: AlertText;
    body: AlertText;
    /** A file under web/public, e.g. "/landing/companion-alpaca-1.webp". */
    image?: string;
    buttons: { title: AlertText; action: AlertAction }[];
};

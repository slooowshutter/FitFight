import { z } from "zod";

export const timeZoneSchema = z
    .string()
    .min(1)
    .max(100)
    .refine((value) => {
        try {
            Intl.DateTimeFormat("en-US", { timeZone: value }).format();
            return true;
        } catch {
            return false;
        }
    }, "invalid time zone");

export type TimeZone = z.infer<typeof timeZoneSchema>;

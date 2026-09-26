import { z } from "zod";

export const fitFightAdminEmailValues = ["marc@marclamy.com"] as const;
export const fitFightAdminHandleValues = ["marc"] as const;

export type FitFightAdminViewer = {
    handle: string;
    emails: string[];
};

export const fitFightAdminProfileSchema = z.object({
    handle: z.string().trim().min(1),
});

export type FitFightAdminProfile = z.infer<typeof fitFightAdminProfileSchema>;

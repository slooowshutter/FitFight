import { z } from "zod";

export const fitFightAdminEmailValues = ["marc@marclamy.com"] as const;
export const fitFightAdminHandleValues = ["marc"] as const;
/** Marc's accounts: staging (TestFlight) and production. Account IDs never change. */
export const fitFightAdminUserIdValues = [
    "87434630-dd64-4465-b79b-fd99e35368be",
    "854ed9b9-5de9-4d85-b10e-e201deb999de",
] as const;

export type FitFightAdminViewer = {
    handle: string;
    emails: string[];
};

export const fitFightAdminProfileSchema = z.object({
    handle: z.string().trim().min(1),
});

export type FitFightAdminProfile = z.infer<typeof fitFightAdminProfileSchema>;

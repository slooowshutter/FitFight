import { z } from "zod";
import { adminDashboardEnvironmentSchema } from "./admin-dashboard";

export const adminUsersQuerySchema = z.object({
    environment: adminDashboardEnvironmentSchema.optional(),
    limit: z.coerce.number().int().min(1).max(100).default(10),
    offset: z.coerce.number().int().min(0).default(0),
});

/** One account, read with the dashboard's own rules. Times are UTC ISO 8601. */
export const adminUserSchema = z.object({
    user_id: z.string().uuid(),
    handle: z.string(),
    /** False while the account still has the username FitFight generated at signup. */
    handle_set: z.boolean(),
    display_name: z.string(),
    /** Null when the account has none, or when the database cannot show it yet (see `note`). */
    email: z.string().nullable(),
    /** Supabase Auth providers, such as apple or google. Null when the database cannot show them yet. */
    providers: z.array(z.string()).nullable(),
    created_at: z.string(),
    friends: z.number().int(),
    /** In the Everybody fight's series now: joined in onboarding or later, and not left. */
    everybody_fight: z.boolean(),
    /** Fights joined, a repeating Fight once, by the dashboard's "joined a fight" rule. */
    fights: z.number().int(),
    /** The referrer's username, when a referral was claimed within 7 days of signing up. */
    referred_by: z.string().nullable(),
    /** Signups this account's referral link brought. */
    referrals: z.number().int(),
    /** The phone has sent at least one Apple Health day with steps. */
    health_connected: z.boolean(),
    last_synced_at: z.string().nullable(),
    /** "1.2.1 (234)": the build of the account's newest Apple Health sync report. */
    app_version: z.string().nullable(),
    /** A device registered for push notifications now. */
    notifications: z.boolean(),
    time_zone: z.string().nullable(),
});

export const adminUsersSchema = z.object({
    environment: adminDashboardEnvironmentSchema,
    /** Every account, deleted ones left out. */
    total: z.number().int(),
    /** Newest signup first. */
    users: z.array(adminUserSchema),
    note: z.string().nullable(),
});

export const adminUsersCountRowSchema = z.object({ total: z.number().int(), accounts: z.boolean() });

export type AdminUser = z.infer<typeof adminUserSchema>;
export type AdminUsers = z.infer<typeof adminUsersSchema>;

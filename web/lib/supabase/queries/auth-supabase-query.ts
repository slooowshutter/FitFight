import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import type { Sql } from "postgres";
import { z } from "zod";
import { isFitFightAdmin } from "@/lib/admin/is-fitfight-admin";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    adminDashboardIdentityRowSchema,
    adminDashboardIdentitySchema,
    adminDashboardLinkedAccountSchema,
    adminDashboardProductionAdminRowSchema,
    type AdminDashboardIdentity,
} from "@/lib/types/admin/admin-dashboard";
import {
    fitFightAdminProfileSchema,
    type FitFightAdminViewer,
} from "@/lib/types/admin/fitfight-admin";

export type AuthedUser = {
    userId: string;
};

function bearerToken(request: Request): string {
    const header =
        request.headers.get("authorization") ??
        request.headers.get("Authorization");
    if (!header) {
        throw new ApiError(
            401,
            ERROR_CODES.unauthorized,
            "Missing bearer token",
        );
    }
    const match = /^Bearer\s+(\S+)/i.exec(header.trim());
    if (!match?.[1]) {
        throw new ApiError(
            401,
            ERROR_CODES.unauthorized,
            "Missing bearer token",
        );
    }
    return match[1];
}

function claimSub(claims: unknown): string | null {
    if (!claims || typeof claims !== "object") {
        return null;
    }
    const sub = (claims as { sub?: unknown }).sub;
    return typeof sub === "string" && sub.length > 0 ? sub : null;
}

async function requireActiveProfile(
    admin: SupabaseClient,
    userId: string,
): Promise<void> {
    const { data, error } = await admin
        .from("profiles")
        .select("id")
        .eq("id", userId)
        .is("deleted_at", null)
        .maybeSingle();
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not verify account",
        );
    }
    if (!data) {
        throw new ApiError(
            401,
            ERROR_CODES.profile_missing,
            "Invalid or deleted account",
        );
    }
}

export async function verifyUser(request: Request): Promise<AuthedUser> {
    const jwt = bearerToken(request);
    const admin = createAdminClient();

    const claimsResult = await admin.auth.getClaims(jwt);
    const fromClaims = claimSub(claimsResult.data?.claims);
    if (fromClaims) {
        await requireActiveProfile(admin, fromClaims);
        return { userId: fromClaims };
    }

    const userResult = await admin.auth.getUser(jwt);
    const userId = userResult.data.user?.id;
    if (userId) {
        await requireActiveProfile(admin, userId);
        return { userId };
    }

    throw new ApiError(
        401,
        ERROR_CODES.unauthorized,
        "Invalid or expired token",
    );
}

export async function readAdminViewer(
    userId: string,
    admin: SupabaseClient = createAdminClient(),
): Promise<FitFightAdminViewer> {
    const { data, error } = await admin
        .from("profiles")
        .select("handle")
        .eq("id", userId)
        .is("deleted_at", null)
        .maybeSingle();
    if (error) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not verify account",
        );
    }
    const profile = fitFightAdminProfileSchema.safeParse(data);
    if (!profile.success) {
        throw new ApiError(
            401,
            ERROR_CODES.profile_missing,
            "Invalid or deleted account",
        );
    }

    const userResult = await admin.auth.admin.getUserById(userId);
    if (userResult.error || !userResult.data.user) {
        throw new ApiError(
            500,
            ERROR_CODES.db_error,
            "Could not verify account",
        );
    }

    const user = userResult.data.user;
    // User-editable metadata must never grant admin access.
    const emails = user.email && user.email_confirmed_at ? [user.email] : [];
    return { handle: profile.data.handle, emails };
}

/** Both projects' public Auth endpoints. Publishable keys are client configuration, not secrets. */
const authProjects: Record<string, { url: string; publishableKey: string }> = {
    pvqntpteehdvhqyctwum: {
        url: "https://pvqntpteehdvhqyctwum.supabase.co",
        publishableKey: "sb_publishable_6wP1KNFvJwIE_hX1U2aTfg_u3sk40Li",
    },
    zstzbfocunthczzubggz: {
        url: "https://zstzbfocunthczzubggz.supabase.co",
        publishableKey: "sb_publishable_7lCDQ1YbMJVUyKZ6Ezq1LA_I-0rZGig",
    },
};

/**
 * The dashboard reads aggregates only. A login from the other FitFight project (an App Store
 * build signs in to production) is accepted when the same Apple or Google account owns an
 * admin profile here, so Marc never signs in twice. Returns the admin's Apple and Google
 * accounts for `verifyProductionDashboardAdmin`.
 */
export async function verifyDashboardAdmin(request: Request): Promise<AdminDashboardIdentity[]> {
    const project = request.headers.get("x-fitfight-auth-project");
    const own = new URL(z.string().url().parse(process.env.NEXT_PUBLIC_SUPABASE_URL)).hostname.split(".")[0];
    if (!project || project === own) {
        const { userId } = await verifyUser(request);
        if (isFitFightAdmin(await readAdminViewer(userId))) {
            const rows = await createDatabaseClient()`
                select provider, provider_id as subject
                from auth.identities
                where user_id = ${userId} and provider in ('apple', 'google')
            `;
            return rows.map((row) => adminDashboardIdentityRowSchema.parse(row));
        }
    } else {
        const other = authProjects[project];
        if (!other) {
            throw new ApiError(401, ERROR_CODES.unauthorized, "Unknown sign-in project");
        }
        const { data, error } = await createClient(other.url, other.publishableKey, {
            auth: { persistSession: false, autoRefreshToken: false },
        }).auth.getUser(bearerToken(request));
        if (error || !data.user) {
            throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid or expired token");
        }
        const linked = (data.user.identities ?? [])
            .filter((identity) => identity.provider === "apple" || identity.provider === "google")
            .map((identity) => adminDashboardIdentitySchema.parse(identity));
        if (linked.length > 0) {
            const sql = createDatabaseClient();
            const rows = await sql`
                select distinct identity.user_id::text as user_id
                from auth.identities as identity
                join unnest(
                    ${linked.map((identity) => identity.provider)}::text[],
                    ${linked.map((identity) => identity.identity_data.sub)}::text[]
                ) as account(provider, subject)
                    on account.provider = identity.provider and account.subject = identity.provider_id
            `;
            for (const row of rows) {
                const userId = adminDashboardLinkedAccountSchema.parse(row).user_id;
                if (isFitFightAdmin(await readAdminViewer(userId))) {
                    return linked.map((identity) => ({
                        provider: identity.provider,
                        subject: identity.identity_data.sub,
                    }));
                }
            }
        }
    }
    throw new ApiError(403, ERROR_CODES.forbidden, "Only the FitFight admin can open the dashboard");
}

/**
 * Production data read by another project's server also needs one of the admin's Apple or
 * Google accounts to own an admin profile in production.
 */
export async function verifyProductionDashboardAdmin(
    identities: AdminDashboardIdentity[],
    production: Sql,
): Promise<void> {
    const rows = await production`
        select p.handle, u.email, u.email_confirmed_at is not null as email_confirmed
        from auth.identities as identity
        join unnest(
            ${identities.map((identity) => identity.provider)}::text[],
            ${identities.map((identity) => identity.subject)}::text[]
        ) as account(provider, subject)
            on account.provider = identity.provider and account.subject = identity.provider_id
        join public.profiles as p on p.user_id = identity.user_id and p.deleted_at is null
        join auth.users as u on u.id = identity.user_id
    `;
    for (const row of rows) {
        const { handle, email, email_confirmed } = adminDashboardProductionAdminRowSchema.parse(row);
        if (isFitFightAdmin({ handle, emails: email && email_confirmed ? [email] : [] })) return;
    }
    throw new ApiError(403, ERROR_CODES.forbidden, "Your account isn't the FitFight admin in production");
}

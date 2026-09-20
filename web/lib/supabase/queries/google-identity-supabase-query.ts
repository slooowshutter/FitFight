import { randomUUID } from "node:crypto";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    emailFromGoogleClaims,
    verifyGoogleIdToken,
} from "@/lib/google/google-id-token";
import type { GoogleIdTokenClaims } from "@/lib/types/auth/google-sign-in";

export type GoogleAccountCandidate = {
    userId: string;
    createdAt: string;
    handle: string | null;
    handleSetAt: string | null;
};

export type DisposableGoogleAccount = {
    otherProviders: number;
    fightMemberships: number;
    ownedFights: number;
    handle: string | null;
    handleSetAt: string | null;
};

const generatedHandle = /^user_[a-z0-9]{12}$/;

export function chooseAccountToKeep(
    candidates: GoogleAccountCandidate[],
): string | null {
    if (candidates.length === 0) return null;
    const real = candidates.filter((candidate) => candidate.handleSetAt);
    if (real.length > 1) return null;
    if (real.length === 1) return real[0].userId;
    return [...candidates].sort((left, right) =>
        left.createdAt < right.createdAt ? -1 : 1,
    )[0].userId;
}

export function isDisposableGoogleAccount(
    account: DisposableGoogleAccount,
): boolean {
    if (account.otherProviders > 0) return false;
    if (account.fightMemberships > 0 || account.ownedFights > 0) return false;
    if (!account.handle) return true;
    return (
        account.handleSetAt === null && generatedHandle.test(account.handle)
    );
}

async function loadCandidates(
    email: string,
    database: Sql,
): Promise<GoogleAccountCandidate[]> {
    const rows = await database<GoogleAccountCandidate[]>`
        select
            account.user_id as "userId",
            min(account.created_at) as "createdAt",
            min(profile.handle) as handle,
            min(profile.handle_set_at) as "handleSetAt"
        from (
            select id as user_id, created_at
            from auth.users
            where deleted_at is null
                and email_confirmed_at is not null
                and lower(email) = ${email}
            union
            select users.id as user_id, users.created_at
            from auth.identities identities
            join auth.users users on users.id = identities.user_id
            where users.deleted_at is null
                and identities.provider in ('apple', 'google', 'email')
                and lower(identities.identity_data->>'email') = ${email}
        ) account
        left join public.profiles profile
            on profile.user_id = account.user_id
            and profile.deleted_at is null
        group by account.user_id
    `;
    return rows;
}

async function googleIdentityOwner(
    subject: string,
    database: Sql,
): Promise<string | null> {
    const [row] = await database<{ user_id: string }[]>`
        select identities.user_id
        from auth.identities identities
        join auth.users users on users.id = identities.user_id
        where identities.provider = 'google'
            and identities.provider_id = ${subject}
            and users.deleted_at is null
    `;
    return row?.user_id ?? null;
}

async function readDisposableState(
    userId: string,
    database: Sql,
): Promise<DisposableGoogleAccount> {
    const [row] = await database<DisposableGoogleAccount[]>`
        select
            (
                select count(*)::integer
                from auth.identities
                where user_id = ${userId} and provider <> 'google'
            ) as "otherProviders",
            (
                select count(*)::integer
                from public.fight_members
                where user_id = ${userId} and state <> 'invited'
            ) as "fightMemberships",
            (
                select count(*)::integer
                from public.fights
                where owner_id = ${userId}
            ) as "ownedFights",
            profile.handle,
            profile.handle_set_at as "handleSetAt"
        from (select ${userId}::uuid as user_id) account
        left join public.profiles profile
            on profile.user_id = account.user_id
            and profile.deleted_at is null
    `;
    return (
        row ?? {
            otherProviders: 0,
            fightMemberships: 0,
            ownedFights: 0,
            handle: null,
            handleSetAt: null,
        }
    );
}

async function attachGoogleIdentity(
    userId: string,
    claims: GoogleIdTokenClaims,
    database: Sql,
): Promise<void> {
    const email = emailFromGoogleClaims(claims);
    const identityData = {
        iss: claims.iss,
        sub: claims.sub,
        email,
        email_verified: true,
        provider_id: claims.sub,
    };
    await database`
        insert into auth.identities (
            id,
            user_id,
            identity_data,
            provider,
            provider_id,
            last_sign_in_at,
            created_at,
            updated_at
        ) values (
            ${randomUUID()},
            ${userId},
            ${database.json(identityData)},
            'google',
            ${claims.sub},
            now(),
            now(),
            now()
        )
    `;
    const [user] = await database<{ raw_app_meta_data: Record<string, unknown> | null }[]>`
        select raw_app_meta_data from auth.users where id = ${userId}
    `;
    const metadata = user?.raw_app_meta_data ?? {};
    const providers = new Set(
        Array.isArray(metadata.providers)
            ? metadata.providers.filter((value): value is string => typeof value === "string")
            : [],
    );
    providers.add("google");
    if (typeof metadata.provider !== "string") {
        metadata.provider = "google";
    }
    await database`
        update auth.users
        set raw_app_meta_data = ${database.json({
            ...metadata,
            providers: [...providers],
        })},
            updated_at = now()
        where id = ${userId}
    `;
}

export async function reconcileGoogleIdentity(
    input: { idToken: string; accessToken: string; nonce: string },
    options: {
        database?: Sql;
        verify?: typeof verifyGoogleIdToken;
        projectURL?: string;
    } = {},
): Promise<{ linked: boolean }> {
    const claims = await (options.verify ?? verifyGoogleIdToken)(
        input.idToken,
        input.nonce,
        { projectURL: options.projectURL },
    );
    if (!input.accessToken) {
        throw new ApiError(401, ERROR_CODES.unauthorized, "Invalid Google token");
    }
    const database = options.database ?? createDatabaseClient();
    const email = emailFromGoogleClaims(claims);
    return database.begin("read write", async (sql) => {
        const keeperId = chooseAccountToKeep(await loadCandidates(email, sql));
        const googleOwnerId = await googleIdentityOwner(claims.sub, sql);
        if (!keeperId) {
            return { linked: false };
        }
        if (googleOwnerId === keeperId) {
            return { linked: true };
        }
        if (googleOwnerId && googleOwnerId !== keeperId) {
            const disposable = await readDisposableState(googleOwnerId, sql);
            if (!isDisposableGoogleAccount(disposable)) {
                return { linked: false };
            }
            await sql`delete from auth.sessions where user_id = ${googleOwnerId}`;
            await sql`delete from auth.refresh_tokens where user_id = ${googleOwnerId}`;
            await sql`delete from auth.identities where user_id = ${googleOwnerId}`;
            await sql`delete from auth.users where id = ${googleOwnerId}`;
        }
        await attachGoogleIdentity(keeperId, claims, sql);
        return { linked: true };
    });
}

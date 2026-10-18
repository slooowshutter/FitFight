import { ApiError } from "@/lib/http";
import {
    appReleaseManifestSchema,
    appReleaseProjectSchema,
    prodAppReleasePolicySchema,
    stagingAppReleasePolicySchema,
    appStoreLookupSchema,
    type AppReleasePolicy,
    type InstallableRelease,
} from "@/lib/types/releases/app-release";

const STAGING_PROJECT = "https://zstzbfocunthczzubggz.supabase.co";
const POLICY_TTL_MS = 60_000;

let cachedPolicy: {
    project: string;
    policy: AppReleasePolicy;
    expiresAtMs: number;
} | null = null;

/** Successful policies are reused for a minute per project; failures are never cached. */
export async function appReleasePolicy(): Promise<AppReleasePolicy> {
    const project = appReleaseProjectSchema.safeParse(
        process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, ""),
    );
    if (!project.success) {
        throw new ApiError(
            503,
            "config",
            "App release environment is not configured",
        );
    }
    if (
        cachedPolicy &&
        cachedPolicy.project === project.data &&
        Date.now() < cachedPolicy.expiresAtMs
    ) {
        return cachedPolicy.policy;
    }

    let payload: unknown;
    try {
        const response = await fetch(
            `https://raw.githubusercontent.com/slooowshutter/FitFight/testflight-latest/releases.json?check=${Date.now()}`,
            { cache: "no-store", signal: AbortSignal.timeout(8_000) },
        );
        if (!response.ok) {
            throw new Error("Release manifest is unavailable");
        }
        payload = await response.json();
    } catch {
        throw new ApiError(
            503,
            "release_unavailable",
            "Could not check the latest app release",
        );
    }

    const channel = project.data === STAGING_PROJECT ? "staging" : "prod";
    const parsed = appReleaseManifestSchema.safeParse(payload);
    let policy: AppReleasePolicy;
    if (parsed.success) {
        // Updates are optional on every channel. Released apps still decode the flag.
        policy = { ...parsed.data[channel], enforced: false };
    } else {
        const selected =
            payload &&
            typeof payload === "object" &&
            !Array.isArray(payload) &&
            channel in payload
                ? Reflect.get(payload, channel)
                : undefined;
        const salvaged = (
            channel === "staging"
                ? stagingAppReleasePolicySchema
                : prodAppReleasePolicySchema
        ).safeParse(selected);
        if (!salvaged.success) {
            throw new ApiError(
                503,
                "release_unavailable",
                "Could not read the latest app release",
            );
        }
        policy = { ...salvaged.data, enforced: false };
    }
    cachedPolicy = {
        project: project.data,
        policy,
        expiresAtMs: Date.now() + POLICY_TTL_MS,
    };
    return policy;
}

export function resetAppReleasePolicyCacheForTests(): void {
    cachedPolicy = null;
    cachedAppStoreVersion = null;
}

const APP_STORE_ID = "6804230516";
const APP_STORE_TTL_MS = 5 * 60_000;
let cachedAppStoreVersion: { version: string; expiresAtMs: number } | null = null;

/**
 * The newest build this backend's people can install. Production asks Apple's public App Store
 * lookup, which changes once the App Store offers the update; no key needed, reused for 5 minutes.
 * Staging (TestFlight) has no public lookup and uses `releases.json`, which a GitHub job rewrites.
 */
export async function latestInstallableRelease(): Promise<InstallableRelease | null> {
    if (process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, "") === STAGING_PROJECT) {
        const { latest } = await appReleasePolicy();
        return latest && { version: latest.version, updateUrl: latest.update_url };
    }
    if (!cachedAppStoreVersion || Date.now() >= cachedAppStoreVersion.expiresAtMs) {
        const response = await fetch(`https://itunes.apple.com/lookup?id=${APP_STORE_ID}&t=${Date.now()}`, {
            cache: "no-store",
            signal: AbortSignal.timeout(5_000),
        });
        if (!response.ok) throw new Error("App Store lookup is unavailable");
        const lookup = appStoreLookupSchema.parse(await response.json());
        cachedAppStoreVersion = { version: lookup.results[0].version, expiresAtMs: Date.now() + APP_STORE_TTL_MS };
    }
    return { version: cachedAppStoreVersion.version, updateUrl: `https://apps.apple.com/app/id${APP_STORE_ID}` };
}

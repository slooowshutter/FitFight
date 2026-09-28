import { ApiError } from "@/lib/http";
import {
    appReleaseManifestSchema,
    appReleaseProjectSchema,
    prodAppReleasePolicySchema,
    stagingAppReleasePolicySchema,
    type AppReleasePolicy,
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
}

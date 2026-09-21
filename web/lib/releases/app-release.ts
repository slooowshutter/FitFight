import { ApiError } from "@/lib/http";
import {
    appReleaseManifestSchema,
    appReleaseProjectSchema,
    prodAppReleasePolicySchema,
    stagingAppReleasePolicySchema,
    testFlightAppStorePromptSchema,
    type AppReleasePolicy,
} from "@/lib/types/releases/app-release";

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

    const channel =
        project.data === "https://zstzbfocunthczzubggz.supabase.co"
            ? "staging"
            : "prod";
    const parsed = appReleaseManifestSchema.safeParse(payload);
    if (parsed.success) {
        if (channel === "staging") {
            const prompt = testFlightAppStorePromptSchema.safeParse(
                process.env.FITFIGHT_TESTFLIGHT_APP_STORE_PROMPT,
            );
            if (!prompt.success) {
                throw new ApiError(
                    503,
                    "config",
                    "App Store prompt setting is invalid",
                );
            }
            // Existing TestFlight binaries already accept an App Store URL in this contract.
            return {
                ...parsed.data.staging,
                latest:
                    prompt.data === "true" && parsed.data.prod.latest
                        ? parsed.data.prod.latest
                        : parsed.data.staging.latest,
                enforced: false,
            };
        }
        return parsed.data.prod;
    }
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
    return channel === "staging"
        ? { ...salvaged.data, enforced: false }
        : salvaged.data;
}

export async function requireLatestAppRelease(request: Request): Promise<void> {
    let policy: AppReleasePolicy;
    try {
        policy = await appReleasePolicy();
    } catch (error) {
        if (error instanceof ApiError && error.status === 503) {
            return;
        }
        throw error;
    }
    if (!policy.enforced) return;
    const version = request.headers.get("x-fitfight-version");
    const build = request.headers.get("x-fitfight-build");
    if (
        ![policy.latest, policy.review, policy.internal].some(
            (release) =>
                release &&
                version === release.version &&
                build === String(release.build),
        )
    ) {
        throw new ApiError(
            426,
            "update_required",
            "Update FitFight to continue",
        );
    }
}

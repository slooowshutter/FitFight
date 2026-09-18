import { appReleaseProjectSchema } from "@/lib/types/releases/app-release";

/** Keeps website downloads on the same channel as the configured backend. */
export function appDownload() {
    const project = appReleaseProjectSchema.parse(
        process.env.NEXT_PUBLIC_SUPABASE_URL?.replace(/\/$/, ""),
    );
    const isStaging = project === "https://zstzbfocunthczzubggz.supabase.co";

    return {
        isStaging,
        url: isStaging
            ? "https://testflight.apple.com/join/wcZKdwVZ"
            : "https://apps.apple.com/app/id6804230516",
    };
}

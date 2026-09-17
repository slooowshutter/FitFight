import {
    fitFightAdminEmailValues,
    fitFightAdminHandleValues,
    type FitFightAdminViewer,
} from "@/lib/types/admin/fitfight-admin";

function listedValues(
    defaults: readonly string[],
    extra: string | undefined,
): Set<string> {
    const values = [...defaults];
    if (extra) {
        for (const part of extra.split(",")) {
            const item = part.trim().toLowerCase();
            if (item) values.push(item);
        }
    }
    return new Set(values.map((value) => value.toLowerCase()));
}

export function isFitFightAdmin(viewer: FitFightAdminViewer): boolean {
    const handles = listedValues(
        fitFightAdminHandleValues,
        process.env.FITFIGHT_ADMIN_HANDLES,
    );
    if (handles.has(viewer.handle.trim().toLowerCase())) {
        return true;
    }
    const emails = listedValues(
        fitFightAdminEmailValues,
        process.env.FITFIGHT_ADMIN_EMAILS,
    );
    return viewer.emails.some((email) =>
        emails.has(email.trim().toLowerCase()),
    );
}

import { z } from "zod";
import {
    ApiError,
    ERROR_CODES,
    apiRoute,
    corsPreflight,
    json,
} from "@/lib/http";
import { readEnvironment } from "@/lib/supabase/queries/environment-supabase-query";
import type { EnvironmentResponse } from "@/lib/types/environment/environment";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

/** Public, so the app learns beta from the database instead of its own build settings. */
export const GET = apiRoute(async () => {
    const projectURL = z
        .string()
        .url()
        .safeParse(process.env.NEXT_PUBLIC_SUPABASE_URL);
    if (!projectURL.success) {
        throw new ApiError(
            500,
            ERROR_CODES.config,
            "Supabase project is not configured",
        );
    }
    const environment = await readEnvironment(
        new URL(projectURL.data).hostname.split(".")[0],
    );
    return json({ environment } satisfies EnvironmentResponse);
});

export const OPTIONS = corsPreflight;

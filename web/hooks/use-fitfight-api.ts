"use client";

import { useEffect, useState } from "react";
import { z } from "zod";
import { apiBase, browserSupabase } from "@/lib/supabase/browser-client";
import { apiErrorResponseSchema, type ErrorCode } from "@/lib/types/http/error";

/** Calls the same `/api/v1` the iPhone app uses, as the signed-in person, and parses the answer with its schema. */
export async function fitfightApi<Schema extends z.ZodTypeAny>(
    path: string,
    schema: Schema,
    options: {
        method?: "GET" | "POST" | "PATCH" | "PUT" | "DELETE";
        body?: unknown;
        idempotent?: boolean;
    } = {},
): Promise<z.output<Schema>> {
    const { data } = await browserSupabase.auth.getSession();
    const headers = new Headers({
        authorization: `Bearer ${data.session?.access_token ?? ""}`,
    });
    if (options.body !== undefined)
        headers.set("content-type", "application/json");
    if (options.idempotent) headers.set("idempotency-key", crypto.randomUUID());
    const response = await fetch(`${apiBase}/${path}`, {
        method: options.method ?? (options.body === undefined ? "GET" : "POST"),
        headers,
        body:
            options.body === undefined
                ? undefined
                : JSON.stringify(options.body),
    });
    const body: unknown = await response.json().catch(() => null);
    if (!response.ok) {
        const failure = apiErrorResponseSchema.safeParse(body);
        throw new FitFightApiError(
            response.status,
            failure.success
                ? failure.data.error
                : `Request failed (${response.status})`,
            failure.success ? failure.data.code : undefined,
        );
    }
    return schema.parse(body);
}

export class FitFightApiError extends Error {
    constructor(
        readonly status: number,
        message: string,
        readonly code?: ErrorCode,
    ) {
        super(message);
    }
}

/**
 * Loads one API answer for a screen. `body` makes it a POST, like the Fights snapshot. Pass `null` to wait. A new path
 * or body never shows the previous request's answer; `reload` keeps it on screen while refetching.
 */
export function useFitFightApi<Schema extends z.ZodTypeAny>(
    path: string | null,
    schema: Schema,
    body?: unknown,
) {
    const bodyKey = JSON.stringify(body);
    const key = path === null ? null : `${path}|${bodyKey}`;
    const [state, setState] = useState<{
        key: string | null;
        data?: z.output<Schema>;
        error?: FitFightApiError | Error;
    }>({ key: null });
    const [version, setVersion] = useState(0);

    useEffect(() => {
        if (!path) return;
        let cancelled = false;
        fitfightApi(path, schema, {
            body: bodyKey === undefined ? undefined : JSON.parse(bodyKey),
        }).then(
            (data) => !cancelled && setState({ key, data }),
            (error: Error) =>
                !cancelled &&
                setState((previous) => ({
                    key,
                    data: previous.key === key ? previous.data : undefined,
                    error,
                })),
        );
        return () => {
            cancelled = true;
        };
        // NOTE: schema must be a module constant at every call site; bodyKey stands in for body.
    }, [path, bodyKey, key, version]);

    const current = key !== null && state.key === key;
    return {
        data: current ? state.data : undefined,
        error: current ? state.error : undefined,
        reload: () => setVersion((value) => value + 1),
    };
}

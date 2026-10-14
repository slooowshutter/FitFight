import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import type { Sql } from "postgres";
import { ModuleKind, transpileModule } from "typescript";
import { z } from "zod";
import { DELETE } from "@/app/api/v1/device-installations/route";
import { POST as RELEASE } from "@/app/api/v1/device-installations/release/route";
import {
    registerDeviceInstallationRequestSchema,
    revokeDeviceInstallationRequestSchema,
} from "@/lib/types/notifications/device-installation";
import {
    releaseDeviceInstallationForToken,
    revokeDeviceInstallationForToken,
} from "./device-installations-supabase-query";

const require = createRequire(import.meta.url);

test("device revocation authenticates before handling a token", async () => {
    const response = await DELETE(
        new Request(
            "https://staging.fitfight.app/api/v1/device-installations",
            {
                method: "DELETE",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify({ token: "ab".repeat(32) }),
            },
        ),
        { params: Promise.resolve({}) },
    );

    assert.equal(response.status, 401);
});

test("device revocation accepts a token without changing installed clients' registration body", () => {
    const token = "ab".repeat(32);
    assert.deepEqual(revokeDeviceInstallationRequestSchema.parse({ token }), {
        token,
    });
    assert.equal(
        revokeDeviceInstallationRequestSchema.safeParse({
            token,
            user_id: "someone-else",
        }).success,
        false,
    );
    assert.equal(
        revokeDeviceInstallationRequestSchema.safeParse({ token: "" }).success,
        false,
    );
    assert.equal(
        revokeDeviceInstallationRequestSchema.safeParse({ token: "not-hex" })
            .success,
        false,
    );
    const registration = {
        token,
        apns_environment: "production",
        locale: "en",
        permission_status: "authorized",
    };
    assert.deepEqual(
        registerDeviceInstallationRequestSchema.parse(registration),
        registration,
    );
});

test("signout revokes only the authenticated user's matching device and keeps the raw token out of SQL", async () => {
    const token = "ab".repeat(32);
    let statement = "";
    let parameters: unknown[] = [];
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        statement = strings.join("?").replace(/\s+/g, " ").trim();
        parameters = values;
        return Promise.resolve([]);
    }) as unknown as Sql;

    await revokeDeviceInstallationForToken(
        "signed-in-user",
        { token },
        database,
    );

    assert.match(
        statement,
        /where user_id = \? and token_fingerprint = \? and revoked_at is null$/,
    );
    assert.match(
        statement,
        /set revoked_at = now\(\), revoke_reason = 'signed_out'/,
    );
    assert.deepEqual(parameters, [
        "signed-in-user",
        createHash("sha256").update(token, "utf8").digest("hex"),
    ]);
    assert.equal(parameters.includes(token), false);
});

test("a release from the other environment stops sending to the phone, whichever account holds it", async () => {
    const token = "cd".repeat(32);
    let statement = "";
    let parameters: unknown[] = [];
    const database = ((strings: TemplateStringsArray, ...values: unknown[]) => {
        statement = strings.join("?").replace(/\s+/g, " ").trim();
        parameters = values;
        return Promise.resolve([]);
    }) as unknown as Sql;

    await releaseDeviceInstallationForToken({ token }, database);

    assert.match(
        statement,
        /set revoked_at = now\(\), revoke_reason = 'other_environment' where token_fingerprint = \? and revoked_at is null$/,
    );
    assert.deepEqual(parameters, [
        createHash("sha256").update(token, "utf8").digest("hex"),
    ]);
});

test("the release endpoint needs no session and accepts only a token", async () => {
    for (const body of [
        { token: "not-hex" },
        { token: "cd".repeat(32), user_id: "someone-else" },
    ]) {
        const response = await RELEASE(
            new Request(
                "https://fitfight.app/api/v1/device-installations/release",
                {
                    method: "POST",
                    headers: { "Content-Type": "application/json" },
                    body: JSON.stringify(body),
                },
            ),
            { params: Promise.resolve({}) },
        );
        assert.equal(response.status, 400);
    }
});

for (const entry of [
    {
        project: "https://zstzbfocunthczzubggz.supabase.co",
        other: "https://fitfight.app",
    },
    {
        project: "https://pvqntpteehdvhqyctwum.supabase.co/",
        other: "https://staging.fitfight.app",
    },
    { project: "http://127.0.0.1:54321", other: null },
]) {
    test(`registering with ${entry.project} releases the phone on ${entry.other ?? "no other environment"} after responding`, async () => {
        const token = "ef".repeat(32);
        const callbacks: Array<() => Promise<void>> = [];
        const releases: Array<{ url: string; body: unknown }> = [];
        const exports: Record<string, unknown> = {};
        // Execute the production handler with only auth, persistence, and the network replaced.
        const { outputText } = transpileModule(
            readFileSync(
                new URL(
                    "../../../app/api/v1/device-installations/route.ts",
                    import.meta.url,
                ),
                "utf8",
            ),
            { compilerOptions: { module: ModuleKind.CommonJS } },
        );
        runInNewContext(outputText, {
            exports,
            process: { env: { NEXT_PUBLIC_SUPABASE_URL: entry.project } },
            fetch: async (url: string, init: RequestInit) => {
                releases.push({ url, body: JSON.parse(String(init.body)) });
                return Response.json({ released: true });
            },
            require(specifier: string) {
                if (specifier === "next/server") {
                    return {
                        after: (callback: () => Promise<void>) =>
                            callbacks.push(callback),
                    };
                }
                if (specifier.endsWith("/auth-supabase-query")) {
                    return { verifyUser: async () => ({ userId: "user" }) };
                }
                if (specifier.endsWith("/device-installations-supabase-query")) {
                    return {
                        registerDeviceInstallation: async () => ({
                            registered: true,
                        }),
                    };
                }
                return require(specifier);
            },
        });

        const response = z.instanceof(Response).parse(
            await z.function().parse(exports.POST)(
                new Request(
                    "https://staging.fitfight.app/api/v1/device-installations",
                    {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify({
                            token,
                            apns_environment: "production",
                            locale: "fr",
                            permission_status: "authorized",
                        }),
                    },
                ),
                { params: Promise.resolve({}) },
            ),
        );

        assert.equal(response.status, 200);
        assert.deepEqual(await response.json(), { registered: true });
        assert.equal(
            releases.length,
            0,
            "Registration must not wait for the other environment",
        );
        await Promise.all(callbacks.map((callback) => callback()));
        assert.deepEqual(
            releases,
            entry.other
                ? [
                      {
                          url: `${entry.other}/api/v1/device-installations/release`,
                          body: { token },
                      },
                  ]
                : [],
        );
    });
}

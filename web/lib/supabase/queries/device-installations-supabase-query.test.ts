import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import type { Sql } from "postgres";
import { DELETE } from "@/app/api/v1/device-installations/route";
import {
    registerDeviceInstallationRequestSchema,
    revokeDeviceInstallationRequestSchema,
} from "@/lib/types/notifications/device-installation";
import { revokeDeviceInstallationForToken } from "./device-installations-supabase-query";

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

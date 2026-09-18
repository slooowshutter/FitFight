import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { GET, PATCH } from "@/app/api/v1/me/preferences/route";
import {
    accountPreferencesSchema,
    updateAccountPreferencesRequestSchema,
} from "@/lib/types/profiles/account-preferences";

test("account preferences share their response fixture with the native decoder", () => {
    const fixture = JSON.parse(readFileSync(
        new URL("../../../../contracts/fixtures/account-preferences.json", import.meta.url),
        "utf8",
    ));
    assert.deepEqual(accountPreferencesSchema.parse(fixture), {
        language: "fr",
        appearance: "dark",
    });
});

test("preference patches accept independent settings and reject identities and invalid values", () => {
    for (const language of ["system", "en", "fr"]) {
        assert.deepEqual(updateAccountPreferencesRequestSchema.parse({ language }), { language });
    }
    for (const appearance of ["system", "light", "dark"]) {
        assert.deepEqual(updateAccountPreferencesRequestSchema.parse({ appearance }), { appearance });
    }
    for (const input of [
        {}, null, [], { language: "de" }, { language: null }, { language: 1 },
        { appearance: "night" }, { appearance: false }, { appearance: null },
        { language: "fr", user_id: "11111111-1111-4111-8111-111111111111" },
        { language: "fr", beta: true },
    ]) {
        assert.equal(updateAccountPreferencesRequestSchema.safeParse(input).success, false);
    }
});

test("reading and changing preferences require authentication", async () => {
    for (const [method, handler] of [["GET", GET], ["PATCH", PATCH]] as const) {
        const response = await handler(new Request("https://fitfight.app/api/v1/me/preferences", { method }), {
            params: Promise.resolve({}),
        });
        assert.equal(response.status, 401);
    }
});

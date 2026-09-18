import assert from "node:assert/strict";
import { test } from "node:test";
import { GET } from "@/app/api/v1/me/companions/route";
import { savedCompanionPromptsSchema } from "@/lib/types/companions/companion";

test("saved companion descriptions require authentication", async () => {
    const response = await GET(
        new Request("https://staging.fitfight.app/api/v1/me/companions"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 401);
    assert.equal(response.headers.get("cache-control"), "no-store");
});

test("saved description responses reject invalid database values", () => {
    for (const input of [null, [null], [" "], ["a".repeat(1001)]]) {
        assert.equal(savedCompanionPromptsSchema.safeParse(input).success, false);
    }
    assert.deepEqual(savedCompanionPromptsSchema.parse([]), []);
    assert.deepEqual(savedCompanionPromptsSchema.parse(["A blue otter"]), ["A blue otter"]);
});

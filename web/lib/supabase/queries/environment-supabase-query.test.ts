import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { environmentResponseSchema } from "@/lib/types/environment/environment";

test("the environment response matches its contract fixture and rejects unknown names", () => {
    const fixture = JSON.parse(
        readFileSync(
            new URL(
                "../../../../contracts/fixtures/environment.json",
                import.meta.url,
            ),
            "utf8",
        ),
    );
    assert.deepEqual(environmentResponseSchema.parse(fixture), {
        environment: "beta",
    });
    for (const environment of ["staging", "develop", "", null]) {
        assert.equal(
            environmentResponseSchema.safeParse({ environment }).success,
            false,
        );
    }
});

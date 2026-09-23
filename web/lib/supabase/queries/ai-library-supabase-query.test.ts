import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { GET } from "@/app/api/v1/ai/library/route";
import { aiLibraryEntrySchema } from "@/lib/types/ai/library";
import { updateProfileRequestSchema } from "@/lib/types/profiles/profile";

test("library access requires authentication and companion selection accepts only a saved result reference", async () => {
    const response = await GET(
        new Request("https://example.com/api/v1/ai/library"),
        { params: Promise.resolve({}) },
    );
    assert.equal(response.status, 401);
    const companion_image = {
        request_id: "11111111-1111-4111-8111-111111111111",
        stage: "image_url",
    };
    assert.deepEqual(updateProfileRequestSchema.parse({ companion_image }), {
        companion_image,
    });
    for (const input of [
        {
            companion_image: {
                ...companion_image,
                url: "https://example.com/foreign.png",
            },
        },
        { companion_image: { ...companion_image, stage: "unknown" } },
        { companion_image, companion_id: "fox" },
    ])
        assert.equal(
            updateProfileRequestSchema.safeParse(input).success,
            false,
        );
    const entries = aiLibraryEntrySchema
        .array()
        .parse(
            JSON.parse(
                readFileSync("../contracts/fixtures/ai-library.json", "utf8"),
            ),
        );
    assert.deepEqual(
        entries.map((entry) => entry.images.length),
        [1, 5, 1],
    );
});

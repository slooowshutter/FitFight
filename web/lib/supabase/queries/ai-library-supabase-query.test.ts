import assert from "node:assert/strict";
import { test } from "node:test";
import { readFileSync } from "node:fs";
import { GET } from "@/app/api/v1/ai/library/route";
import { POST } from "@/app/api/v1/ai/runs/[requestID]/images/route";
import {
    aiLibraryEntrySchema,
    saveAiImagesSchema,
} from "@/lib/types/ai/library";

const requestId = "11111111-1111-4111-8111-111111111111";
const mediaId = "22222222-2222-4222-8222-222222222222";

test("library and save routes reject unauthenticated callers before database access", async () => {
    const read = await GET(
        new Request("https://example.com/api/v1/ai/library"),
        { params: Promise.resolve({}) },
    );
    assert.equal(read.status, 401);
    const write = await POST(
        new Request(`https://example.com/api/v1/ai/runs/${requestId}/images`, {
            method: "POST",
            body: JSON.stringify({
                description: "Fox",
                images: [{ stage: "image_url", media_id: mediaId }],
            }),
        }),
        { params: Promise.resolve({ requestID: requestId }) },
    );
    assert.equal(write.status, 401);
});

test("library save accepts owned-media references, never URLs or duplicate stages", () => {
    const valid = {
        description: "Fox",
        images: [{ stage: "image_url", media_id: mediaId }],
    };
    assert.equal(saveAiImagesSchema.parse(valid).images.length, 1);
    for (const input of [
        { ...valid, images: [...valid.images, ...valid.images] },
        {
            ...valid,
            images: [
                { stage: "image_url", url: "https://example.com/image.png" },
            ],
        },
        { ...valid, images: [{ stage: "unknown", media_id: mediaId }] },
        { ...valid, user_id: requestId },
        { ...valid, description: " " },
    ])
        assert.equal(saveAiImagesSchema.safeParse(input).success, false);
});

test("the shared library fixture carries durable media and all five named fitness images", () => {
    const library = aiLibraryEntrySchema
        .array()
        .parse(
            JSON.parse(
                readFileSync("../contracts/fixtures/ai-library.json", "utf8"),
            ),
        );
    assert.deepEqual(
        library.map((entry) => entry.workflow),
        ["avatar", "fitness", "group_photo"],
    );
    assert.equal(library[1].images.length, 5);
    assert.ok(
        library.every((entry) =>
            entry.images.every(
                (image) => image.media.content_type === "image/png",
            ),
        ),
    );
});

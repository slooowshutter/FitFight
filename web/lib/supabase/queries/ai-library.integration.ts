import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test } from "node:test";
import postgres from "postgres";
import { z } from "zod";
import { ApiError } from "@/lib/http";
import { readAiLibrary, saveAiImages } from "./ai-library-supabase-query";
import { adjustAiCredits } from "./ai-credits-supabase-query";
import { reserveAiRequest } from "./ai-requests-supabase-query";
import type { AiWorkflow } from "@/lib/types/ai/workflow";
import { aiImageStageValues, type SaveAiImages } from "@/lib/types/ai/library";

const databaseURL = process.env.DATABASE_URL;
if (
    process.env.CI !== "true" ||
    !databaseURL ||
    !["localhost", "127.0.0.1"].includes(new URL(databaseURL).hostname)
) {
    throw new Error(
        "These tests require the disposable local database in cloud CI",
    );
}
const database = postgres(databaseURL, { max: 5 });
after(() => database.end());
process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY = "fixture-key";

test("generated account images retain ownership, complete sets, and reusable portraits", async (t) => {
    const owner = randomUUID();
    const other = randomUUID();
    t.after(async () => {
        await database`delete from auth.users where id in (${owner}, ${other})`;
    });
    await database`insert into auth.users (id) values (${owner}), (${other})`;
    await database`update private.ai_provider_budget set requests = 0, starts = 0, remaining = null,
        reset_at = null, blocked_until = null, window_started_at = clock_timestamp(),
        starts_day = (clock_timestamp() at time zone 'UTC')::date where provider = 'blend'`;
    t.mock.method(
        globalThis,
        "fetch",
        async (...[, init]: Parameters<typeof fetch>) => {
            const body = z
                .object({ paths: z.array(z.string()) })
                .parse(JSON.parse(String(init?.body)));
            return new Response(
                JSON.stringify(
                    body.paths.map((path) => ({
                        path,
                        error: null,
                        signedURL: `/object/sign/user-media/${path}?token=fixture`,
                    })),
                ),
                { status: 200 },
            );
        },
    );

    async function completed(workflow: AiWorkflow) {
        const id = randomUUID();
        const result =
            workflow === "fitness"
                ? Object.fromEntries(
                      aiImageStageValues
                          .filter((stage) => stage !== "image_url")
                          .map((stage) => [
                              stage,
                              `https://supabase.tryblend.ai/${stage}.png`,
                          ]),
                  )
                : { image_url: "https://supabase.tryblend.ai/avatar.png" };
        await database`insert into private.ai_requests (id, user_id, workflow, idempotency_key, request_hash,
            workflow_version, run_handle, status, result)
            values (${id}, ${owner}, ${workflow}, ${randomUUID()}, ${"a".repeat(64)},
                ${database.json({ workflowId: "fixture", versionId: "fixture" })},
                ${database.json({ workflowId: "fixture", versionId: "fixture", runId: randomUUID() })},
                'completed', ${database.json(result)})`;
        return id;
    }
    async function image(
        userId: string,
        status: "ready" | "pending" = "ready",
    ) {
        const id = randomUUID();
        await database`insert into public.media_objects (id, owner_id, kind, purpose, status, object_path,
            original_filename, content_type, byte_size, width, height, sha256)
            values (${id}, ${userId}, 'photo', 'profile', ${status}::public.media_status, ${`${userId}/profile/${id}`},
                'companion.png', 'image/png', 1000, 1024, 1024, ${"a".repeat(64)})`;
        return id;
    }

    const avatar = await completed("avatar");
    const avatarMedia = await image(owner);
    const foreignMedia = await image(other);
    const pendingMedia = await image(owner, "pending");
    for (const mediaId of [foreignMedia, pendingMedia]) {
        await assert.rejects(
            saveAiImages(
                owner,
                avatar,
                {
                    description: "Fox",
                    images: [{ stage: "image_url", media_id: mediaId }],
                },
                database,
            ),
            (error: unknown) =>
                error instanceof ApiError && error.status === 404,
        );
    }
    await assert.rejects(
        saveAiImages(
            other,
            avatar,
            {
                description: "Fox",
                images: [{ stage: "image_url", media_id: foreignMedia }],
            },
            database,
        ),
        (error: unknown) => error instanceof ApiError && error.status === 404,
    );
    const input: SaveAiImages = {
        description: "Fox",
        images: [{ stage: "image_url", media_id: avatarMedia }],
    };
    await Promise.all([
        saveAiImages(owner, avatar, input, database),
        saveAiImages(owner, avatar, input, database),
    ]);
    assert.equal(
        (
            await database`select * from private.ai_library_images where request_id = ${avatar}`
        ).length,
        1,
    );
    assert.deepEqual(await readAiLibrary(other, database), []);
    const library = await readAiLibrary(owner, database);
    assert.equal(library[0].images[0].media.id, avatarMedia);
    assert.ok(
        library[0].images[0].media.url?.startsWith(
            "https://example.supabase.co/storage/v1/object/sign/",
        ),
    );

    const fitness = await completed("fitness");
    const fitnessImages: SaveAiImages["images"] = [];
    for (const stage of [
        "resting",
        "soft",
        "average",
        "fit",
        "strong",
    ] as const) {
        fitnessImages.push({ stage, media_id: await image(owner) });
    }
    await assert.rejects(
        saveAiImages(
            owner,
            fitness,
            { description: "Fox", images: fitnessImages.slice(0, 4) },
            database,
        ),
        (error: unknown) => error instanceof ApiError && error.status === 400,
    );
    assert.equal(
        (
            await database`select * from private.ai_library_images where request_id = ${fitness}`
        ).length,
        0,
    );
    await saveAiImages(
        owner,
        fitness,
        { description: "Fox", images: fitnessImages },
        database,
    );
    assert.equal(
        (await readAiLibrary(owner, database)).find(
            (entry) => entry.request_id === fitness,
        )?.images.length,
        5,
    );

    // Ordinary request pruning must not remove the library or prevent future paid derivatives.
    await database`update private.ai_requests set updated_at = clock_timestamp() - interval '8 days' where id = ${avatar}`;
    await adjustAiCredits(
        owner,
        {
            kind: "grant",
            user_id: owner,
            operation_key: randomUUID(),
            quantity: 3,
            reason: "test_library",
        },
        database,
    );
    const derived = await reserveAiRequest(
        owner,
        {
            workflow: "fitness",
            resourceId: null,
            idempotencyKey: randomUUID(),
            requestHash: "b".repeat(64),
            version: { workflowId: "fitness", versionId: "fixture" },
            creditPrice: 1,
            sourceRequestIds: [avatar],
        },
        {
            globalDailyStarts: 100,
            globalConcurrentRuns: 10,
            providerRequestsPerMinute: 100,
        },
        database,
    );
    assert.equal(derived.shouldStart, true);
    if (derived.shouldStart)
        assert.ok(derived.portraits[0].includes(avatarMedia));
    assert.equal(
        (
            await database`select id from private.ai_requests where id = ${avatar}`
        ).length,
        0,
    );
    await saveAiImages(owner, avatar, input, database);
    assert.equal((await readAiLibrary(owner, database)).length, 2);

    await database`delete from auth.users where id = ${owner}`;
    assert.equal(
        (
            await database`select * from private.ai_library_images where user_id = ${owner}`
        ).length,
        0,
    );
    assert.equal(
        (
            await database`select * from public.media_objects where owner_id = ${owner}`
        ).length,
        0,
    );
});

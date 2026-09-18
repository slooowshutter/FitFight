import assert from "node:assert/strict";
import test from "node:test";
import { readFileSync } from "node:fs";
import { GET as activity } from "@/app/api/v1/feed/activity/route";
import { GET as post } from "@/app/api/v1/posts/[postID]/route";
import { feedActivityResponseSchema, listFeedActivityQuerySchema } from "@/lib/types/feed/feed-activity";

test("activity shares its response fixture with the native decoder", () => {
    const fixture = JSON.parse(readFileSync(new URL("../../../../contracts/fixtures/feed-activity-response.json", import.meta.url), "utf8"));
    const result = feedActivityResponseSchema.parse(fixture);
    assert.equal(result.events[0].occurred_at, "2026-09-16T12:13:14.123456Z");
    assert.equal(result.events[1].occurred_at, null);
});

test("activity and post destinations require authentication", async () => {
    const response = await activity(new Request("https://fitfight.app/api/v1/feed/activity"), { params: Promise.resolve({}) });
    assert.equal(response.status, 401);
    const detail = await post(new Request("https://fitfight.app/api/v1/posts/00000000-0000-4000-8000-000000000000"), {
        params: Promise.resolve({ postID: "00000000-0000-4000-8000-000000000000" }),
    });
    assert.equal(detail.status, 401);
});

test("activity cursors preserve exact timestamps and distinguish unknown historical times", () => {
    const id = "membership:00000000-0000-4000-8000-000000000000";
    const at = "2026-09-16T12:13:14.123456Z";
    assert.deepEqual(listFeedActivityQuerySchema.parse({ cursor: `${at}|${id}` }).cursor, { at, id });
    assert.deepEqual(listFeedActivityQuerySchema.parse({ cursor: `unknown|${id}` }).cursor, { at: null, id });
    for (const cursor of ["", "garbage", `tomorrow|${id}`, `${at}|${id}|extra`, `${at}|not-an-event`]) {
        assert.equal(listFeedActivityQuerySchema.safeParse({ cursor }).success, false);
    }
    for (const limit of [0, 81, "invalid"]) {
        assert.equal(listFeedActivityQuerySchema.safeParse({ limit }).success, false);
    }
});

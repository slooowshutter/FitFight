import assert from "node:assert/strict";
import { test } from "node:test";
import { z } from "zod";
import { POST as createMedia } from "@/app/api/v1/media/route";
import { POST as commitMedia } from "@/app/api/v1/media/[mediaID]/commit/route";
import {
  createMediaUploadRequestSchema,
  mediaObjectSchema,
} from "@/lib/types/media/media";
import {
  mapMedia,
  removeStoragePaths,
  signedUrlsFromBatch,
} from "./media-supabase-query";

const mediaId = "55555555-5555-4555-8555-555555555555";

process.env.NEXT_PUBLIC_SUPABASE_URL = "https://example.supabase.co";
process.env.SUPABASE_SECRET_KEY = "test-secret-key";

test("media removal respects Storage's 1000-object limit without skipping paths", async (t) => {
  const paths = Array.from({ length: 2001 }, (_, index) => `user-id/fight_post/${index}`);
  const batches: string[][] = [];
  t.mock.method(globalThis, "fetch", async (...[, request]: Parameters<typeof fetch>) => {
    const { prefixes } = z.object({ prefixes: z.array(z.string()) }).parse(JSON.parse(String(request?.body)));
    batches.push(prefixes);
    return new Response(JSON.stringify(prefixes.length > 1000
      ? { message: "Too many prefixes", statusCode: "400" }
      : []), { status: prefixes.length > 1000 ? 400 : 200 });
  });

  await removeStoragePaths(paths);

  assert.deepEqual(batches.map((batch) => batch.length), [1000, 1000, 1]);
  assert.deepEqual(batches.flat(), paths);
});

test("media uploads accept only bounded photo metadata", () => {
  const parsed = createMediaUploadRequestSchema.parse({
    purpose: "fight_post",
    original_filename: "proof.jpg",
    content_type: "image/jpeg",
    byte_size: 120_000,
    width: 1200,
    height: 1600,
    sha256: "a".repeat(64),
  });
  assert.equal(parsed.purpose, "fight_post");
  assert.equal(parsed.kind, "photo");
  for (const input of [
    { purpose: "avatar", original_filename: "a.jpg", content_type: "image/jpeg", byte_size: 1, width: 1, height: 1, sha256: "a".repeat(64) },
    { purpose: "profile", original_filename: "../a.jpg", content_type: "image/jpeg", byte_size: 1, width: 1, height: 1, sha256: "a".repeat(64) },
    { purpose: "profile", original_filename: "a.jpg", content_type: "image/gif", byte_size: 1, width: 1, height: 1, sha256: "a".repeat(64) },
    { purpose: "profile", original_filename: "a.jpg", content_type: "image/jpeg", byte_size: 9_000_000, width: 1, height: 1, sha256: "a".repeat(64) },
    { purpose: "profile", original_filename: "a.jpg", content_type: "image/jpeg", byte_size: 1, width: 1, height: 1, sha256: "zz" },
  ]) {
    assert.equal(createMediaUploadRequestSchema.safeParse(input).success, false);
  }
});

test("media uploads accept short fight-post videos and reject invalid ones", () => {
  const parsed = createMediaUploadRequestSchema.parse({
    purpose: "fight_post",
    kind: "video",
    original_filename: "clip.mp4",
    content_type: "video/mp4",
    byte_size: 4_000_000,
    width: 1080,
    height: 1920,
    duration_ms: 12_000,
    sha256: "a".repeat(64),
  });
  assert.equal(parsed.kind, "video");
  assert.equal(parsed.duration_ms, 12_000);
  for (const input of [
    {
      purpose: "profile",
      kind: "video",
      original_filename: "clip.mp4",
      content_type: "video/mp4",
      byte_size: 4_000_000,
      width: 1080,
      height: 1920,
      duration_ms: 12_000,
      sha256: "a".repeat(64),
    },
    {
      purpose: "fight_post",
      kind: "video",
      original_filename: "clip.mp4",
      content_type: "image/jpeg",
      byte_size: 4_000_000,
      width: 1080,
      height: 1920,
      duration_ms: 12_000,
      sha256: "a".repeat(64),
    },
    {
      purpose: "fight_post",
      kind: "video",
      original_filename: "clip.mp4",
      content_type: "video/mp4",
      byte_size: 4_000_000,
      width: 1080,
      height: 1920,
      sha256: "a".repeat(64),
    },
    {
      purpose: "fight_post",
      kind: "video",
      original_filename: "clip.mp4",
      content_type: "video/mp4",
      byte_size: 52_428_801,
      width: 1080,
      height: 1920,
      duration_ms: 12_000,
      sha256: "a".repeat(64),
    },
  ]) {
    assert.equal(createMediaUploadRequestSchema.safeParse(input).success, false);
  }
});

test("media uploads accept request files and videos, and reject unsafe types", () => {
  const file = createMediaUploadRequestSchema.parse({
    purpose: "feedback",
    kind: "file",
    original_filename: "console.log",
    content_type: "text/plain",
    byte_size: 2048,
    width: 1,
    height: 1,
    sha256: "a".repeat(64),
  });
  assert.equal(file.kind, "file");
  assert.equal(file.purpose, "feedback");
  const video = createMediaUploadRequestSchema.parse({
    purpose: "feedback",
    kind: "video",
    original_filename: "repro.mov",
    content_type: "video/quicktime",
    byte_size: 4_000_000,
    width: 1080,
    height: 1920,
    duration_ms: 8_000,
    sha256: "a".repeat(64),
  });
  assert.equal(video.purpose, "feedback");
  for (const input of [
    {
      purpose: "fight_post",
      kind: "file",
      original_filename: "notes.txt",
      content_type: "text/plain",
      byte_size: 20,
      width: 1,
      height: 1,
      sha256: "a".repeat(64),
    },
    {
      purpose: "feedback",
      kind: "file",
      original_filename: "page.html",
      content_type: "text/html",
      byte_size: 20,
      width: 1,
      height: 1,
      sha256: "a".repeat(64),
    },
    {
      purpose: "feedback",
      kind: "file",
      original_filename: "clip.mp4",
      content_type: "text/plain",
      byte_size: 20,
      width: 1,
      height: 1,
      duration_ms: 1_000,
      sha256: "a".repeat(64),
    },
  ]) {
    assert.equal(createMediaUploadRequestSchema.safeParse(input).success, false);
  }
});

test("batch signed URLs keep one URL per object path and ignore failed rows", () => {
  const urls = signedUrlsFromBatch(
    ["a/photo", "b/photo", "c/photo"],
    [
      { path: "a/photo", signedUrl: "https://example.com/a?token=1", error: null },
      { path: null, signedUrl: "https://example.com/b?token=2", error: null },
      { path: "c/photo", signedUrl: null, error: "not_found" },
    ],
  );
  assert.equal(urls.get("a/photo"), "https://example.com/a?token=1");
  assert.equal(urls.get("b/photo"), "https://example.com/b?token=2");
  assert.equal(urls.get("c/photo"), null);
});

test("mapped media objects keep file identity and hide storage paths", () => {
  const media = mapMedia({
    id: mediaId,
    owner_id: "11111111-1111-4111-8111-111111111111",
    kind: "photo",
    purpose: "profile",
    status: "ready",
    object_path: "11111111-1111-4111-8111-111111111111/profile/" + mediaId,
    original_filename: "me.jpg",
    content_type: "image/jpeg",
    byte_size: "2048",
    width: 64,
    height: 64,
    duration_ms: null,
    sha256: "b".repeat(64),
    created_at: "2026-09-09T12:00:00.000Z",
  }, "https://example.com/photo.jpg");
  assert.deepEqual(mediaObjectSchema.parse(media), {
    id: mediaId,
    kind: "photo",
    purpose: "profile",
    status: "ready",
    original_filename: "me.jpg",
    content_type: "image/jpeg",
    byte_size: 2048,
    width: 64,
    height: 64,
    duration_ms: null,
    sha256: "b".repeat(64),
    url: "https://example.com/photo.jpg",
    created_at: "2026-09-09T12:00:00Z",
  });
});

test("media routes authenticate before creating or committing an upload", async () => {
  const created = await createMedia(new Request("https://staging.fitfight.app/api/v1/media", {
    method: "POST",
  }), { params: Promise.resolve({}) });
  assert.equal(created.status, 401);
  const committed = await commitMedia(new Request("https://staging.fitfight.app/api/v1/media/" + mediaId + "/commit", {
    method: "POST",
  }), { params: Promise.resolve({ mediaID: mediaId }) });
  assert.equal(committed.status, 401);
});

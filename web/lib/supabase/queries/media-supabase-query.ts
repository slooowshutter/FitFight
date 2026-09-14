import { createHash, randomUUID } from "node:crypto";
import type { Sql } from "postgres";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { createAdminClient } from "@/lib/supabase/admin";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
  mediaObjectSchema,
  type CreateMediaUploadRequest,
  type MediaObject,
  type MediaUploadResponse,
} from "@/lib/types/media/media";

const BUCKET = "user-media";
const SIGNED_READ_SECONDS = 21_600;
const SIGNED_REUSE_MS = (SIGNED_READ_SECONDS - 300) * 1000;
const SIGN_BATCH = 50;
const PENDING_LIMIT = 3;

type CachedSignedUrl = { url: string; expiresAtMs: number };

const signedUrlCache = new Map<string, CachedSignedUrl>();

export function signedUrlsFromBatch(
  paths: string[],
  rows: { path: string | null; signedUrl: string | null; error: string | null }[],
): Map<string, string | null> {
  const urls = new Map<string, string | null>();
  for (const path of paths) urls.set(path, null);
  for (const [index, row] of rows.entries()) {
    const path = row.path ?? paths[index];
    if (!path) continue;
    urls.set(path, row.error || !row.signedUrl ? null : row.signedUrl);
  }
  return urls;
}

export type MediaRow = {
  id: string;
  owner_id: string;
  kind: "photo" | "video";
  purpose: "profile" | "fight_post";
  status: "pending" | "ready" | "rejected";
  object_path: string;
  original_filename: string;
  content_type: MediaObject["content_type"];
  byte_size: string | number;
  width: number;
  height: number;
  duration_ms: number | null;
  sha256: string;
  created_at: Date | string;
};

function isoUtc(value: Date | string): string {
  return new Date(value).toISOString().replace(/\.\d{3}Z$/, "Z");
}

export function mapMedia(row: MediaRow, url: string | null): MediaObject {
  return mediaObjectSchema.parse({
    id: row.id,
    kind: row.kind,
    purpose: row.purpose,
    status: row.status,
    original_filename: row.original_filename,
    content_type: row.content_type,
    byte_size: Number(row.byte_size),
    width: row.width,
    height: row.height,
    duration_ms: row.duration_ms,
    sha256: row.sha256,
    url,
    created_at: isoUtc(row.created_at),
  });
}

export async function signMediaUrls(objectPaths: string[]): Promise<Map<string, string | null>> {
  const nowMs = Date.now();
  if (signedUrlCache.size > 2000) {
    for (const [path, entry] of signedUrlCache) {
      if (entry.expiresAtMs <= nowMs) signedUrlCache.delete(path);
    }
    if (signedUrlCache.size > 2000) signedUrlCache.clear();
  }

  const urls = new Map<string, string | null>();
  const missing: string[] = [];
  for (const path of objectPaths) {
    if (!path || urls.has(path)) continue;
    const cached = signedUrlCache.get(path);
    if (cached && cached.expiresAtMs > nowMs) {
      urls.set(path, cached.url);
    } else {
      missing.push(path);
      urls.set(path, null);
    }
  }
  if (missing.length === 0) return urls;

  const admin = createAdminClient();
  const expiresAtMs = nowMs + SIGNED_REUSE_MS;
  for (let index = 0; index < missing.length; index += SIGN_BATCH) {
    const slice = missing.slice(index, index + SIGN_BATCH);
    const { data, error } = await admin.storage.from(BUCKET).createSignedUrls(slice, SIGNED_READ_SECONDS);
    const rows = error || !data ? [] : data;
    for (const [path, url] of signedUrlsFromBatch(slice, rows)) {
      urls.set(path, url);
      if (url) signedUrlCache.set(path, { url, expiresAtMs });
    }
  }
  return urls;
}

export async function signMediaUrl(objectPath: string): Promise<string | null> {
  return (await signMediaUrls([objectPath])).get(objectPath) ?? null;
}

export async function createMediaUpload(
  userId: string,
  input: CreateMediaUploadRequest,
  database: Sql = createDatabaseClient(),
): Promise<MediaUploadResponse> {
  const [pending] = await database<{ n: number }[]>`
    select count(*)::int as n
    from public.media_objects
    where owner_id = ${userId}
      and status = 'pending'
      and created_at > now() - interval '2 hours'
  `;
  if ((pending?.n ?? 0) >= PENDING_LIMIT) {
    throw new ApiError(429, ERROR_CODES.rate_limited, "Finish or wait on your current photo uploads.");
  }

  const id = randomUUID();
  const objectPath = `${userId}/${input.purpose}/${id}`;
  const [row] = await database<MediaRow[]>`
    insert into public.media_objects (
      id, owner_id, kind, purpose, original_filename, content_type,
      byte_size, width, height, duration_ms, sha256, object_path
    ) values (
      ${id}, ${userId}, ${input.kind}::public.media_kind, ${input.purpose}::public.media_purpose,
      ${input.original_filename}, ${input.content_type}, ${input.byte_size},
      ${input.width}, ${input.height}, ${input.duration_ms ?? null}, ${input.sha256}, ${objectPath}
    )
    returning id, owner_id, kind::text as kind, purpose::text as purpose,
      status::text as status, object_path, original_filename, content_type,
      byte_size::text, width, height, duration_ms, sha256, created_at
  `;
  if (!row) {
    throw new ApiError(500, ERROR_CODES.db_error, "Could not start the photo upload");
  }

  const admin = createAdminClient();
  const { data, error } = await admin.storage.from(BUCKET).createSignedUploadUrl(objectPath, {
    upsert: false,
  });
  if (error || !data?.signedUrl || !data.token) {
    await database`
      update public.media_objects
      set status = 'rejected'
      where id = ${id} and owner_id = ${userId}
    `;
    throw new ApiError(503, ERROR_CODES.storage_error, "Could not authorize the photo upload");
  }

  return {
    media: mapMedia(row, null),
    upload: {
      url: data.signedUrl,
      token: data.token,
      method: "PUT",
    },
  };
}

export async function commitMediaUpload(
  userId: string,
  mediaId: string,
  database: Sql = createDatabaseClient(),
): Promise<MediaObject> {
  const [row] = await database<MediaRow[]>`
    select id, owner_id, kind::text as kind, purpose::text as purpose,
      status::text as status, object_path, original_filename, content_type,
      byte_size::text, width, height, duration_ms, sha256, created_at
    from public.media_objects
    where id = ${mediaId} and owner_id = ${userId}
  `;
  if (!row) {
    throw new ApiError(404, ERROR_CODES.not_found, "Photo upload not found");
  }
  if (row.status === "ready") {
    return mapMedia(row, await signMediaUrl(row.object_path));
  }
  if (row.status !== "pending") {
    throw new ApiError(409, ERROR_CODES.conflict, "This photo can no longer be saved");
  }

  const admin = createAdminClient();
  const { data, error } = await admin.storage.from(BUCKET).download(row.object_path);
  if (error || !data) {
    throw new ApiError(409, ERROR_CODES.archive_not_found, "Upload the photo before saving it");
  }
  const bytes = Buffer.from(await data.arrayBuffer());
  if (bytes.byteLength !== Number(row.byte_size)) {
    await database`
      update public.media_objects
      set status = 'rejected'
      where id = ${mediaId} and owner_id = ${userId}
    `;
    await removeStoragePaths([row.object_path]);
    throw new ApiError(409, ERROR_CODES.archive_size_mismatch, "That photo did not match its size");
  }
  const digest = createHash("sha256").update(bytes).digest("hex");
  if (digest !== row.sha256) {
    await database`
      update public.media_objects
      set status = 'rejected'
      where id = ${mediaId} and owner_id = ${userId}
    `;
    await removeStoragePaths([row.object_path]);
    throw new ApiError(409, ERROR_CODES.archive_checksum_mismatch, "That photo did not match its checksum");
  }

  const [ready] = await database<MediaRow[]>`
    update public.media_objects
    set status = 'ready', committed_at = now()
    where id = ${mediaId} and owner_id = ${userId} and status = 'pending'
    returning id, owner_id, kind::text as kind, purpose::text as purpose,
      status::text as status, object_path, original_filename, content_type,
      byte_size::text, width, height, duration_ms, sha256, created_at
  `;
  if (!ready) {
    throw new ApiError(409, ERROR_CODES.conflict, "This photo can no longer be saved");
  }
  return mapMedia(ready, await signMediaUrl(ready.object_path));
}

export async function loadReadyMedia(
  userId: string,
  mediaIds: string[],
  purpose: "profile" | "fight_post",
  database: Sql = createDatabaseClient(),
): Promise<MediaRow[]> {
  if (mediaIds.length === 0) return [];
  return database<MediaRow[]>`
    select id, owner_id, kind::text as kind, purpose::text as purpose,
      status::text as status, object_path, original_filename, content_type,
      byte_size::text, width, height, duration_ms, sha256, created_at
    from public.media_objects
    where owner_id = ${userId}
      and purpose = ${purpose}::public.media_purpose
      and status = 'ready'
      and id in ${database(mediaIds)}
  `;
}

export async function removeStoragePaths(paths: string[]): Promise<void> {
  if (paths.length === 0) return;
  const admin = createAdminClient();
  const { error } = await admin.storage.from(BUCKET).remove(paths);
  if (error && error.status !== 404 && error.statusCode !== "404") {
    throw new ApiError(503, ERROR_CODES.storage_error, "Could not remove uploaded photos");
  }
}

export async function removeUserMediaObjects(
  userId: string,
  database: Sql = createDatabaseClient(),
): Promise<void> {
  const rows = await database<{ object_path: string }[]>`
    select object_path from public.media_objects where owner_id = ${userId}
  `;
  await removeStoragePaths(rows.map((entry) => entry.object_path));
}

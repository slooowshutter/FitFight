import { createHash } from "node:crypto";
import { ApiError, ERROR_CODES } from "@/lib/http";
import {
  providerArchiveRecordSchema,
  type ProviderArchiveRecord,
} from "@/lib/types/provider-uploads/provider-upload";

export const maximumProviderArchiveBytes = 512 * 1_024 * 1_024;

export function requireProviderArchiveSize(byteSize: number): void {
  if (byteSize > maximumProviderArchiveBytes) {
    throw new ApiError(413, ERROR_CODES.archive_too_large, "Archive exceeds 512 MiB");
  }
}

export async function readProviderArchive(
  stream: ReadableStream<Uint8Array>,
  expectedBytes: number,
  expectedSha256: string,
  consumeEvent?: (item: {
    record: Extract<ProviderArchiveRecord, { type: "sample" | "deletion" }>;
    inputHash: string;
  }) => Promise<void>,
) {
  const reader = stream.getReader();
  const decoder = new TextDecoder("utf-8", { fatal: true });
  const hash = createHash("sha256");
  const records: Array<{ record: ProviderArchiveRecord; inputHash: string }> = [];
  const unique = new Set<string>();
  let pending = "";
  let bytes = 0;
  let lineNumber = 0;
  let checkpointSeen = false;
  let sampleCount = 0;
  let deletionCount = 0;

  const consume = async (line: string) => {
    lineNumber += 1;
    const text = line.endsWith("\r") ? line.slice(0, -1) : line;
    if (!text) {
      throw new ApiError(400, ERROR_CODES.archive_invalid, `Archive line ${lineNumber} is empty`);
    }
    if (new TextEncoder().encode(text).byteLength > 1_000_000) {
      throw new ApiError(400, ERROR_CODES.archive_invalid, `Archive line ${lineNumber} is too large`);
    }
    let value: unknown;
    try {
      value = JSON.parse(text) as unknown;
    } catch {
      throw new ApiError(400, ERROR_CODES.archive_invalid, `Archive line ${lineNumber} is invalid JSON`);
    }
    const parsed = providerArchiveRecordSchema.safeParse(value);
    if (!parsed.success) {
      throw new ApiError(
        400,
        ERROR_CODES.archive_invalid,
        `Archive line ${lineNumber}: ${parsed.error.issues[0]?.message ?? "invalid record"}`,
      );
    }
    if (checkpointSeen) {
      throw new ApiError(400, ERROR_CODES.archive_invalid, "Checkpoint must be the final record");
    }
    const record = parsed.data;
    const inputHash = createHash("sha256").update(text, "utf8").digest("hex");
    if (record.type === "sample" || record.type === "deletion") {
      if (record.type === "sample") {
        sampleCount += 1;
      } else {
        deletionCount += 1;
      }
      if (consumeEvent) {
        await consumeEvent({ record, inputHash });
      }
      return;
    }

    const key = record.type === "merged_day"
      ? `${record.type}:${record.day}`
      : record.type === "source_day"
        ? `${record.type}:${record.day}:${record.source_bundle_identifier}`
        : record.type === "fight_aggregate"
          ? `${record.type}:${record.fight_id}`
          : record.type;
    if (unique.has(key)) {
      throw new ApiError(400, ERROR_CODES.archive_invalid, `Duplicate archive record: ${key}`);
    }
    unique.add(key);
    checkpointSeen = record.type === "checkpoint";
    records.push({ record, inputHash });
  };

  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      bytes += value.byteLength;
      if (bytes > maximumProviderArchiveBytes) {
        throw new ApiError(413, ERROR_CODES.archive_too_large, "Archive exceeds 512 MiB");
      }
      hash.update(value);
      try {
        pending += decoder.decode(value, { stream: true });
      } catch {
        throw new ApiError(400, ERROR_CODES.archive_invalid, "Archive is not valid UTF-8");
      }
      let newline = pending.indexOf("\n");
      while (newline >= 0) {
        await consume(pending.slice(0, newline));
        pending = pending.slice(newline + 1);
        newline = pending.indexOf("\n");
      }
    }
    try {
      pending += decoder.decode();
    } catch {
      throw new ApiError(400, ERROR_CODES.archive_invalid, "Archive is not valid UTF-8");
    }
    if (pending) {
      await consume(pending);
    }
  } catch (error) {
    await reader.cancel();
    throw error;
  }

  if (bytes !== expectedBytes) {
    throw new ApiError(400, ERROR_CODES.archive_size_mismatch, "Archive byte size does not match");
  }
  const actualSha256 = hash.digest("hex");
  if (actualSha256 !== expectedSha256) {
    throw new ApiError(400, ERROR_CODES.archive_checksum_mismatch, "Archive checksum does not match");
  }
  if (!checkpointSeen) {
    throw new ApiError(400, ERROR_CODES.archive_invalid, "Archive checkpoint is missing");
  }

  return {
    records,
    sampleCount,
    deletionCount,
    actualBytes: bytes,
    actualSha256,
  };
}

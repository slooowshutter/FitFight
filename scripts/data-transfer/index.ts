/** Temporary cloud maintenance endpoint for the authorized 1.1.1 production transfer. */
import { Buffer } from "node:buffer";
import { createHash, randomUUID, timingSafeEqual } from "node:crypto";
import postgres from "postgres";
import { createClient } from "@supabase/supabase-js";
import { planDataTransfer, transferDigest } from "@/lib/releases/data-transfer";
import {
    applyDataTransfer,
    readTransferMedia,
    readTransferSnapshot,
} from "@/lib/supabase/queries/data-transfer-supabase-query";
import {
    transferArchiveSchema,
    transferApplicationResultSchema,
    transferEnvironmentSchema,
    transferFailureMetadataSchema,
    transferMediaSchema,
    transferReceiptSchema,
    transferRequestSchema,
    transferSnapshotSchema,
    transferUserSchema,
    type TransferPlan,
} from "@/lib/types/releases/data-transfer";

const environment = transferEnvironmentSchema.parse(Deno.env.toObject());
const sourceProject = "zstzbfocunthczzubggz";
const archiveBucket = "release-transfer-rehearsal";
const project = new URL(environment.SUPABASE_URL).hostname.split(".")[0];
if (![sourceProject, environment.FF_RELEASE_TRANSFER_TARGET].includes(project))
    throw new Error("Unexpected transfer environment");
const database = postgres(environment.SUPABASE_DB_URL, {
    max: 1,
    prepare: false,
});
const admin = createClient(
    environment.SUPABASE_URL,
    environment.SUPABASE_SERVICE_ROLE_KEY,
    {
        auth: {
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUrl: false,
        },
    },
);
const authorization = `Bearer ${environment.FF_RELEASE_TRANSFER_TOKEN}`;

Deno.serve(async (request) => {
    const incoming = Buffer.from(request.headers.get("Authorization") ?? "");
    const expected = Buffer.from(authorization);
    if (
        Date.now() >= Date.parse(environment.FF_RELEASE_TRANSFER_EXPIRES_AT) ||
        request.method !== "POST" ||
        incoming.length !== expected.length ||
        !timingSafeEqual(incoming, expected)
    )
        return new Response(null, { status: 404 });

    let phase = "request";
    try {
        const input = transferRequestSchema.parse(await request.json());
        // 1. Source data travels only to the authenticated cloud importer.
        if (project === sourceProject) {
            if (input.action === "snapshot") {
                phase = "source_snapshot";
                const snapshot = await database.begin(
                    "isolation level repeatable read read only",
                    (transaction) => readTransferSnapshot(transaction, project),
                );
                return Response.json(snapshot, {
                    headers: { "Cache-Control": "no-store" },
                });
            }
            if (input.action === "media") {
                phase = "source_media";
                const media = await readTransferMedia(database, input.id);
                if (!media) return new Response(null, { status: 404 });
                const file = await admin.storage
                    .from(media.bucket_id)
                    .download(media.object_path);
                if (file.error) throw file.error;
                return new Response(file.data, {
                    headers: {
                        "Content-Type": media.content_type,
                        "Cache-Control": "no-store",
                    },
                });
            }
            return new Response(null, { status: 404 });
        }
        if (input.action === "snapshot" || input.action === "media")
            return new Response(null, { status: 404 });

        // 2. Freeze the plan before copying files or acquiring target write locks.
        if (input.action === "prepare") {
            phase = "source_fetch";
            const response = await fetch(
                `https://${sourceProject}.supabase.co/functions/v1/ff-release-transfer`,
                {
                    method: "POST",
                    headers: {
                        Authorization: authorization,
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify({ action: "snapshot" }),
                },
            );
            if (!response.ok) throw new Error("Source snapshot unavailable");
            const source = transferSnapshotSchema.parse(await response.json());
            if (source.project_ref !== sourceProject)
                throw new Error("Unexpected source snapshot");
            phase = "target_snapshot";
            const target = await database.begin(
                "isolation level repeatable read read only",
                (transaction) => readTransferSnapshot(transaction, project),
            );
            let previous: TransferPlan | null = null;
            if (input.previous_run_id) {
                phase = "previous_checkpoint";
                const prior = await admin.storage
                    .from(archiveBucket)
                    .download(`${input.previous_run_id}/archive.json`);
                if (prior.error) throw prior.error;
                const archive = transferArchiveSchema.parse(
                    JSON.parse(await prior.data.text()),
                );
                if (
                    archive.source.project_ref !== sourceProject ||
                    archive.target.project_ref !== project
                )
                    throw new Error("Checkpoint belongs to another transfer");
                const applied = await admin.storage
                    .from(archiveBucket)
                    .download(`${input.previous_run_id}/applied.json`);
                if (applied.error) throw applied.error;
                const result = transferApplicationResultSchema.parse(
                    JSON.parse(await applied.data.text()),
                );
                if (
                    !result.committed ||
                    result.verified_digest !== archive.plan.after_digest
                )
                    throw new Error(
                        "Previous checkpoint was not successfully applied",
                    );
                previous = archive.plan;
            }
            phase = "plan";
            const plan = planDataTransfer(source, target, previous);
            if (plan.conflicts.length > 0)
                return Response.json(
                    { status: "conflicts", conflicts: plan.conflicts },
                    { status: 409 },
                );
            const archive = transferArchiveSchema.parse({
                id: randomUUID(),
                source,
                target,
                plan,
            });
            phase = "checkpoint_write";
            const saved = await admin.storage
                .from(archiveBucket)
                .upload(`${archive.id}/archive.json`, JSON.stringify(archive), {
                    contentType: "application/json",
                    upsert: false,
                });
            if (saved.error) throw saved.error;
            return Response.json({
                status: "prepared",
                run_id: archive.id,
                profile_policy: plan.profile_policy,
                source_accounts: source.rows["auth.users"].length,
                target_accounts: target.rows["auth.users"].length,
                shared_accounts: plan.shared_accounts,
                combined_accounts: plan.total_accounts,
                media_files: source.rows["public.media_objects"].length,
                unfinished_uploads_excluded: source.pending_media,
                before_digest: plan.before_digest,
                after_digest: plan.after_digest,
                write_counts: Object.fromEntries(
                    Object.entries(plan.writes).map(([table, rows]) => [
                        table,
                        rows.length,
                    ]),
                ),
            });
        }

        phase = "checkpoint_read";
        const checkpoint = await admin.storage
            .from(archiveBucket)
            .download(`${input.run_id}/archive.json`);
        if (checkpoint.error) throw checkpoint.error;
        const archive = transferArchiveSchema.parse(
            JSON.parse(await checkpoint.data.text()),
        );
        if (
            archive.id !== input.run_id ||
            archive.target.project_ref !== project ||
            archive.source.project_ref !== sourceProject
        )
            throw new Error("Checkpoint does not match this environment");
        const sourceMedia = transferMediaSchema
            .array()
            .parse(archive.source.rows["public.media_objects"]);
        const targetMedia = transferMediaSchema
            .array()
            .parse(archive.plan.imported["public.media_objects"]);
        const receipts = await admin.storage
            .from(archiveBucket)
            .list(`${input.run_id}/files`, { limit: 1000 });
        if (receipts.error) throw receipts.error;
        const completed = new Set(receipts.data.map((file) => file.name));

        // 3. Copy bounded batches and verify both ends before recording each receipt.
        if (input.action === "copy-media") {
            const pending = sourceMedia.filter(
                (media) => !completed.has(`${media.id}.json`),
            );
            for (const media of pending.slice(0, 5)) {
                phase = "media_download";
                const response = await fetch(
                    `https://${sourceProject}.supabase.co/functions/v1/ff-release-transfer`,
                    {
                        method: "POST",
                        headers: {
                            Authorization: authorization,
                            "Content-Type": "application/json",
                        },
                        body: JSON.stringify({ action: "media", id: media.id }),
                    },
                );
                if (!response.ok) throw new Error("Source media unavailable");
                const bytes = await response.arrayBuffer();
                const hash = createHash("sha256")
                    .update(new Uint8Array(bytes))
                    .digest("hex");
                if (
                    hash !== media.sha256 ||
                    bytes.byteLength !== media.byte_size
                )
                    throw new Error("Source media changed since preparation");
                const target = targetMedia.find((row) => row.id === media.id);
                if (!target) throw new Error("Media mapping is missing");
                phase = "media_upload";
                const uploaded = await admin.storage
                    .from(target.bucket_id)
                    .upload(target.object_path, bytes, {
                        contentType: media.content_type,
                        upsert: false,
                    });
                if (uploaded.error) {
                    const existing = await admin.storage
                        .from(target.bucket_id)
                        .download(target.object_path);
                    if (existing.error) throw uploaded.error;
                    const existingBytes = await existing.data.arrayBuffer();
                    if (
                        existingBytes.byteLength !== media.byte_size ||
                        createHash("sha256")
                            .update(new Uint8Array(existingBytes))
                            .digest("hex") !== hash
                    )
                        throw new Error("Target media conflicts with source");
                }
                phase = "media_verify";
                const verified = await admin.storage
                    .from(target.bucket_id)
                    .download(target.object_path);
                if (verified.error) throw verified.error;
                const verifiedBytes = await verified.data.arrayBuffer();
                if (
                    verifiedBytes.byteLength !== media.byte_size ||
                    createHash("sha256")
                        .update(new Uint8Array(verifiedBytes))
                        .digest("hex") !== hash
                )
                    throw new Error("Target media verification failed");
                const receipt = transferReceiptSchema.parse({
                    sha256: hash,
                    byte_size: bytes.byteLength,
                });
                const saved = await admin.storage
                    .from(archiveBucket)
                    .upload(
                        `${input.run_id}/files/${media.id}.json`,
                        JSON.stringify(receipt),
                        { contentType: "application/json", upsert: false },
                    );
                if (saved.error) throw saved.error;
                completed.add(`${media.id}.json`);
            }
            return Response.json({
                status: "media_copied",
                files_verified: completed.size,
                files_remaining: sourceMedia.length - completed.size,
            });
        }
        if (sourceMedia.some((media) => !completed.has(`${media.id}.json`)))
            throw new Error("Media verification is incomplete");

        // 4. The default rehearsal verifies real writes, then rolls the entire transaction back.
        if (input.action === "apply" || input.action === "rehearse") {
            phase = "database_transfer";
            const result = await applyDataTransfer(
                database,
                archive,
                input.action === "apply",
            );
            if (result.committed) {
                const saved = await admin.storage
                    .from(archiveBucket)
                    .upload(
                        `${input.run_id}/applied.json`,
                        JSON.stringify(result),
                        { contentType: "application/json", upsert: true },
                    );
                if (saved.error) throw saved.error;
            }
            return Response.json({
                status: result.committed
                    ? "applied"
                    : "rehearsed_and_rolled_back",
                ...result,
                files_verified: completed.size,
                combined_accounts: archive.plan.total_accounts,
            });
        }
        phase = "verify";
        const current = await database.begin(
            "isolation level repeatable read read only",
            (transaction) => readTransferSnapshot(transaction, project),
        );
        const digest = transferDigest(current.rows);
        let authAccountsVerified = 0;
        if (digest === archive.plan.after_digest) {
            phase = "auth_read";
            const users = transferUserSchema
                .array()
                .parse(current.rows["auth.users"]);
            for (const user of users) {
                const account = await admin.auth.admin.getUserById(user.id);
                if (account.error) throw account.error;
                phase = "auth_identity_verify";
                if (
                    account.data.user.id !== user.id ||
                    !account.data.user.identities?.some(
                        (identity) => identity.provider === "apple",
                    )
                )
                    throw new Error(
                        "Imported Apple account is unavailable in Auth",
                    );
                authAccountsVerified += 1;
                phase = "auth_read";
            }
        }
        return Response.json({
            status:
                digest === archive.plan.after_digest
                    ? "verified"
                    : digest === archive.plan.before_digest
                      ? "unchanged"
                      : "changed",
            accounts: current.rows["auth.users"].length,
            fights: current.rows["public.fights"].length,
            files_verified: completed.size,
            auth_accounts_verified: authAccountsVerified,
            digest,
        });
    } catch (error) {
        // SQL details can contain names, email addresses, Health values, or file paths.
        const metadata = transferFailureMetadataSchema.safeParse(error);
        return Response.json(
            {
                error: "transfer_failed",
                phase,
                metadata: metadata.success ? metadata.data : {},
            },
            { status: 500 },
        );
    }
});

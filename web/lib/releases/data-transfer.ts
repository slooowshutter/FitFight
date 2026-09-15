import { createHash } from "node:crypto";
import { z } from "zod";
import {
    transferIdentitySchema,
    transferMediaSchema,
    transferPlanSchema,
    transferProfileSchema,
    transferSourceSchema,
    transferTableValues,
    transferUserSchema,
    type TransferPlan,
    type TransferRow,
    type TransferSnapshot,
} from "@/lib/types/releases/data-transfer";

/** Object key order is irrelevant; array order remains part of the stored contract. */
export function transferDigest(value: unknown): string {
    const canonical = JSON.stringify(value, (_key, item: unknown) => {
        if (item !== null && typeof item === "object" && !Array.isArray(item)) {
            return Object.fromEntries(
                Object.entries(item).sort(([left], [right]) =>
                    left < right ? -1 : left > right ? 1 : 0,
                ),
            );
        }
        return item;
    });
    return createHash("sha256").update(canonical).digest("hex");
}

/** Beta profile details win; other records retain three-way conflict protection. */
export function planDataTransfer(
    source: TransferSnapshot,
    target: TransferSnapshot,
    previous: TransferPlan | null,
): TransferPlan {
    const conflictCounts = new Map<string, number>();
    const sourceUsers = transferUserSchema
        .array()
        .parse(source.rows["auth.users"]);
    const targetUsers = transferUserSchema
        .array()
        .parse(target.rows["auth.users"]);
    const sourceIdentities = transferIdentitySchema
        .array()
        .parse(source.rows["auth.identities"]);
    const targetIdentities = transferIdentitySchema
        .array()
        .parse(target.rows["auth.identities"]);
    const targetByApple = new Map(
        targetIdentities.map((identity) => [identity.provider_id, identity]),
    );
    const userIds: Record<string, string> = {};
    const identityIds: Record<string, string> = {};

    // 1. Account identity survives the environment change; production UUIDs and referral codes stay stable.
    for (const identity of sourceIdentities) {
        const existing = targetByApple.get(identity.provider_id);
        if (userIds[identity.user_id])
            throw new Error("Source account has multiple Apple identities");
        userIds[identity.user_id] = existing
            ? existing.user_id
            : identity.user_id;
        identityIds[identity.id] = existing ? existing.id : identity.id;
    }
    if (Object.keys(userIds).length !== sourceUsers.length)
        throw new Error("Source account is missing its Apple identity");
    for (const user of sourceUsers) {
        if (user.deleted_at !== null)
            throw new Error("A deleted source account cannot be imported");
        const id = userIds[user.id];
        const existing = targetUsers.find((candidate) => candidate.id === id);
        if (existing?.deleted_at)
            throw new Error(
                "A deleted production account cannot be restored by an import",
            );
        if (
            existing &&
            !targetIdentities.some(
                (identity) =>
                    identity.user_id === id &&
                    sourceIdentities.some(
                        (candidate) =>
                            candidate.user_id === user.id &&
                            candidate.provider_id === identity.provider_id,
                    ),
            )
        ) {
            throw new Error(
                "Account UUID collides with a different Apple identity",
            );
        }
        if (
            user.email !== null &&
            targetUsers.some(
                (candidate) =>
                    candidate.id !== id &&
                    candidate.email?.toLowerCase() ===
                        user.email?.toLowerCase(),
            )
        ) {
            throw new Error("Email belongs to another production account");
        }
    }

    const sourceSources = transferSourceSchema
        .array()
        .parse(source.rows["public.data_sources"]);
    const targetSources = transferSourceSchema
        .array()
        .parse(target.rows["public.data_sources"]);
    const sourceIds: Record<string, string> = {};
    for (const dataSource of sourceSources) {
        const existing = targetSources.find(
            (candidate) =>
                candidate.user_id === userIds[dataSource.user_id] &&
                candidate.provider === dataSource.provider &&
                candidate.connection_route === dataSource.connection_route,
        );
        if (
            !existing &&
            targetSources.some((candidate) => candidate.id === dataSource.id)
        ) {
            throw new Error(
                "Activity source UUID belongs to a different connection",
            );
        }
        sourceIds[dataSource.id] = existing ? existing.id : dataSource.id;
    }
    const sourceProfiles = transferProfileSchema
        .array()
        .parse(source.rows["public.profiles"]);
    const targetProfiles = transferProfileSchema
        .array()
        .parse(target.rows["public.profiles"]);
    for (const profile of sourceProfiles) {
        if (profile.deleted_at !== null)
            throw new Error("A deleted source profile cannot be imported");
        const id = userIds[profile.user_id];
        if (
            targetProfiles.some(
                (candidate) =>
                    candidate.user_id === id && candidate.deleted_at !== null,
            )
        ) {
            throw new Error(
                "A deleted production profile cannot be restored by an import",
            );
        }
        if (
            targetProfiles.some(
                (candidate) =>
                    candidate.user_id !== id &&
                    candidate.handle.toLowerCase() ===
                        profile.handle.toLowerCase(),
            )
        ) {
            throw new Error("Username belongs to another production account");
        }
        if (
            targetProfiles.some(
                (candidate) =>
                    candidate.user_id !== id &&
                    candidate.referral_code === profile.referral_code,
            )
        ) {
            throw new Error(
                "Referral code belongs to another production account",
            );
        }
    }

    // 2. Remap only declared references. Free text and historical input hashes remain byte-for-byte intact.
    const imported: Record<string, TransferRow[]> = {};
    const writes: Record<string, TransferRow[]> = {};
    const after: Record<string, TransferRow[]> = {};
    for (const table of transferTableValues) {
        const definition = target.definitions[table];
        if (
            transferDigest(definition) !==
            transferDigest(source.definitions[table])
        ) {
            throw new Error(`Schema differs for ${table}`);
        }
        const existingRows = new Map(
            target.rows[table].map((row) => [
                JSON.stringify(
                    definition.primary_key.map((column) => row[column]),
                ),
                row,
            ]),
        );
        const priorRows = new Map(
            (previous ? previous.imported[table] : []).map((row) => [
                JSON.stringify(
                    definition.primary_key.map((column) => row[column]),
                ),
                row,
            ]),
        );
        const desiredRows = new Map<string, TransferRow>();
        writes[table] = [];

        for (const original of source.rows[table]) {
            let row = { ...original };
            for (const column of definition.user_columns) {
                if (row[column] === null) continue;
                const id = z.string().uuid().parse(row[column]);
                if (!userIds[id])
                    throw new Error(`Unmapped account reference in ${table}`);
                row[column] = userIds[id];
            }
            for (const column of definition.source_columns) {
                if (row[column] === null) continue;
                const id = z.string().uuid().parse(row[column]);
                if (!sourceIds[id])
                    throw new Error(`Unmapped activity source in ${table}`);
                row[column] = sourceIds[id];
            }
            if (table === "auth.users")
                row.id = userIds[z.string().parse(original.id)];
            if (table === "auth.identities")
                row.id = identityIds[z.string().parse(original.id)];
            if (table === "public.data_sources")
                row.id = sourceIds[z.string().parse(original.id)];
            if (table === "public.media_objects") {
                const media = transferMediaSchema.parse(original);
                if (
                    media.object_path !==
                    `${media.owner_id}/${media.purpose}/${media.id}`
                )
                    throw new Error("Unexpected media path");
                row.object_path = `${userIds[media.owner_id]}/${media.purpose}/${media.id}`;
            }
            if (
                table === "private.fight_score_snapshots" &&
                row.upload_id !== null
            ) {
                throw new Error(
                    "A historical snapshot still depends on an operational upload",
                );
            }
            const key = JSON.stringify(
                definition.primary_key.map((column) => row[column]),
            );
            const existing = existingRows.get(key);
            const prior = priorRows.get(key);

            if (
                existing &&
                (table === "auth.users" || table === "auth.identities")
            ) {
                row = existing;
            } else if (existing && table === "public.profiles") {
                row.referral_code = existing.referral_code;
            } else if (existing && table === "public.data_sources" && !prior) {
                const currentSource = transferSourceSchema.parse(existing);
                const betaSource = transferSourceSchema.parse(row);
                if (currentSource.revoked_at !== null)
                    throw new Error(
                        "Production activity connection was revoked",
                    );
                if (
                    currentSource.last_success_at !== null &&
                    (betaSource.last_success_at === null ||
                        Date.parse(currentSource.last_success_at) >
                            Date.parse(betaSource.last_success_at))
                )
                    row = existing;
            }

            desiredRows.set(key, row);
            if (!existing) {
                if (prior) {
                    const reason = `${table}|production_deleted_imported_record`;
                    conflictCounts.set(
                        reason,
                        (conflictCounts.get(reason) ?? 0) + 1,
                    );
                } else {
                    writes[table].push(row);
                }
            } else if (transferDigest(existing) !== transferDigest(row)) {
                const explicitlyMerged =
                    table === "public.profiles" ||
                    (!previous && table === "public.data_sources");
                if (
                    explicitlyMerged ||
                    (prior &&
                        transferDigest(existing) === transferDigest(prior))
                ) {
                    writes[table].push(row);
                } else if (
                    prior &&
                    transferDigest(row) === transferDigest(prior)
                ) {
                    // Keep the original imported value as the baseline for detecting a future two-sided edit.
                } else {
                    const reason = `${table}|different_existing_record`;
                    conflictCounts.set(
                        reason,
                        (conflictCounts.get(reason) ?? 0) + 1,
                    );
                }
            }
        }

        for (const key of priorRows.keys()) {
            if (!desiredRows.has(key) && existingRows.has(key)) {
                const reason = `${table}|beta_deleted_imported_record`;
                conflictCounts.set(
                    reason,
                    (conflictCounts.get(reason) ?? 0) + 1,
                );
            }
        }
        imported[table] = [...desiredRows.entries()]
            .sort(([left], [right]) =>
                left < right ? -1 : left > right ? 1 : 0,
            )
            .map(([, row]) => row);
        for (const row of writes[table])
            existingRows.set(
                JSON.stringify(
                    definition.primary_key.map((column) => row[column]),
                ),
                row,
            );
        after[table] = [...existingRows.entries()]
            .sort(([left], [right]) =>
                left < right ? -1 : left > right ? 1 : 0,
            )
            .map(([, row]) => row);
    }

    // 3. One transaction must produce this exact snapshot; a changed target requires a fresh plan.
    return transferPlanSchema.parse({
        profile_policy: "beta",
        user_ids: userIds,
        source_ids: sourceIds,
        identity_ids: identityIds,
        before_digest: transferDigest(target.rows),
        after_digest: transferDigest(after),
        imported,
        writes,
        after,
        conflicts: [...conflictCounts].map(([key, count]) => {
            const [table, reason] = key.split("|");
            return { table, reason, count };
        }),
        shared_accounts: sourceUsers.filter((user) =>
            targetUsers.some((existing) => existing.id === userIds[user.id]),
        ).length,
        total_accounts: after["auth.users"].length,
    });
}

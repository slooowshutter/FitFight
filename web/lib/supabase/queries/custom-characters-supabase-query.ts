import { randomUUID } from "node:crypto";
import type { Sql, TransactionSql } from "postgres";
import { ApiError } from "@/lib/http";
import { companionSuggestions } from "@/lib/domain/ai/companion-suggestions";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { readActiveDeviceInstallations } from "@/lib/supabase/queries/device-installations-supabase-query";
import { readFreeCharacters, readReferralPending } from "@/lib/supabase/queries/free-characters-supabase-query";
import { readSpecialStore } from "@/lib/supabase/queries/specials-supabase-query";
import { customCharacterProductId, type AppleCustomCharacterTransaction } from "@/lib/types/apple/custom-character-purchase";
import {
    companionLabelRowSchema,
    companionLinesBatchSchema,
    customCharacterAttemptSchema,
    customCharacterClaimResultSchema,
    customCharacterPortraitRowSchema,
    customCharacterPurchaseRowSchema,
    customCharacterStoreSchema,
    freeCharacterGiftResultSchema,
    type CompanionLinesStep,
    type CustomCharacterAdvanceRequest,
    type CustomCharacterLabelRequest,
    type FreeCharacterGiftRequest,
    type CustomCharacterAttempt,
    type CustomCharacterStage,
} from "@/lib/types/ai/custom-character";

/** A current app asks for three portraits; slot 1 reuses the purchase key that older checks expect. */
async function saveCustomCharacterDescription(
    sql: TransactionSql,
    purchaseId: string,
    description: string,
    choosePortrait: boolean,
) {
    const key = randomUUID();
    const [saved] = await sql`update private.custom_character_purchases
        set description = ${description}, avatar_action_key = ${key} where id = ${purchaseId} returning *`;
    if (choosePortrait)
        await sql`insert into private.custom_character_portraits (purchase_id, slot, action_key)
            values (${purchaseId}, 1, ${key}), (${purchaseId}, 2, ${randomUUID()}), (${purchaseId}, 3, ${randomUUID()})`;
    return customCharacterPurchaseRowSchema.parse(saved);
}

/** Apple account tokens are shared with Specials; only this purchase flag controls new character checkout. */
export async function readCustomCharacterStore(
    userId: string,
    database: Sql = createDatabaseClient(),
    sandbox = false,
) {
    const account = await readSpecialStore(userId, database, sandbox);
    const purchases = customCharacterPurchaseRowSchema.array().parse(
        await database`select * from private.custom_character_purchases
            where account_id = ${account.app_account_token} order by created_at desc`,
    );
    const portraits = customCharacterPortraitRowSchema.array().parse(
        await database`select portrait.id, portrait.purchase_id, portrait.slot, portrait.action_key, portrait.selected_at
            from private.custom_character_portraits portrait
            join private.custom_character_purchases purchase on purchase.id = portrait.purchase_id
            where purchase.account_id = ${account.app_account_token} order by portrait.slot`,
    );
    const attempts = customCharacterAttemptSchema.array().parse(
        await database`select resource_id, id as request_id, workflow, status, next_poll_at, idempotency_key,
                result ->> 'image_url' as image_url
            from private.ai_requests where workflow in ('avatar', 'fitness') and resource_id in (
                select id from private.custom_character_purchases where account_id = ${account.app_account_token}
            ) order by created_at desc`,
    );
    const batches = companionLinesBatchSchema.array().parse(
        await database`select id, resource_id, idempotency_key, status, result
            from private.ai_requests where workflow = 'companion_lines' and resource_id in (
                select id from private.custom_character_purchases where account_id = ${account.app_account_token}
            ) order by created_at, id`,
    );
    const latest = new Map<string, CustomCharacterAttempt>();
    for (const attempt of attempts) {
        const key = `${attempt.resource_id}:${attempt.workflow}`;
        if (!latest.has(key)) latest.set(key, attempt);
    }
    const characters = purchases.map((purchase) => {
        const avatar = latest.get(`${purchase.id}:avatar`);
        const fitness = latest.get(`${purchase.id}:fitness`);
        const candidates = portraits.filter((portrait) => portrait.purchase_id === purchase.id).map((portrait) => {
            const attempt = attempts.find((item) => item.idempotency_key === portrait.action_key);
            const status = !attempt || ["starting", "pending", "running"].includes(attempt.status)
                ? "pending" as const
                : attempt.status === "completed"
                  ? "completed" as const
                  : attempt.status === "start_unconfirmed" ? "needs_support" as const : "failed" as const;
            return { portrait, attempt, status };
        });
        // Older purchases have no portrait rows: their single completed portrait is the chosen one.
        const chosen = candidates.length > 0
            ? candidates.find((candidate) => candidate.portrait.selected_at !== null)?.attempt
            : avatar?.status === "completed" ? avatar : undefined;
        const settledPhase = (attempt: CustomCharacterAttempt, running: "portraits" | "poses") =>
            attempt.status === "start_unconfirmed"
                ? "needs_support" as const
                : attempt.status === "failed" || attempt.status === "cancelled" ? "retryable" as const : running;
        const states = candidates.map((candidate) => candidate.status);
        const phase = purchase.revoked_at
            ? "refunded" as const
            : purchase.description === null
              ? "ready" as const
              : fitness
                ? fitness.status === "completed" ? "complete" as const : settledPhase(fitness, "poses")
                : chosen
                  ? "poses" as const
                  : candidates.length === 0
                    ? avatar ? settledPhase(avatar, "portraits") : "portraits" as const
                    : states.includes("pending")
                      ? "portraits" as const
                      : states.includes("completed")
                        ? "choosing" as const
                        : states.includes("needs_support") ? "needs_support" as const : "retryable" as const;
        const status = phase === "portraits" || phase === "choosing" || phase === "poses" ? "generating" : phase;
        const current = fitness ?? (candidates.length > 0
            ? chosen ?? candidates.find((candidate) => candidate.status === "pending" && candidate.attempt)?.attempt
                ?? candidates.find((candidate) => candidate.attempt)?.attempt
            : avatar);
        return {
            id: purchase.id,
            description: purchase.description,
            stage: status === "ready" || status === "refunded" ? null : fitness || chosen ? "fitness" : "portrait",
            status,
            request_id: current?.request_id ?? null,
            poll_after_seconds: status !== "generating"
                ? null
                : phase === "choosing"
                  ? 30
                  : Math.max(3, Math.ceil(((current?.next_poll_at.getTime() ?? Date.now()) - Date.now()) / 1000)),
            phase,
            portrait_url: purchase.revoked_at ? null : chosen?.image_url ?? null,
            candidates: purchase.revoked_at ? [] : candidates.map((candidate) => ({
                id: candidate.portrait.id,
                slot: candidate.portrait.slot,
                status: candidate.status,
                image_url: candidate.attempt?.image_url ?? null,
                selected: candidate.portrait.selected_at !== null,
            })),
            // Suggestions start once a portrait is chosen.
            ...(!purchase.revoked_at && (fitness || chosen)
                ? companionSuggestions(batches.filter((batch) => batch.resource_id === purchase.id))
                : { suggestions: [], suggestions_pending: false, more_suggestions_left: 0 }),
            name: purchase.name,
            line: purchase.line,
        };
    });
    return customCharacterStoreSchema.parse({
        app_account_token: account.app_account_token,
        environment: account.environment,
        purchases_enabled: true,
        product_id: customCharacterProductId,
        free_characters: await readFreeCharacters(database, userId),
        referral_pending: await readReferralPending(userId, database),
        characters,
    });
}

/**
 * Apple is the payment authority; a transaction ID can fund only one character in one account.
 * A description sent with the first claim is saved with it, so generation never depends on the phone.
 */
export async function recordCustomCharacterTransaction(
    transaction: AppleCustomCharacterTransaction,
    database: Sql = createDatabaseClient(),
    description?: string,
) {
    return database.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtextextended(${transaction.environment + ":" + transaction.originalTransactionId}, 2))`;
        const [owner] = await sql`select id, user_id, environment from private.special_accounts
            where id = ${transaction.appAccountToken}`;
        if (!owner || owner.environment !== transaction.environment)
            throw new ApiError(409, "character_account", "Purchase belongs to another FitFight account");
        if (owner.user_id)
            await sql`select id from public.profiles where id = ${owner.user_id} for update`;
        const [lockedOwner] = await sql`select user_id, environment from private.special_accounts
            where id = ${owner.id} for update`;
        if (lockedOwner.user_id !== owner.user_id || lockedOwner.environment !== transaction.environment)
            throw new ApiError(409, "character_account", "Purchase account changed");
        const [previous] = await sql`select * from private.custom_character_purchases
            where environment = ${transaction.environment} and
                (transaction_id = ${transaction.transactionId} or original_transaction_id = ${transaction.originalTransactionId})
            for update`;
        if (previous && (previous.account_id !== owner.id || previous.transaction_id !== transaction.transactionId ||
            previous.original_transaction_id !== transaction.originalTransactionId))
            throw new ApiError(409, "character_account", "Purchase is already bound to another account");
        const revoked = transaction.revocationDate !== undefined || transaction.revocationType !== undefined ||
            (transaction.revocationPercentage !== undefined && transaction.revocationPercentage > 0);
        const revokedAt = revoked ? new Date(transaction.revocationDate ?? transaction.signedDate).toISOString() : null;
        const signedAt = new Date(transaction.signedDate).toISOString();
        const purchaseAt = new Date(transaction.purchaseDate).toISOString();
        let purchase;
        if (!previous) {
            [purchase] = await sql`insert into private.custom_character_purchases
                (account_id, environment, transaction_id, original_transaction_id, revoked_at, signed_at, purchase_at, evidence)
                values (${owner.id}, ${transaction.environment}, ${transaction.transactionId},
                    ${transaction.originalTransactionId}, ${revokedAt}, ${signedAt}, ${purchaseAt}, ${sql.json(transaction)})
                returning *`;
        } else if (new Date(previous.signed_at).getTime() <= transaction.signedDate) {
            [purchase] = await sql`update private.custom_character_purchases set
                revoked_at = ${revokedAt}, signed_at = ${signedAt}, evidence = ${sql.json(transaction)}
                where id = ${previous.id} returning *`;
        } else {
            purchase = previous;
        }
        let saved = customCharacterPurchaseRowSchema.parse(purchase);
        if (description && !saved.revoked_at && saved.description === null && owner.user_id)
            saved = await saveCustomCharacterDescription(sql, saved.id, description, true);
        if (saved.revoked_at && owner.user_id) {
            await sql`update public.profiles set companion_id = null, companion_prompt = null, companion_image_url = null
                where id = ${owner.user_id} and companion_id = 'custom'
                    and companion_image_url in (
                        select library.image_url from private.ai_library_images library
                        join private.ai_requests request on request.id = library.request_id
                        where request.resource_id = ${saved.id}
                    )`;
        }
        return customCharacterClaimResultSchema.parse({
            purchase_id: saved.id,
            refunded: saved.revoked_at !== null,
        });
    });
}

/**
 * Uses one free character instead of an Apple charge and saves its description with three portraits, like a paid claim.
 * The client's key makes a retried request return the same character instead of using another one.
 */
export async function claimFreeCustomCharacter(
    userId: string,
    claimKey: string,
    description: string,
    database: Sql = createDatabaseClient(),
) {
    const account = await readSpecialStore(userId, database);
    return database.begin(async (sql) => {
        await sql`select id from public.profiles where id = ${userId} for update`;
        const [existing] = await sql`select id, account_id from private.custom_character_purchases
            where free_claim_key = ${claimKey}`;
        if (existing) {
            if (existing.account_id !== account.app_account_token)
                throw new ApiError(409, "ai_request_conflict", "This free character belongs to another account");
            return customCharacterClaimResultSchema.parse({ purchase_id: existing.id, refunded: false });
        }
        if (await readFreeCharacters(sql, userId) < 1)
            throw new ApiError(409, "no_free_characters", "You have no free characters left");
        const [purchase] = await sql`insert into private.custom_character_purchases (account_id, environment, free_claim_key)
            values (${account.app_account_token}, ${account.environment}, ${claimKey}) returning id`;
        await saveCustomCharacterDescription(sql, purchase.id, description, true);
        return customCharacterClaimResultSchema.parse({ purchase_id: purchase.id, refunded: false });
    });
}

/** Adds free characters to one username or to every current account. The same key never gives twice. */
export async function giftFreeCharacters(
    adminId: string,
    operationKey: string,
    input: FreeCharacterGiftRequest,
    database: Sql = createDatabaseClient(),
) {
    return database.begin(async (sql) => {
        await sql`insert into private.free_character_grants (user_id, quantity, reason, granted_by, operation_key)
            select user_id, ${input.quantity}, 'gift', ${adminId}, ${operationKey} from public.profiles
            where deleted_at is null and ${"everyone" in input ? sql`true` : sql`lower(handle) = lower(${input.username})`}
            on conflict (operation_key, user_id) do nothing`;
        const [given] = await sql`select count(*)::int as people from private.free_character_grants
            where operation_key = ${operationKey}`;
        if (given.people === 0) throw new ApiError(404, "not_found", "No account has this username");
        return freeCharacterGiftResultSchema.parse({ people: given.people, quantity: input.quantity });
    });
}

/** Stores action keys before a provider call, so a crash resumes the same stage without charging again. */
export async function prepareCustomCharacterStage(
    userId: string,
    purchaseId: string,
    input: CustomCharacterAdvanceRequest,
    database: Sql = createDatabaseClient(),
): Promise<CustomCharacterStage> {
    return database.begin(async (sql) => {
        const [profile] = await sql`select id from public.profiles
            where id = ${userId} and deleted_at is null for key share`;
        if (!profile) throw new ApiError(401, "profile_missing", "Invalid or deleted account");
        const [raw] = await sql`select purchase.* from private.custom_character_purchases purchase
            join private.special_accounts account on account.id = purchase.account_id
            where purchase.id = ${purchaseId} and account.user_id = ${userId}
            for update of purchase`;
        if (!raw) throw new ApiError(404, "not_found", "Character purchase not found");
        let purchase = customCharacterPurchaseRowSchema.parse(raw);
        if (purchase.revoked_at)
            throw new ApiError(403, "character_refunded", "This purchase was refunded");
        const attempts = customCharacterAttemptSchema.array().parse(
            await sql`select resource_id, id as request_id, workflow, status, next_poll_at, idempotency_key,
                    result ->> 'image_url' as image_url
                from private.ai_requests where resource_id = ${purchaseId} and workflow in ('avatar', 'fitness')
                order by created_at desc`,
        );
        // NOTE: each free retry or new description after a failure is a new paid Blend run, so a purchase gets a bounded number of them.
        if ((input.retry || (input.description && input.description !== purchase.description)) && attempts.filter((item) => ["failed", "cancelled"].includes(item.status)).length >= 6)
            throw new ApiError(409, "character_retry_limit", "This character needs support before another retry");
        let avatar = attempts.find((item) => item.workflow === "avatar");
        const fitness = attempts.find((item) => item.workflow === "fitness");
        if (purchase.description === null) {
            if (!input.description)
                throw new ApiError(400, "validation", "Describe your character before generating");
            purchase = await saveCustomCharacterDescription(sql, purchaseId, input.description, input.choose_portrait === true);
        }
        const portraits = customCharacterPortraitRowSchema.array().parse(
            await sql`select id, purchase_id, slot, action_key, selected_at from private.custom_character_portraits
                where purchase_id = ${purchaseId} order by slot for update`,
        );
        if (portraits.length > 0) {
            const attemptFor = (key: string) => attempts.find((item) => item.idempotency_key === key);
            const selected = portraits.find((portrait) => portrait.selected_at !== null);
            if (input.description && input.description !== purchase.description) {
                // Only a purchase whose three portraits all failed may start over with new words.
                if (selected || portraits.some((portrait) =>
                    !["failed", "cancelled"].includes(attemptFor(portrait.action_key)?.status ?? "")))
                    throw new ApiError(409, "ai_request_conflict", "This purchase already has a character description");
                const keys = portraits.map(() => randomUUID());
                await sql`update private.custom_character_purchases
                    set description = ${input.description}, avatar_action_key = ${keys[0]} where id = ${purchaseId}`;
                for (const [index, portrait] of portraits.entries())
                    await sql`update private.custom_character_portraits set action_key = ${keys[index]} where id = ${portrait.id}`;
                return { kind: "portraits", description: input.description, starts: keys, pending: [] };
            }
            if (!selected) {
                const starts: string[] = [];
                const pending: string[] = [];
                for (const portrait of portraits) {
                    const attempt = attemptFor(portrait.action_key);
                    if (!attempt) {
                        starts.push(portrait.action_key);
                    } else if (input.retry && ["failed", "cancelled"].includes(attempt.status)) {
                        const key = randomUUID();
                        await sql`update private.custom_character_portraits set action_key = ${key} where id = ${portrait.id}`;
                        starts.push(key);
                    } else if (["pending", "running"].includes(attempt.status)) {
                        pending.push(attempt.request_id);
                    }
                }
                if (purchase.description === null) throw new Error("Character description was not saved");
                return { kind: "portraits", description: purchase.description, starts, pending };
            }
            avatar = attemptFor(selected.action_key);
        } else if (input.description && input.description !== purchase.description) {
            // A portrait that Blend failed or cancelled has no image to keep, so a new description starts a new portrait.
            if (!avatar || !["failed", "cancelled"].includes(avatar.status))
                throw new ApiError(409, "ai_request_conflict", "This purchase already has a character description");
            const key = randomUUID();
            await sql`update private.custom_character_purchases
                set description = ${input.description}, avatar_action_key = ${key} where id = ${purchaseId}`;
            return { kind: "avatar", key, description: input.description };
        }
        const description = purchase.description;
        if (description === null) throw new Error("Character description was not saved");
        if (fitness) {
            if (!input.retry || !["failed", "cancelled"].includes(fitness.status))
                return { kind: "existing", requestId: fitness.request_id };
            const key = randomUUID();
            await sql`update private.custom_character_purchases set fitness_action_key = ${key} where id = ${purchaseId}`;
            if (!avatar || avatar.status !== "completed") throw new Error("Fitness has no completed source portrait");
            return { kind: "fitness", key, description, avatarRequestId: avatar.request_id };
        }
        if (avatar && avatar.status !== "completed") {
            if (!input.retry || !["failed", "cancelled"].includes(avatar.status))
                return { kind: "existing", requestId: avatar.request_id };
            const key = randomUUID();
            await sql`update private.custom_character_purchases set avatar_action_key = ${key} where id = ${purchaseId}`;
            return { kind: "avatar", key, description };
        }
        if (avatar) {
            const key = purchase.fitness_action_key ?? randomUUID();
            if (!purchase.fitness_action_key)
                await sql`update private.custom_character_purchases set fitness_action_key = ${key} where id = ${purchaseId}`;
            return { kind: "fitness", key, description, avatarRequestId: avatar.request_id };
        }
        if (!purchase.avatar_action_key) throw new Error("Character has no portrait action key");
        return { kind: "avatar", key: purchase.avatar_action_key, description };
    });
}

/**
 * Background reconciliation starts saved portraits, the poses of a chosen portrait, and owed pushes.
 * Owners with an unresolved request outside the purchase, other than a suggestion batch, are skipped because
 * reserveAiRequest would return ai_in_progress, so their purchases cannot fill every batch and starve newer ones.
 */
export async function dueCustomCharacterPurchases(database: Sql = createDatabaseClient()) {
    const rows = await database`select purchase.id, account.user_id from private.custom_character_purchases purchase
        join private.special_accounts account on account.id = purchase.account_id
        where purchase.description is not null and purchase.revoked_at is null and account.user_id is not null and (
            (
                not exists (select 1 from private.ai_requests request
                    where request.user_id = account.user_id and request.resource_id is distinct from purchase.id
                        and request.workflow <> 'companion_lines'
                        and request.status in ('starting', 'pending', 'running', 'start_unconfirmed'))
                and not exists (select 1 from private.ai_requests request
                    where request.resource_id = purchase.id and request.workflow = 'fitness')
                and (
                    (
                        not exists (select 1 from private.custom_character_portraits portrait where portrait.purchase_id = purchase.id)
                        and not exists (select 1 from private.ai_requests request
                            where request.user_id = account.user_id and request.workflow <> 'companion_lines'
                                and request.status in ('starting', 'pending', 'running', 'start_unconfirmed'))
                        and (not exists (select 1 from private.ai_requests request where request.resource_id = purchase.id)
                            or exists (select 1 from private.ai_requests request
                                where request.resource_id = purchase.id and request.workflow = 'avatar' and request.status = 'completed'))
                    )
                    or exists (select 1 from private.custom_character_portraits portrait
                        where portrait.purchase_id = purchase.id and portrait.selected_at is not null)
                    or (
                        not exists (select 1 from private.custom_character_portraits portrait
                            where portrait.purchase_id = purchase.id and portrait.selected_at is not null)
                        and exists (select 1 from private.custom_character_portraits portrait
                            where portrait.purchase_id = purchase.id and not exists (select 1 from private.ai_requests request
                                where request.user_id = account.user_id and request.idempotency_key = portrait.action_key))
                    )
                )
            )
            or (
                purchase.portraits_notified_at is null
                and not exists (select 1 from private.custom_character_portraits portrait
                    where portrait.purchase_id = purchase.id and (portrait.selected_at is not null
                        or not exists (select 1 from private.ai_requests request
                            where request.user_id = account.user_id and request.idempotency_key = portrait.action_key
                                and request.status in ('completed', 'failed', 'cancelled', 'start_unconfirmed'))))
                and exists (select 1 from private.custom_character_portraits portrait
                    join private.ai_requests request on request.user_id = account.user_id
                        and request.idempotency_key = portrait.action_key and request.status = 'completed'
                    where portrait.purchase_id = purchase.id)
            )
            or (
                purchase.poses_notified_at is null
                and exists (select 1 from private.ai_requests request
                    where request.resource_id = purchase.id and request.workflow = 'fitness' and request.status = 'completed')
            )
        )
        order by purchase.updated_at, purchase.id limit 4`;
    return rows.map((row) => ({ id: String(row.id), userId: String(row.user_id) }));
}

/** Moves a purchase that keeps failing to the back of the reconcile queue, so it cannot starve the others. */
export async function deferCustomCharacterPurchase(purchaseId: string, database: Sql = createDatabaseClient()) {
    await database`update private.custom_character_purchases set updated_at = now() where id = ${purchaseId}`;
}

/**
 * The oldest character with a chosen portrait and no suggestion batch yet, including those finished before
 * suggestions existed. One per run, and only while Blend is quiet, so the backfill never crowds out real work.
 * A character whose start failed has its first-batch key and waits behind those never tried; updated_at, which
 * orders the character work, stays untouched.
 */
export async function dueCompanionLines(database: Sql = createDatabaseClient()) {
    const rows = await database`select purchase.id, account.user_id from private.custom_character_purchases purchase
        join private.special_accounts account on account.id = purchase.account_id
        where purchase.revoked_at is null and account.user_id is not null
            and (select count(*) from private.ai_requests
                where status in ('starting', 'pending', 'running', 'start_unconfirmed')) < 10
            and not exists (select 1 from private.ai_requests request
                where request.resource_id = purchase.id and request.workflow = 'companion_lines')
            and exists (select 1 from private.ai_requests request
                where request.resource_id = purchase.id and request.workflow = 'avatar' and request.status = 'completed'
                    and (not exists (select 1 from private.custom_character_portraits portrait
                            where portrait.purchase_id = purchase.id)
                        or exists (select 1 from private.custom_character_portraits portrait
                            where portrait.purchase_id = purchase.id and portrait.selected_at is not null
                                and portrait.action_key = request.idempotency_key)))
        order by purchase.lines_action_key is not null, purchase.created_at, purchase.id limit 1`;
    return rows.map((row) => ({ id: String(row.id), userId: String(row.user_id) }));
}

/**
 * Saves the first-batch key before any provider call, so the app and the reconciler start the same first batch.
 * Without an attempt ID it returns a running batch to read, or the first batch while the character has none. With
 * one it prepares that "Four more" batch, which is the first batch when none was prepared yet; reserveAiRequest
 * checks the running batch and the limit under the admission lock.
 */
export async function prepareCompanionLines(
    userId: string,
    purchaseId: string,
    attemptId: string | null,
    database: Sql = createDatabaseClient(),
): Promise<CompanionLinesStep> {
    return database.begin(async (sql) => {
        const [raw] = await sql`select purchase.* from private.custom_character_purchases purchase
            join private.special_accounts account on account.id = purchase.account_id
            where purchase.id = ${purchaseId} and account.user_id = ${userId}
            for update of purchase`;
        if (!raw) throw new ApiError(404, "not_found", "Character purchase not found");
        const purchase = customCharacterPurchaseRowSchema.parse(raw);
        if (purchase.revoked_at)
            throw new ApiError(403, "character_refunded", "This purchase was refunded");
        const batches = companionLinesBatchSchema.array().parse(
            await sql`select id, resource_id, idempotency_key, status, result from private.ai_requests
                where resource_id = ${purchaseId} and workflow = 'companion_lines' order by created_at, id`,
        );
        if (attemptId && batches.some((batch) => batch.idempotency_key === attemptId)) return { kind: "none" };
        const running = batches.find((batch) => ["starting", "pending", "running"].includes(batch.status));
        if (!attemptId && running) return { kind: "pending", requestId: running.id };
        if (!attemptId && batches.length > 0) return { kind: "none" };
        const [portrait] = await sql`select request.id from private.ai_requests request
            where request.resource_id = ${purchaseId} and request.user_id = ${userId}
                and request.workflow = 'avatar' and request.status = 'completed'
                and (not exists (select 1 from private.custom_character_portraits portrait
                        where portrait.purchase_id = ${purchaseId})
                    or exists (select 1 from private.custom_character_portraits portrait
                        where portrait.purchase_id = ${purchaseId} and portrait.selected_at is not null
                            and portrait.action_key = request.idempotency_key))
            order by request.created_at desc limit 1`;
        if (!portrait) {
            if (attemptId) throw new ApiError(404, "not_found", "Choose a portrait first");
            return { kind: "none" };
        }
        if (purchase.description === null) throw new Error("Character description was not saved");
        const key = attemptId ?? purchase.lines_action_key ?? randomUUID();
        if (!purchase.lines_action_key)
            await sql`update private.custom_character_purchases set lines_action_key = ${key} where id = ${purchaseId}`;
        const [installation] = await readActiveDeviceInstallations(userId, sql);
        return {
            kind: "start",
            key,
            description: purchase.description,
            avatarRequestId: String(portrait.id),
            locale: installation?.locale ?? null,
            avoid: companionSuggestions(batches).suggestions,
        };
    });
}

/** Saves a name and line the owner picked, edited or typed. Like usernames, the text is not reviewed first. */
export async function saveCustomCharacterLabel(
    userId: string,
    purchaseId: string,
    input: CustomCharacterLabelRequest,
    database: Sql = createDatabaseClient(),
) {
    await database.begin(async (sql) => {
        const [purchase] = await sql`select purchase.id, purchase.revoked_at from private.custom_character_purchases purchase
            join private.special_accounts account on account.id = purchase.account_id
            where purchase.id = ${purchaseId} and account.user_id = ${userId}
            for update of purchase`;
        if (!purchase) throw new ApiError(404, "not_found", "Character purchase not found");
        if (purchase.revoked_at)
            throw new ApiError(403, "character_refunded", "This purchase was refunded");
        await sql`update private.custom_character_purchases set name = ${input.name}, line = ${input.line}
            where id = ${purchaseId}`;
    });
}

/**
 * The pair a profile shows for an equipped custom character: its saved name and line, else its first suggestion.
 * Empty for stock companions, Specials, refunded characters, and characters with neither.
 */
export async function readCompanionLabel(userId: string, imageUrl: string, database: Sql = createDatabaseClient()) {
    const [row] = await database`select coalesce(purchase.name, suggestion.name) as companion_name,
            coalesce(purchase.line, suggestion.line) as companion_line
        from private.ai_library_images library
        join private.ai_requests request on request.id = library.request_id
        join private.custom_character_purchases purchase on purchase.id = request.resource_id and purchase.revoked_at is null
        join private.special_accounts account on account.id = purchase.account_id and account.user_id = ${userId}
        left join lateral (
            select batch.result -> 'options' -> 0 ->> 'name' as name, batch.result -> 'options' -> 0 ->> 'line' as line
            from private.ai_requests batch
            where batch.resource_id = purchase.id and batch.workflow = 'companion_lines' and batch.status = 'completed'
            order by batch.created_at, batch.id limit 1
        ) suggestion on true
        where library.user_id = ${userId} and library.image_url = ${imageUrl}
            and coalesce(purchase.name, suggestion.name) is not null
        limit 1`;
    return row ? companionLabelRowSchema.parse(row) : {};
}

/** The owner picks one finished portrait; the other portraits are kept, unselected. */
export async function chooseCustomCharacterPortrait(
    userId: string,
    purchaseId: string,
    candidateId: string,
    database: Sql = createDatabaseClient(),
) {
    await database.begin(async (sql) => {
        const [purchase] = await sql`select purchase.id, purchase.revoked_at from private.custom_character_purchases purchase
            join private.special_accounts account on account.id = purchase.account_id
            where purchase.id = ${purchaseId} and account.user_id = ${userId}
            for update of purchase`;
        if (!purchase) throw new ApiError(404, "not_found", "Character purchase not found");
        if (purchase.revoked_at)
            throw new ApiError(403, "character_refunded", "This purchase was refunded");
        const portraits = await sql`select portrait.id, portrait.selected_at, request.status
            from private.custom_character_portraits portrait
            left join private.ai_requests request on request.user_id = ${userId} and request.idempotency_key = portrait.action_key
            where portrait.purchase_id = ${purchaseId} for update of portrait`;
        const chosen = portraits.find((portrait) => portrait.id === candidateId);
        if (!chosen) throw new ApiError(404, "not_found", "Portrait not found");
        const selected = portraits.find((portrait) => portrait.selected_at !== null);
        if (selected?.id === candidateId) return;
        if (selected)
            throw new ApiError(409, "character_portrait_chosen", "You already chose a portrait for this character");
        if (chosen.status !== "completed")
            throw new ApiError(409, "character_portrait_not_ready", "This portrait is not ready yet");
        await sql`update private.custom_character_portraits set selected_at = now() where id = ${candidateId}`;
    });
}

/** Claims a "character ready" push once. Returns false when it was already claimed or the owner muted pushes. */
export async function claimCustomCharacterPush(
    userId: string,
    purchaseId: string,
    milestone: "portraits" | "poses",
    database: Sql = createDatabaseClient(),
) {
    const [claimed] = milestone === "portraits"
        ? await database`update private.custom_character_purchases set portraits_notified_at = now()
            where id = ${purchaseId} and portraits_notified_at is null returning id`
        : await database`update private.custom_character_purchases set poses_notified_at = now()
            where id = ${purchaseId} and poses_notified_at is null returning id`;
    if (!claimed) return false;
    const [preferences] = await database`select enabled from private.notification_preferences where user_id = ${userId}`;
    return preferences?.enabled !== false;
}

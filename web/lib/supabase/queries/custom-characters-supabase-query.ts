import { randomUUID } from "node:crypto";
import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import { readSpecialStore } from "@/lib/supabase/queries/specials-supabase-query";
import { customCharacterProductId, type AppleCustomCharacterTransaction } from "@/lib/types/apple/custom-character-purchase";
import {
    customCharacterAttemptSchema,
    customCharacterClaimResultSchema,
    customCharacterConfigurationSchema,
    customCharacterPurchaseRowSchema,
    customCharacterStoreSchema,
    type CustomCharacterAdvanceRequest,
    type CustomCharacterAttempt,
    type CustomCharacterStage,
} from "@/lib/types/ai/custom-character";

/** Apple account tokens are shared with Specials; only this purchase flag controls new character checkout. */
export async function readCustomCharacterStore(
    userId: string,
    database: Sql = createDatabaseClient(),
) {
    const account = await readSpecialStore(userId, database);
    const configuration = customCharacterConfigurationSchema.safeParse({
        enabled: process.env.APPLE_CUSTOM_CHARACTERS_ENABLED,
    });
    if (!configuration.success)
        throw new ApiError(503, "config", "Custom character purchases are not configured");
    const purchases = customCharacterPurchaseRowSchema.array().parse(
        await database`select * from private.custom_character_purchases
            where account_id = ${account.app_account_token} order by created_at desc`,
    );
    const attempts = customCharacterAttemptSchema.array().parse(
        await database`select resource_id, id as request_id, workflow, status, next_poll_at
            from private.ai_requests where resource_id in (
                select id from private.custom_character_purchases where account_id = ${account.app_account_token}
            ) order by created_at desc`,
    );
    const latest = new Map<string, CustomCharacterAttempt>();
    for (const attempt of attempts) {
        const key = `${attempt.resource_id}:${attempt.workflow}`;
        if (!latest.has(key)) latest.set(key, attempt);
    }
    const characters = purchases.map((purchase) => {
        const avatar = latest.get(`${purchase.id}:avatar`);
        const fitness = latest.get(`${purchase.id}:fitness`);
        const current = fitness ?? avatar;
        const stage = fitness || avatar?.status === "completed" ? "fitness" : "portrait";
        const status = purchase.revoked_at
            ? "refunded"
            : fitness?.status === "completed"
              ? "complete"
              : current?.status === "start_unconfirmed"
                ? "needs_support"
                : current?.status === "failed" || current?.status === "cancelled"
                  ? "retryable"
                  : purchase.description === null
                    ? "ready"
                    : "generating";
        return {
            id: purchase.id,
            description: purchase.description,
            stage: status === "ready" || status === "refunded" ? null : stage,
            status,
            request_id: current?.request_id ?? null,
            poll_after_seconds: status === "generating"
                ? Math.max(3, Math.ceil(((current?.next_poll_at.getTime() ?? Date.now()) - Date.now()) / 1000))
                : null,
        };
    });
    return customCharacterStoreSchema.parse({
        app_account_token: account.app_account_token,
        environment: account.environment,
        purchases_enabled: configuration.data.enabled === "true",
        product_id: customCharacterProductId,
        characters,
    });
}

/** Apple is the payment authority; a transaction ID can fund only one character in one account. */
export async function recordCustomCharacterTransaction(
    transaction: AppleCustomCharacterTransaction,
    database: Sql = createDatabaseClient(),
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
        const saved = customCharacterPurchaseRowSchema.parse(purchase);
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
        if (purchase.description === null) {
            if (!input.description)
                throw new ApiError(400, "validation", "Describe your character before generating");
            const [saved] = await sql`update private.custom_character_purchases
                set description = ${input.description}, avatar_action_key = ${randomUUID()}
                where id = ${purchaseId} returning *`;
            purchase = customCharacterPurchaseRowSchema.parse(saved);
        } else if (input.description && input.description !== purchase.description) {
            throw new ApiError(409, "ai_request_conflict", "This purchase already has a character description");
        }
        const description = purchase.description;
        if (description === null) throw new Error("Character description was not saved");
        const attempts = customCharacterAttemptSchema.array().parse(
            await sql`select resource_id, id as request_id, workflow, status, next_poll_at
                from private.ai_requests where resource_id = ${purchaseId} order by created_at desc`,
        );
        const avatar = attempts.find((item) => item.workflow === "avatar");
        const fitness = attempts.find((item) => item.workflow === "fitness");
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

/** Background reconciliation resumes a stage whose inputs were saved but provider start was interrupted. */
export async function dueCustomCharacterPurchases(database: Sql = createDatabaseClient()) {
    const rows = await database`select purchase.id, account.user_id from private.custom_character_purchases purchase
        join private.special_accounts account on account.id = purchase.account_id
        where purchase.description is not null and purchase.revoked_at is null and account.user_id is not null
            and not exists (select 1 from private.ai_requests request
                where request.resource_id = purchase.id and request.workflow = 'fitness')
            and (not exists (select 1 from private.ai_requests request where request.resource_id = purchase.id)
                or exists (select 1 from private.ai_requests request
                    where request.resource_id = purchase.id and request.workflow = 'avatar' and request.status = 'completed'))
        order by purchase.updated_at, purchase.id limit 4`;
    return rows.map((row) => ({ id: String(row.id), userId: String(row.user_id) }));
}

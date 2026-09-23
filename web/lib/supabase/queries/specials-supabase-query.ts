import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    appleSpecialProductIds,
    applePurchaseEnvironmentSchema,
    type AppleSpecialTransaction,
} from "@/lib/types/apple/special-purchase";
import {
    specialAccountSchema,
    specialEditionSchema,
    specialStoreSchema,
    specialTransactionRecordSchema,
    specialsConfigurationSchema,
    type SpecialCheckoutRequest,
    type SpecialClaimResult,
    type SpecialStore,
} from "@/lib/types/companions/specials";

/** The shelf comes exclusively from deployment configuration, never a client header. */
export async function readSpecialStore(
    userId: string,
    database: Sql = createDatabaseClient(),
): Promise<SpecialStore> {
    const configured = specialsConfigurationSchema.safeParse({
        environment: process.env.APPLE_IAP_ENVIRONMENT,
        enabled: process.env.APPLE_SPECIALS_ENABLED,
        reviewers: process.env.APPLE_IAP_REVIEW_USER_IDS,
    });
    if (!configured.success)
        throw new ApiError(
            503,
            "config",
            "Special purchases are not configured",
        );
    const configuration = configured.data;
    return database.begin(async (sql) => {
        const profiles =
            await sql`select id from public.profiles where id = ${userId} and deleted_at is null for key share`;
        if (!profiles.length)
            throw new ApiError(
                401,
                "profile_missing",
                "Invalid or deleted account",
            );
        // NOTE: unpaid holds lapse after 30 minutes so abandoned checkouts cannot strand a Special.
        // A reserved row's updated_at is its reservation time; resuming the same checkout restarts it.
        await sql`
            update private.special_editions set state = 'available', account_id = null, attempt_id = null
            where id in (
                select id from private.special_editions
                where state = 'reserved' and updated_at < now() - interval '30 minutes'
                order by environment, companion_id for update skip locked
            )
        `;
        // NOTE: App Review buys in Sandbox against production. Only configured review accounts use that shelf.
        const environment =
            configuration.environment === "Production" &&
            configuration.reviewers.includes(userId.toLowerCase())
                ? "Sandbox"
                : configuration.environment;
        await sql`
            insert into private.special_accounts (user_id, environment) values (${userId}, ${environment})
            on conflict (user_id) do nothing
        `;
        await sql`
            update private.special_accounts as account set environment = ${environment}
            where user_id = ${userId} and environment <> ${environment}
                and not exists (select 1 from private.special_editions where account_id = account.id)
                and not exists (select 1 from private.special_transactions where account_id = account.id)
        `;
        const [row] =
            await sql`select id, user_id, environment from private.special_accounts where user_id = ${userId}`;
        const account = specialAccountSchema.parse(row);
        if (
            account.environment !== configuration.environment &&
            account.environment !== "Sandbox"
        )
            throw new ApiError(
                503,
                "config",
                "Purchase environment changed for this account",
            );
        const editions = (
            await sql`select * from private.special_editions where environment = ${account.environment}`
        ).map((edition) => specialEditionSchema.parse(edition));
        const conflicts = await sql`
            select outcome, transaction_id, companion_id from private.special_transactions
            where account_id = ${account.id} and outcome = 'conflict'
        `;
        const productIds = new Map(
            [...appleSpecialProductIds].map(([product, companion]) => [
                companion,
                product,
            ]),
        );
        return specialStoreSchema.parse({
            app_account_token: account.id,
            environment: account.environment,
            purchases_enabled: configuration.enabled === "true",
            editions: editions.map((edition) => ({
                id: edition.companion_id,
                product_id: productIds.get(edition.companion_id),
                status:
                    edition.account_id === account.id
                        ? edition.state === "owned"
                            ? "yours"
                            : edition.state === "revoked"
                              ? "refunded"
                              : "reserved"
                        : edition.state === "available"
                          ? "available"
                          : "taken",
            })),
            conflicts,
        });
    });
}

/** Holds lapse after 30 minutes without a verified charge; see readSpecialStore. */
export async function specialCheckout(
    userId: string,
    input: SpecialCheckoutRequest,
    database: Sql = createDatabaseClient(),
): Promise<void> {
    const store = await readSpecialStore(userId, database);
    if (input.action === "reserve" && !store.purchases_enabled)
        throw new ApiError(
            503,
            "special_unavailable",
            "Special purchases are not available yet",
        );
    await database.begin(async (sql) => {
        const profiles =
            await sql`select id from public.profiles where id = ${userId} and deleted_at is null for update`;
        if (!profiles.length)
            throw new ApiError(
                401,
                "profile_missing",
                "Invalid or deleted account",
            );
        const [locked] =
            await sql`select environment from private.special_accounts where id = ${store.app_account_token} for update`;
        const environment = applePurchaseEnvironmentSchema.parse(
            locked.environment,
        );
        const rows = await sql`
            select * from private.special_editions where environment = ${environment}
                and (companion_id = ${input.companion_id} or account_id = ${store.app_account_token})
            order by companion_id for update
        `;
        const editions = rows.map((row) => specialEditionSchema.parse(row));
        const target = editions.find(
            (edition) => edition.companion_id === input.companion_id,
        );
        if (!target) throw new ApiError(404, "not_found", "Special not found");
        if (input.action === "cancel") {
            if (
                target.state === "reserved" &&
                target.account_id === store.app_account_token &&
                target.attempt_id === input.attempt_id
            ) {
                await sql`update private.special_editions set state = 'available', account_id = null, attempt_id = null where id = ${target.id}`;
            }
            return;
        }
        const existing = editions.find(
            (edition) => edition.account_id === store.app_account_token,
        );
        if (existing) {
            if (
                existing.id === target.id &&
                existing.state === "reserved" &&
                existing.attempt_id === input.attempt_id
            ) {
                await sql`update private.special_editions set updated_at = now() where id = ${existing.id}`;
                return;
            }
            throw new ApiError(
                409,
                "special_limit",
                "You already own a Special or have a purchase in progress",
            );
        }
        if (target.state !== "available")
            throw new ApiError(
                409,
                "companion_taken",
                "That Special is no longer available",
            );
        await sql`
            update private.special_editions set state = 'reserved', account_id = ${store.app_account_token}, attempt_id = ${input.attempt_id}
            where id = ${target.id}
        `;
    });
}

/** Persists every verified charge, including conflicts, before reporting its outcome. */
export async function recordSpecialTransaction(
    transaction: AppleSpecialTransaction,
    database: Sql = createDatabaseClient(),
): Promise<SpecialClaimResult> {
    return database.begin(async (sql) => {
        // Serialize first delivery too, before there is a transaction row to lock.
        await sql`select pg_advisory_xact_lock(hashtextextended(${transaction.environment + ":" + transaction.originalTransactionId}, 0))`;
        const [owner] =
            await sql`select id, user_id, environment from private.special_accounts where id = ${transaction.appAccountToken}`;
        if (!owner)
            throw new ApiError(
                409,
                "special_account",
                "Purchase belongs to a different FitFight account",
            );
        const account = specialAccountSchema.parse(owner);
        // Profile, account, then editions is also the deletion/equip lock order.
        if (account.user_id)
            await sql`select id from public.profiles where id = ${account.user_id} for update`;
        const [locked] =
            await sql`select environment from private.special_accounts where id = ${account.id} for update`;
        if (locked.environment !== transaction.environment)
            throw new ApiError(
                403,
                "forbidden",
                "Purchase environment does not match the account",
            );
        const editions = (
            await sql`
            select * from private.special_editions where environment = ${transaction.environment}
                and (companion_id = ${transaction.companionId} or account_id = ${account.id})
            order by companion_id for update
        `
        ).map((row) => specialEditionSchema.parse(row));
        const edition = editions.find(
            (row) => row.companion_id === transaction.companionId,
        );
        if (!edition) throw new ApiError(404, "not_found", "Special not found");
        const previousRows = (
            await sql`
            select outcome, transaction_id, companion_id, signed_at, account_id, original_transaction_id
            from private.special_transactions where environment = ${transaction.environment}
                and (original_transaction_id = ${transaction.originalTransactionId} or transaction_id = ${transaction.transactionId})
            order by signed_at desc for update
        `
        ).map((row) => specialTransactionRecordSchema.parse(row));
        if (
            previousRows.some(
                (row) =>
                    row.account_id !== account.id ||
                    row.companion_id !== transaction.companionId ||
                    row.original_transaction_id !==
                        transaction.originalTransactionId,
            )
        ) {
            throw new ApiError(
                409,
                "special_account",
                "Purchase is already bound to another account or Special",
            );
        }
        const previous = previousRows[0];
        const stale =
            previous &&
            (previous.signed_at.getTime() > transaction.signedDate ||
                (previous.signed_at.getTime() === transaction.signedDate &&
                    previous.outcome === "refunded"));
        const revoked =
            transaction.revocationDate !== undefined ||
            transaction.revocationType !== undefined ||
            (transaction.revocationPercentage !== undefined &&
                transaction.revocationPercentage > 0);
        const belongs =
            edition.account_id === account.id &&
            (edition.original_transaction_id === null ||
                edition.original_transaction_id ===
                    transaction.originalTransactionId);
        const hasAnother = editions.some(
            (row) => row.account_id === account.id && row.id !== edition.id,
        );
        const assignable =
            !hasAnother &&
            (belongs ||
                (edition.state === "available" && (!revoked || !previous)));
        const outcome = stale
            ? previous.outcome
            : revoked
              ? "refunded"
              : assignable
                ? "owned"
                : "conflict";
        const written = await sql`
            insert into private.special_transactions (environment, transaction_id, original_transaction_id, account_id, companion_id, outcome, signed_at, purchase_at, evidence)
            values (${transaction.environment}, ${transaction.transactionId}, ${transaction.originalTransactionId}, ${account.id}, ${transaction.companionId}, ${outcome}, ${new Date(transaction.signedDate)}, ${new Date(transaction.purchaseDate)}, ${sql.json(transaction)})
            on conflict (environment, transaction_id) do update set outcome = excluded.outcome, signed_at = excluded.signed_at, evidence = excluded.evidence
            where private.special_transactions.account_id = excluded.account_id
                and private.special_transactions.companion_id = excluded.companion_id
                and private.special_transactions.original_transaction_id = excluded.original_transaction_id
                and private.special_transactions.signed_at <= excluded.signed_at
            returning id
        `;
        if (!written.length && !stale)
            throw new ApiError(
                409,
                "special_account",
                "Purchase binding changed",
            );
        if (!stale && assignable) {
            await sql`
                update private.special_editions set state = ${revoked ? "revoked" : "owned"}, account_id = ${account.id},
                    original_transaction_id = ${transaction.originalTransactionId}, attempt_id = null where id = ${edition.id}
            `;
        }
        if (!stale && revoked && belongs && account.user_id) {
            await sql`update public.profiles set companion_id = null, companion_prompt = null where id = ${account.user_id} and companion_id = ${transaction.companionId}`;
        }
        return {
            outcome,
            transaction_id: transaction.transactionId,
            companion_id: transaction.companionId,
        };
    });
}

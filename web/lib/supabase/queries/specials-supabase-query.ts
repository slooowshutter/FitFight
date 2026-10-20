import type { Sql } from "postgres";
import { ApiError } from "@/lib/http";
import { appReleasePolicy } from "@/lib/releases/app-release";
import { createDatabaseClient } from "@/lib/supabase/postgres";
import {
    appleSpecialProductIds,
    specialProductId,
    type AppleSpecialConsumableTransaction,
    type AppleSpecialTransaction,
    type ApplePurchaseEnvironment,
} from "@/lib/types/apple/special-purchase";
import {
    limitedCompanionIdValues,
    specialCompanionIdSchema,
    specialCompanionIdValues,
    type LimitedCompanionId,
} from "@/lib/types/companions/companion";
import {
    specialAccountSchema,
    specialEditionSchema,
    specialPurchaseRowSchema,
    specialStoreSchema,
    specialTransactionRecordSchema,
    specialsConfigurationSchema,
    type SpecialClaimResult,
    type SpecialStore,
} from "@/lib/types/companions/specials";

/**
 * The shelf comes from deployment configuration. `charge` is set only while claiming, to the environment the charge
 * names; the charge is then verified against the returned shelf, so a false claim only moves the caller's own account:
 * to Sandbox while it has no purchase, and on production only while a build is in review. A Production charge moves an
 * account off the Sandbox shelf even after Sandbox purchases, or a real payment could never be claimed.
 */
export async function readSpecialStore(
    userId: string,
    database: Sql = createDatabaseClient(),
    charge?: ApplePurchaseEnvironment,
): Promise<SpecialStore> {
    const configured = specialsConfigurationSchema.safeParse({
        environment: process.env.APPLE_IAP_ENVIRONMENT,
    });
    if (!configured.success)
        throw new ApiError(
            503,
            "config",
            "Special purchases are not configured",
        );
    const configuration = configured.data;
    // NOTE: App Review signs in with its own Apple Account and buys in Sandbox against production, so production opens
    // the Sandbox shelf only while the release registry lists a build in review.
    const environment =
        charge === "Sandbox" &&
        (configuration.environment === "Sandbox" ||
            (await appReleasePolicy()).review !== null)
            ? "Sandbox"
            : configuration.environment;
    return database.begin(async (sql) => {
        const profiles =
            await sql`select id from public.profiles where id = ${userId} and deleted_at is null for key share`;
        if (!profiles.length)
            throw new ApiError(
                401,
                "profile_missing",
                "Invalid or deleted account",
            );
        await sql`
            insert into private.special_accounts (user_id, environment) values (${userId}, ${environment})
            on conflict (user_id) do nothing
        `;
        await sql`
            update private.special_accounts as account set environment = ${environment}
            where user_id = ${userId} and environment <> ${environment}
                and (${charge === "Production" && environment === "Production"}::boolean or (
                    not exists (select 1 from private.special_editions where account_id = account.id)
                    and not exists (select 1 from private.special_transactions where account_id = account.id)
                    and not exists (select 1 from private.special_purchases where account_id = account.id)
                    and not exists (select 1 from private.custom_character_purchases where account_id = account.id)
                ))
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
        // An edition owned under the one-of-a-kind model stays owned alongside consumable purchases.
        const owned = new Set(
            (
                await sql`
                    select companion_id from private.special_purchases
                    where account_id = ${account.id} and environment = ${account.environment} and revoked_at is null
                    union
                    select companion_id from private.special_editions
                    where account_id = ${account.id} and environment = ${account.environment} and state = 'owned'
                `
            ).map((row) => specialCompanionIdSchema.parse(row.companion_id)),
        );
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
        const current = new Set<string>(limitedCompanionIdValues);
        return specialStoreSchema.parse({
            app_account_token: account.id,
            environment: account.environment,
            purchases_enabled: true,
            product_id: specialProductId,
            // Retired Specials are listed only for an account that owns one.
            editions: specialCompanionIdValues
                .filter((id) => current.has(id) || owned.has(id))
                .map((id) => ({
                    id,
                    product_id: productIds.get(id),
                    status: owned.has(id) ? "yours" : "available",
                })),
            conflicts,
        });
    });
}

/**
 * Apple is the payment authority: one charge unlocks one Special for one account, and a replay returns the Special it
 * first unlocked. A notification names no Special, so it only updates a charge the app already claimed; an unclaimed
 * refund is caught when the app claims it, because the claim reads Apple's current record.
 */
export async function recordSpecialPurchase(
    transaction: AppleSpecialConsumableTransaction,
    companionId: LimitedCompanionId | undefined,
    database: Sql = createDatabaseClient(),
): Promise<SpecialClaimResult | null> {
    return database.begin(async (sql) => {
        await sql`select pg_advisory_xact_lock(hashtextextended(${transaction.environment + ":" + transaction.originalTransactionId}, 3))`;
        const [owner] =
            await sql`select id, user_id, environment from private.special_accounts where id = ${transaction.appAccountToken}`;
        if (!owner || owner.environment !== transaction.environment)
            throw new ApiError(
                409,
                "special_account",
                "Purchase belongs to another FitFight account",
            );
        const account = specialAccountSchema.parse(owner);
        // Profile, then account, is also the deletion and equip lock order.
        if (account.user_id)
            await sql`select id from public.profiles where id = ${account.user_id} for update`;
        const [locked] =
            await sql`select user_id, environment from private.special_accounts where id = ${account.id} for update`;
        if (
            locked.user_id !== account.user_id ||
            locked.environment !== transaction.environment
        )
            throw new ApiError(
                409,
                "special_account",
                "Purchase account changed",
            );
        const [previousRow] = await sql`
            select id, account_id, companion_id, transaction_id, original_transaction_id, revoked_at, signed_at
            from private.special_purchases where environment = ${transaction.environment}
                and (transaction_id = ${transaction.transactionId} or original_transaction_id = ${transaction.originalTransactionId})
            for update
        `;
        const previous =
            previousRow && specialPurchaseRowSchema.parse(previousRow);
        if (
            previous &&
            (previous.account_id !== account.id ||
                previous.transaction_id !== transaction.transactionId ||
                previous.original_transaction_id !==
                    transaction.originalTransactionId)
        )
            throw new ApiError(
                409,
                "special_account",
                "Purchase is already bound to another account",
            );
        const revoked =
            transaction.revocationDate !== undefined ||
            transaction.revocationType !== undefined ||
            (transaction.revocationPercentage !== undefined &&
                transaction.revocationPercentage > 0);
        const revokedAt = revoked
            ? new Date(transaction.revocationDate ?? transaction.signedDate)
            : null;
        let saved = previous;
        if (!previous) {
            if (!companionId) return null;
            const [inserted] = await sql`
                insert into private.special_purchases
                    (account_id, environment, companion_id, transaction_id, original_transaction_id, revoked_at, signed_at, purchase_at, evidence)
                values (${account.id}, ${transaction.environment}, ${companionId}, ${transaction.transactionId},
                    ${transaction.originalTransactionId}, ${revokedAt}, ${new Date(transaction.signedDate)},
                    ${new Date(transaction.purchaseDate)}, ${sql.json(transaction)})
                returning id, account_id, companion_id, transaction_id, original_transaction_id, revoked_at, signed_at
            `;
            saved = specialPurchaseRowSchema.parse(inserted);
        } else if (previous.signed_at.getTime() <= transaction.signedDate) {
            const [updated] = await sql`
                update private.special_purchases set revoked_at = ${revokedAt}, signed_at = ${new Date(transaction.signedDate)},
                    evidence = ${sql.json(transaction)}
                where id = ${previous.id}
                returning id, account_id, companion_id, transaction_id, original_transaction_id, revoked_at, signed_at
            `;
            saved = specialPurchaseRowSchema.parse(updated);
        }
        if (!saved) throw new Error("Special purchase was not saved");
        // The same Special may be owned twice, or under the old model, so a refund unequips only the last ownership.
        if (saved.revoked_at && account.user_id) {
            await sql`
                update public.profiles set companion_id = null, companion_prompt = null
                where id = ${account.user_id} and companion_id = ${saved.companion_id}
                    and not exists (
                        select 1 from private.special_purchases where account_id = ${account.id}
                            and environment = ${transaction.environment} and companion_id = ${saved.companion_id}
                            and revoked_at is null
                    )
                    and not exists (
                        select 1 from private.special_editions where account_id = ${account.id}
                            and environment = ${transaction.environment} and companion_id = ${saved.companion_id}
                            and state = 'owned'
                    )
            `;
        }
        return {
            outcome: saved.revoked_at ? "refunded" : "owned",
            transaction_id: transaction.transactionId,
            companion_id: saved.companion_id,
        };
    });
}

/** Legacy one-of-a-kind products only. Persists every verified charge, including conflicts, before reporting its outcome. */
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
                (edition.retired_at === null &&
                    edition.state === "available" &&
                    (!revoked || !previous)));
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

import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import { appleSpecialTransactionSchema } from "@/lib/types/apple/special-purchase";
import {
    specialCheckout,
    readSpecialStore,
    recordSpecialTransaction,
} from "./specials-supabase-query";
import { readProfile, updateProfile } from "./profiles-supabase-query";
import { deleteAccount } from "./delete-account-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
process.env.APPLE_SPECIALS_ENABLED = "true";
const database = postgres(env.DATABASE_URL, { max: 5 });
const admin = createClient(
    env.SUPABASE_TEST_URL,
    env.SUPABASE_TEST_SERVICE_KEY,
    { auth: { persistSession: false, autoRefreshToken: false } },
);
after(() => database.end());

async function specialUsers(context: TestContext, count = 2) {
    const users: string[] = [];
    const accounts: string[] = [];
    context.after(async () => {
        await database`delete from private.special_transactions where account_id in ${database(accounts)}`;
        await database`update private.special_editions set account_id = null, state = 'available', attempt_id = null, original_transaction_id = null where account_id in ${database(accounts)}`;
        await database`delete from private.special_accounts where id in ${database(accounts)}`;
        await database`delete from auth.users where id in ${database(users)}`;
    });
    for (let index = 0; index < count; index++) {
        const id = randomUUID();
        users.push(id);
        await database`insert into auth.users (id) values (${id})`;
        accounts.push((await readSpecialStore(id, database)).app_account_token);
    }
    return { users, accounts };
}

function receipt(account: string, transactionId = "200000001") {
    return appleSpecialTransactionSchema.parse({
        transactionId,
        originalTransactionId: transactionId,
        bundleId: "com.fitfight.mvp",
        productId: "com.fitfight.mvp.special.pangolin",
        environment: "Sandbox",
        type: "Non-Consumable",
        inAppOwnershipType: "PURCHASED",
        quantity: 1,
        appAccountToken: account,
        purchaseDate: 1_790_000_000_000,
        signedDate: 1_790_000_001_000,
        price: 990,
        currency: "EUR",
    });
}

test("concurrent checkouts hold one edition, release only the matching cancellation, and lapse unpaid holds", async (context) => {
    const { users } = await specialUsers(context);
    const attempts = users.map(() => randomUUID());
    const results = await Promise.allSettled(
        users.map((user, index) =>
            specialCheckout(
                user,
                {
                    action: "reserve",
                    companion_id: "limited-pangolin",
                    attempt_id: attempts[index],
                },
                database,
            ),
        ),
    );
    assert.equal(
        results.filter((result) => result.status === "fulfilled").length,
        1,
    );
    const winner = results.findIndex((result) => result.status === "fulfilled");
    const loser = 1 - winner;
    const request = {
        action: "reserve" as const,
        companion_id: "limited-pangolin" as const,
        attempt_id: attempts[winner],
    };
    await specialCheckout(users[winner], request, database);
    await assert.rejects(
        specialCheckout(
            users[winner],
            { ...request, attempt_id: randomUUID() },
            database,
        ),
        { code: "special_limit" },
    );
    await assert.rejects(
        specialCheckout(
            users[winner],
            { ...request, companion_id: "limited-platypus" },
            database,
        ),
        { code: "special_limit" },
    );
    await assert.rejects(
        specialCheckout(
            users[loser],
            { ...request, attempt_id: attempts[loser] },
            database,
        ),
        { code: "companion_taken" },
    );
    await specialCheckout(
        users[winner],
        { ...request, action: "cancel", attempt_id: randomUUID() },
        database,
    );
    assert.equal(
        (await readSpecialStore(users[winner], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "reserved",
    );
    await specialCheckout(
        users[winner],
        { ...request, action: "cancel" },
        database,
    );
    await specialCheckout(
        users[loser],
        { ...request, attempt_id: attempts[loser] },
        database,
    );
    await database`update private.special_editions set updated_at = now() - interval '31 minutes' where companion_id = 'limited-pangolin' and environment = 'Sandbox'`;
    assert.equal(
        (await readSpecialStore(users[loser], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "available",
        "An unpaid hold lapses after 30 minutes",
    );
    await specialCheckout(
        users[winner],
        { ...request, attempt_id: randomUUID() },
        database,
    );
});

test("verified ownership survives switching and repeats; conflicting charges are durably recorded", async (context) => {
    const { users, accounts } = await specialUsers(context);
    const transaction = receipt(accounts[0]);
    await assert.rejects(
        updateProfile(users[0], { companion_id: "limited-pangolin" }, admin),
        { code: "special_purchase_required" },
    );
    await assert.rejects(
        database`update public.profiles set companion_id = 'limited-pangolin' where id = ${users[0]}`,
        (error: unknown) =>
            error instanceof postgres.PostgresError &&
            error.message.includes("special_purchase_required"),
    );
    const attemptId = randomUUID();
    await specialCheckout(
        users[0],
        {
            action: "reserve",
            companion_id: "limited-pangolin",
            attempt_id: attemptId,
        },
        database,
    );
    assert.equal(
        (await recordSpecialTransaction(transaction, database)).outcome,
        "owned",
    );
    await recordSpecialTransaction(transaction, database);
    await updateProfile(users[0], { companion_id: "limited-pangolin" }, admin);
    assert.equal(
        (await readProfile(users[0], admin)).companion_id,
        "limited-pangolin",
    );
    await updateProfile(
        users[0],
        { display_name: "Legacy profile edit" },
        admin,
    );
    await updateProfile(
        users[0],
        { companion_id: "fox", companion_prompt: null },
        admin,
    );
    assert.equal(
        (await readSpecialStore(users[0], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "yours",
    );
    assert.equal(
        (await readSpecialStore(users[1], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "taken",
    );
    await specialCheckout(
        users[0],
        {
            action: "cancel",
            companion_id: "limited-pangolin",
            attempt_id: attemptId,
        },
        database,
    );
    assert.equal(
        (await readSpecialStore(users[0], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "yours",
    );
    const conflict = await recordSpecialTransaction(
        receipt(accounts[1], "200000002"),
        database,
    );
    assert.equal(conflict.outcome, "conflict");
    assert.equal(
        (await readSpecialStore(users[1], database)).conflicts.length,
        1,
    );
    await assert.rejects(
        updateProfile(users[1], { companion_id: "limited-pangolin" }, admin),
        { code: "special_purchase_required" },
    );
    const secondAnimal = appleSpecialTransactionSchema.parse({
        ...transaction,
        transactionId: "200000003",
        originalTransactionId: "200000003",
        productId: "com.fitfight.mvp.special.platypus",
    });
    assert.equal(
        (await recordSpecialTransaction(secondAnimal, database)).outcome,
        "conflict",
    );
    const rows =
        await database`select id from private.special_transactions where account_id = ${accounts[0]} and transaction_id = ${transaction.transactionId}`;
    assert.equal(rows.length, 1);
});

test("refunds, stale delivery, reversal, and deletion cannot resell an edition", async (context) => {
    const { users, accounts } = await specialUsers(context);
    const transaction = receipt(accounts[0]);
    await recordSpecialTransaction(transaction, database);
    await updateProfile(users[0], { companion_id: "limited-pangolin" }, admin);
    const refunded = {
        ...transaction,
        signedDate: transaction.signedDate + 2000,
        revocationDate: transaction.signedDate + 1000,
    };
    await recordSpecialTransaction(refunded, database);
    await recordSpecialTransaction(refunded, database);
    assert.equal((await readProfile(users[0], admin)).companion_id, null);
    assert.equal(
        (await recordSpecialTransaction(transaction, database)).outcome,
        "refunded",
    );
    await assert.rejects(
        specialCheckout(
            users[1],
            {
                action: "reserve",
                companion_id: "limited-pangolin",
                attempt_id: randomUUID(),
            },
            database,
        ),
        { code: "companion_taken" },
    );
    await recordSpecialTransaction(
        { ...transaction, signedDate: refunded.signedDate + 1000 },
        database,
    );
    assert.equal(
        (await readSpecialStore(users[0], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "yours",
    );
    assert.equal(
        (await readProfile(users[0], admin)).companion_id,
        null,
        "A refund reversal must not override the user's chosen profile animal",
    );
    await deleteAccount(users[0], database);
    const [account] =
        await database`select user_id from private.special_accounts where id = ${accounts[0]}`;
    assert.equal(account.user_id, null);
    assert.equal(
        (await readSpecialStore(users[1], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "taken",
    );
    await assert.rejects(
        specialCheckout(
            users[1],
            {
                action: "reserve",
                companion_id: "limited-pangolin",
                attempt_id: randomUUID(),
            },
            database,
        ),
        { code: "companion_taken" },
    );
});

test("disabled sales and payment environments cannot be bypassed by client input", async (context) => {
    const { users, accounts } = await specialUsers(context, 1);
    process.env.APPLE_SPECIALS_ENABLED = "false";
    try {
        await assert.rejects(
            specialCheckout(
                users[0],
                {
                    action: "reserve",
                    companion_id: "limited-pangolin",
                    attempt_id: randomUUID(),
                },
                database,
            ),
            { code: "special_unavailable" },
        );
    } finally {
        process.env.APPLE_SPECIALS_ENABLED = "true";
    }
    await assert.rejects(
        recordSpecialTransaction(
            { ...receipt(accounts[0]), environment: "Production" },
            database,
        ),
        { code: "forbidden" },
    );
    await recordSpecialTransaction(receipt(accounts[0]), database);
    const [production] =
        await database`select state from private.special_editions where environment = 'Production' and companion_id = 'limited-pangolin'`;
    assert.equal(production.state, "available");
    await assert.rejects(
        database.begin(async (sql) => {
            await sql`set local role authenticated`;
            await sql`select * from private.special_transactions`;
        }),
        (error: unknown) =>
            error instanceof postgres.PostgresError && error.code === "42501",
    );
});

test("a simultaneous cancellation and verified charge cannot leave a paid edition available", async (context) => {
    const { users, accounts } = await specialUsers(context, 1);
    const attempt = {
        companion_id: "limited-pangolin" as const,
        attempt_id: randomUUID(),
    };
    await specialCheckout(
        users[0],
        { action: "reserve", ...attempt },
        database,
    );
    await Promise.all([
        specialCheckout(users[0], { action: "cancel", ...attempt }, database),
        recordSpecialTransaction(receipt(accounts[0]), database),
    ]);
    assert.equal(
        (await readSpecialStore(users[0], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "yours",
    );
});

test("refund arriving before purchase delivery retires the edition and can be reversed", async (context) => {
    const { users, accounts } = await specialUsers(context);
    const transaction = receipt(accounts[0]);
    await recordSpecialTransaction(
        { ...transaction, revocationDate: transaction.signedDate },
        database,
    );
    assert.equal(
        (await readSpecialStore(users[0], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "refunded",
    );
    await assert.rejects(
        specialCheckout(
            users[1],
            {
                action: "reserve",
                companion_id: "limited-pangolin",
                attempt_id: randomUUID(),
            },
            database,
        ),
        { code: "companion_taken" },
    );
    await recordSpecialTransaction(
        { ...transaction, signedDate: transaction.signedDate + 1000 },
        database,
    );
    assert.equal(
        (await readSpecialStore(users[0], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "yours",
    );
});

test("original and transaction identities cannot be rebound, including concurrent first delivery", async (context) => {
    const { accounts } = await specialUsers(context);
    const transaction = receipt(accounts[0]);
    const results = await Promise.allSettled([
        recordSpecialTransaction(transaction, database),
        recordSpecialTransaction(
            { ...transaction, appAccountToken: accounts[1] },
            database,
        ),
    ]);
    assert.equal(
        results.filter((result) => result.status === "fulfilled").length,
        1,
    );
    const [saved] =
        await database`select account_id from private.special_transactions where transaction_id = ${transaction.transactionId}`;
    const changedAnimal = appleSpecialTransactionSchema.parse({
        ...transaction,
        appAccountToken: saved.account_id,
        productId: "com.fitfight.mvp.special.platypus",
    });
    await assert.rejects(
        recordSpecialTransaction(changedAnimal, database),
        { code: "special_account" },
    );
    await assert.rejects(
        recordSpecialTransaction(
            {
                ...transaction,
                appAccountToken: saved.account_id,
                originalTransactionId: "999",
            },
            database,
        ),
        { code: "special_account" },
    );
});

test("a delayed notification is acknowledged without undoing a newer refund", async (context) => {
    const { accounts } = await specialUsers(context, 1);
    const transaction = receipt(accounts[0]);
    await recordSpecialTransaction(
        {
            ...transaction,
            signedDate: transaction.signedDate + 2000,
            revocationDate: transaction.signedDate + 1000,
        },
        database,
    );
    const outcome = await recordSpecialTransaction(transaction, database);
    assert.equal(outcome.outcome, "refunded");
    assert.equal(outcome.transaction_id, transaction.transactionId);
});

test("production keeps configured App Review accounts on a separate Sandbox shelf", async (context) => {
    process.env.APPLE_IAP_ENVIRONMENT = "Production";
    try {
        const { users, accounts } = await specialUsers(context);
        process.env.APPLE_IAP_REVIEW_USER_IDS = users[0].toUpperCase();
        assert.equal(
            (await readSpecialStore(users[0], database)).environment,
            "Sandbox",
            "An unused configured review account moves to the Sandbox shelf",
        );
        await specialCheckout(
            users[1],
            {
                action: "reserve",
                companion_id: "limited-pangolin",
                attempt_id: randomUUID(),
            },
            database,
        );
        process.env.APPLE_IAP_REVIEW_USER_IDS = `${users[0]}, ${users[1]}`;
        assert.equal(
            (await readSpecialStore(users[1], database)).environment,
            "Production",
            "An account with a hold or purchase never changes shelf",
        );
        process.env.APPLE_IAP_REVIEW_USER_IDS = "not-a-user-id";
        await assert.rejects(readSpecialStore(users[1], database), {
            code: "config",
        });
        process.env.APPLE_IAP_REVIEW_USER_IDS = users[0];
        assert.equal(
            (await recordSpecialTransaction(receipt(accounts[0]), database))
                .outcome,
            "owned",
        );
        await updateProfile(
            users[0],
            { companion_id: "limited-pangolin" },
            admin,
        );
        const [production] =
            await database`select state, account_id from private.special_editions where environment = 'Production' and companion_id = 'limited-pangolin'`;
        assert.deepEqual(
            { state: production.state, account_id: production.account_id },
            { state: "reserved", account_id: accounts[1] },
            "A Sandbox purchase never touches the real shelf",
        );
    } finally {
        process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
        delete process.env.APPLE_IAP_REVIEW_USER_IDS;
    }
});

test("a refund for a charge lost as a conflict never retires the Special", async (context) => {
    const { users, accounts } = await specialUsers(context, 3);
    const reserve = (user: string) =>
        specialCheckout(
            user,
            {
                action: "reserve",
                companion_id: "limited-pangolin",
                attempt_id: randomUUID(),
            },
            database,
        );
    const lapse = () =>
        database`update private.special_editions set updated_at = now() - interval '31 minutes' where companion_id = 'limited-pangolin' and environment = 'Sandbox'`;
    await reserve(users[0]);
    await lapse();
    await reserve(users[1]);
    const late = receipt(accounts[0]);
    assert.equal(
        (await recordSpecialTransaction(late, database)).outcome,
        "conflict",
    );
    await lapse();
    assert.equal(
        (await readSpecialStore(users[2], database)).editions.find(
            (row) => row.id === "limited-pangolin",
        )?.status,
        "available",
    );
    assert.equal(
        (
            await recordSpecialTransaction(
                {
                    ...late,
                    signedDate: late.signedDate + 2000,
                    revocationDate: late.signedDate + 1000,
                },
                database,
            )
        ).outcome,
        "refunded",
    );
    await reserve(users[2]);
    await specialCheckout(
        users[0],
        {
            action: "reserve",
            companion_id: "limited-platypus",
            attempt_id: randomUUID(),
        },
        database,
    );
});

test("deleting an account frees its hold, and resuming a checkout restarts its 30 minutes", async (context) => {
    const { users } = await specialUsers(context);
    const request = {
        action: "reserve" as const,
        companion_id: "limited-pangolin" as const,
        attempt_id: randomUUID(),
    };
    await specialCheckout(users[0], request, database);
    await database`update private.special_editions set updated_at = now() - interval '29 minutes' where companion_id = 'limited-pangolin' and environment = 'Sandbox'`;
    await specialCheckout(users[0], request, database);
    const [edition] =
        await database`select updated_at > now() - interval '1 minute' as fresh from private.special_editions where companion_id = 'limited-pangolin' and environment = 'Sandbox'`;
    assert.equal(edition.fresh, true);
    await deleteAccount(users[0], database);
    await specialCheckout(
        users[1],
        { ...request, attempt_id: randomUUID() },
        database,
    );
});

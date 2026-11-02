import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, test, type TestContext } from "node:test";
import { createClient } from "@supabase/supabase-js";
import postgres from "postgres";
import { databaseTestEnvironmentSchema } from "@/lib/types/testing/database";
import {
    appleSpecialConsumableTransactionSchema,
    appleSpecialTransactionSchema,
    specialProductId,
} from "@/lib/types/apple/special-purchase";
import {
    readSpecialStore,
    recordSpecialPurchase,
    recordSpecialTransaction,
} from "./specials-supabase-query";
import { resetAppReleasePolicyCacheForTests } from "@/lib/releases/app-release";
import { appReleaseProjectValues } from "@/lib/types/releases/app-release";
import { readProfile, updateProfile } from "./profiles-supabase-query";
import { deleteAccount } from "./delete-account-supabase-query";

const env = databaseTestEnvironmentSchema.parse(process.env);
process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
process.env.SUPABASE_SECRET_KEY = env.SUPABASE_TEST_SERVICE_KEY;
process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
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
        await database`delete from private.special_purchases where account_id in ${database(accounts)}`;
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

/** A legacy one-of-a-kind charge, as bought by builds before 12 Oct 2026. */
function receipt(account: string, transactionId = "200000001") {
    return appleSpecialTransactionSchema.parse({
        transactionId,
        originalTransactionId: transactionId,
        bundleId: "com.fitfight.mvp",
        productId: "com.fitfight.mvp.special.black_panther",
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

/** One charge of the shared consumable every Special is now bought with. */
function charge(account: string, transactionId: string, environment = "Sandbox") {
    return appleSpecialConsumableTransactionSchema.parse({
        transactionId,
        originalTransactionId: transactionId,
        bundleId: "com.fitfight.mvp",
        productId: specialProductId,
        environment,
        type: "Consumable",
        inAppOwnershipType: "PURCHASED",
        quantity: 1,
        appAccountToken: account,
        purchaseDate: 1_790_000_000_000,
        signedDate: 1_790_000_001_000,
        price: 990,
        currency: "EUR",
    });
}

async function status(user: string, companion: string) {
    return (await readSpecialStore(user, database)).editions.find(
        (row) => row.id === companion,
    )?.status;
}

test("the shelf offers the current roster to everyone; retired editions stay stored but unsold", async (context) => {
    const { users } = await specialUsers(context, 1);
    const store = await readSpecialStore(users[0], database);
    assert.equal(store.product_id, "com.fitfight.mvp.special");
    assert.equal(store.purchases_enabled, true);
    assert.equal(store.editions.length, 30);
    assert.ok(store.editions.every((row) => row.status === "available"));
    assert.equal(
        store.editions.find((row) => row.id === "limited-black-panther")
            ?.product_id,
        "com.fitfight.mvp.special.black_panther",
        "Older builds still decode a per-Special product ID",
    );
    assert.equal(
        store.editions.some((row) => row.id === "limited-pangolin"),
        false,
    );
    const [retired] =
        await database`select count(*)::int as count from private.special_editions where environment = 'Sandbox' and retired_at is not null`;
    assert.equal(retired.count, 40);
});

test("anyone can buy any Special: two accounts own the same one and one account owns several", async (context) => {
    const { users, accounts } = await specialUsers(context);
    await assert.rejects(
        updateProfile(
            users[0],
            { companion_id: "limited-black-panther" },
            admin,
        ),
        { code: "special_purchase_required" },
    );
    for (const [account, transactionId, companion] of [
        [accounts[0], "300000001", "limited-black-panther"],
        [accounts[1], "300000002", "limited-black-panther"],
        [accounts[0], "300000003", "limited-lone-wolf"],
    ] as const) {
        const result = await recordSpecialPurchase(
            charge(account, transactionId),
            companion,
            database,
        );
        assert.deepEqual(result, {
            outcome: "owned",
            transaction_id: transactionId,
            companion_id: companion,
        });
    }
    assert.equal(await status(users[0], "limited-black-panther"), "yours");
    assert.equal(await status(users[0], "limited-lone-wolf"), "yours");
    assert.equal(await status(users[1], "limited-black-panther"), "yours");
    assert.equal(await status(users[1], "limited-lone-wolf"), "available");
    await updateProfile(users[0], { companion_id: "limited-lone-wolf" }, admin);
    await updateProfile(
        users[0],
        { companion_id: "limited-black-panther" },
        admin,
    );
    await updateProfile(
        users[1],
        { companion_id: "limited-black-panther" },
        admin,
    );
    await assert.rejects(
        updateProfile(users[1], { companion_id: "limited-lone-wolf" }, admin),
        { code: "special_purchase_required" },
    );
    await assert.rejects(
        database`update public.profiles set companion_id = 'limited-lone-wolf' where id = ${users[1]}`,
        (error: unknown) =>
            error instanceof postgres.PostgresError &&
            error.message.includes("special_purchase_required"),
    );

    const replay = await recordSpecialPurchase(
        charge(accounts[0], "300000001"),
        "limited-tiger",
        database,
    );
    assert.equal(
        replay?.companion_id,
        "limited-black-panther",
        "A replayed charge returns the Special it first unlocked",
    );
    const [rows] =
        await database`select count(*)::int as count from private.special_purchases where account_id = ${accounts[0]}`;
    assert.equal(rows.count, 2);
    assert.equal(await status(users[0], "limited-tiger"), "available");
});

test("a refund revokes only its charge, unequips only the last ownership, and a reversal restores it", async (context) => {
    const { users, accounts } = await specialUsers(context, 1);
    const first = charge(accounts[0], "300000011");
    const second = charge(accounts[0], "300000012");
    await recordSpecialPurchase(first, "limited-tiger", database);
    await recordSpecialPurchase(second, "limited-tiger", database);
    await updateProfile(users[0], { companion_id: "limited-tiger" }, admin);
    const refund = (transaction: typeof first) => ({
        ...transaction,
        signedDate: transaction.signedDate + 2000,
        revocationDate: transaction.signedDate + 1000,
    });
    assert.equal(
        (await recordSpecialPurchase(refund(first), undefined, database))
            ?.outcome,
        "refunded",
    );
    assert.equal((await readProfile(users[0], admin)).companion_id, "limited-tiger");
    assert.equal(await status(users[0], "limited-tiger"), "yours");
    await recordSpecialPurchase(refund(second), undefined, database);
    await recordSpecialPurchase(refund(second), undefined, database);
    assert.equal((await readProfile(users[0], admin)).companion_id, null);
    assert.equal(await status(users[0], "limited-tiger"), "available");
    assert.equal(
        (await recordSpecialPurchase(second, "limited-tiger", database))
            ?.outcome,
        "refunded",
        "A delayed older record never undoes a newer refund",
    );
    await assert.rejects(
        updateProfile(users[0], { companion_id: "limited-tiger" }, admin),
        { code: "special_purchase_required" },
    );
    await recordSpecialPurchase(
        { ...second, signedDate: second.signedDate + 3000 },
        undefined,
        database,
    );
    assert.equal(await status(users[0], "limited-tiger"), "yours");
    assert.equal(
        (await readProfile(users[0], admin)).companion_id,
        null,
        "A refund reversal must not override the user's chosen profile animal",
    );
    const [kept] =
        await database`select count(*)::int as count from private.special_purchases where account_id = ${accounts[0]}`;
    assert.equal(kept.count, 2, "Refunded charges stay recorded");
});

test("a notification for an unclaimed charge changes nothing; a charge refunded before its claim is never granted", async (context) => {
    const { users, accounts } = await specialUsers(context, 1);
    const transaction = charge(accounts[0], "300000021");
    const refunded = {
        ...transaction,
        signedDate: transaction.signedDate + 2000,
        revocationDate: transaction.signedDate + 1000,
    };
    assert.equal(
        await recordSpecialPurchase(refunded, undefined, database),
        null,
    );
    const [none] =
        await database`select count(*)::int as count from private.special_purchases where account_id = ${accounts[0]}`;
    assert.equal(none.count, 0);
    assert.equal(
        (await recordSpecialPurchase(refunded, "limited-panda", database))
            ?.outcome,
        "refunded",
    );
    assert.equal(await status(users[0], "limited-panda"), "available");
});

test("a charge cannot be rebound to another account, identity or environment, including concurrent first delivery", async (context) => {
    const { accounts } = await specialUsers(context);
    const transaction = charge(accounts[0], "300000031");
    const results = await Promise.allSettled([
        recordSpecialPurchase(transaction, "limited-seal", database),
        recordSpecialPurchase(
            { ...transaction, appAccountToken: accounts[1] },
            "limited-seal",
            database,
        ),
    ]);
    assert.equal(
        results.filter((result) => result.status === "fulfilled").length,
        1,
    );
    const [saved] =
        await database`select account_id from private.special_purchases where transaction_id = ${transaction.transactionId}`;
    await assert.rejects(
        recordSpecialPurchase(
            {
                ...transaction,
                appAccountToken: saved.account_id,
                originalTransactionId: "999",
            },
            "limited-seal",
            database,
        ),
        { code: "special_account" },
    );
    await assert.rejects(
        recordSpecialPurchase(
            charge(accounts[0], "300000032", "Production"),
            "limited-seal",
            database,
        ),
        { code: "special_account" },
    );
    await assert.rejects(
        database.begin(async (sql) => {
            await sql`set local role authenticated`;
            await sql`select * from private.special_purchases`;
        }),
        (error: unknown) =>
            error instanceof postgres.PostgresError && error.code === "42501",
    );
});

test("an edition owned under the one-of-a-kind model stays owned, survives refund of a newer charge, and deletion keeps every row", async (context) => {
    const { users, accounts } = await specialUsers(context, 1);
    const legacy = receipt(accounts[0]);
    assert.equal(
        (await recordSpecialTransaction(legacy, database)).outcome,
        "owned",
    );
    assert.equal(await status(users[0], "limited-black-panther"), "yours");
    await updateProfile(
        users[0],
        { companion_id: "limited-black-panther" },
        admin,
    );
    const newer = charge(accounts[0], "300000041");
    await recordSpecialPurchase(newer, "limited-black-panther", database);
    await recordSpecialPurchase(
        {
            ...newer,
            signedDate: newer.signedDate + 2000,
            revocationDate: newer.signedDate + 1000,
        },
        undefined,
        database,
    );
    assert.equal(
        (await readProfile(users[0], admin)).companion_id,
        "limited-black-panther",
        "The legacy edition still owns the equipped Special",
    );
    await deleteAccount(users[0], database);
    const [account] =
        await database`select user_id from private.special_accounts where id = ${accounts[0]}`;
    assert.equal(account.user_id, null);
    const [purchases] =
        await database`select count(*)::int as count from private.special_purchases where account_id = ${accounts[0]}`;
    assert.equal(purchases.count, 1);
});

test("legacy charges keep their recorded outcomes and identities", async (context) => {
    const { users, accounts } = await specialUsers(context);
    const transaction = receipt(accounts[0]);
    assert.equal(
        (await recordSpecialTransaction(transaction, database)).outcome,
        "owned",
    );
    await recordSpecialTransaction(transaction, database);
    assert.equal(
        await status(users[1], "limited-black-panther"),
        "available",
        "Another account's legacy edition is never shown as taken",
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
    const changedAnimal = appleSpecialTransactionSchema.parse({
        ...transaction,
        productId: "com.fitfight.mvp.special.lone_wolf",
    });
    await assert.rejects(recordSpecialTransaction(changedAnimal, database), {
        code: "special_account",
    });
    await assert.rejects(
        recordSpecialTransaction(
            { ...transaction, environment: "Production" },
            database,
        ),
        { code: "forbidden" },
    );
    const refunded = {
        ...transaction,
        signedDate: transaction.signedDate + 2000,
        revocationDate: transaction.signedDate + 1000,
    };
    await recordSpecialTransaction(refunded, database);
    assert.equal(
        (await recordSpecialTransaction(transaction, database)).outcome,
        "refunded",
    );
    assert.equal(await status(users[0], "limited-black-panther"), "available");
});

test("production keeps App Review Sandbox charges on a separate Sandbox shelf", async (context) => {
    process.env.APPLE_IAP_ENVIRONMENT = "Production";
    process.env.NEXT_PUBLIC_SUPABASE_URL = appReleaseProjectValues[1];
    const release = { version: "1.1.3", build: 230, update_url: "https://apps.apple.com/app/id6804230516" };
    let review: typeof release | null = null;
    const realFetch = globalThis.fetch;
    context.mock.method(globalThis, "fetch", (input: RequestInfo | URL, init?: RequestInit) =>
        String(input).includes("/releases.json")
            ? Promise.resolve(
                  Response.json({
                      staging: { latest: null, review: null, enforced: false },
                      prod: { latest: null, review, enforced: false },
                  }),
              )
            : realFetch(input, init),
    );
    try {
        const { users, accounts } = await specialUsers(context);
        assert.equal(
            (await readSpecialStore(users[0], database, "Sandbox")).environment,
            "Production",
            "Without a build in review, production never opens the Sandbox shelf",
        );
        review = release;
        resetAppReleasePolicyCacheForTests();
        assert.equal(
            (await readSpecialStore(users[0], database, "Sandbox")).environment,
            "Sandbox",
            "An unused account moves to the Sandbox shelf for a Sandbox charge",
        );
        await recordSpecialPurchase(
            charge(accounts[1], "300000051", "Production"),
            "limited-lone-wolf",
            database,
        );
        assert.equal(
            (await readSpecialStore(users[1], database, "Sandbox")).environment,
            "Production",
            "An account with a purchase never changes shelf",
        );
        assert.equal(
            (
                await recordSpecialPurchase(
                    charge(accounts[0], "300000052"),
                    "limited-black-panther",
                    database,
                )
            )?.outcome,
            "owned",
        );
        assert.equal(
            (await readSpecialStore(users[0], database)).environment,
            "Sandbox",
            "A Sandbox purchase keeps the account on the Sandbox shelf",
        );
        await updateProfile(
            users[0],
            { companion_id: "limited-black-panther" },
            admin,
        );
        const [production] =
            await database`select count(*)::int as count from private.special_purchases where account_id = ${accounts[0]} and environment = 'Production'`;
        assert.equal(
            production.count,
            0,
            "A Sandbox purchase never reaches the real shelf",
        );
        assert.equal(
            (await readSpecialStore(users[0], database)).environment,
            "Sandbox",
            "Opening the store does not move a Sandbox account",
        );
        assert.equal(
            (await readSpecialStore(users[0], database, "Production")).environment,
            "Production",
            "A real charge moves an account with Sandbox purchases to the real shelf",
        );
    } finally {
        process.env.APPLE_IAP_ENVIRONMENT = "Sandbox";
        process.env.NEXT_PUBLIC_SUPABASE_URL = env.SUPABASE_TEST_URL;
        resetAppReleasePolicyCacheForTests();
    }
});

import assert from "node:assert/strict";
import {
    createHash,
    generateKeyPairSync,
    randomUUID,
    sign,
    X509Certificate,
} from "node:crypto";
import { test, type TestContext } from "node:test";
import {
    AppStoreServerAPIClient,
    SignedDataVerifier,
    VerificationException,
    VerificationStatus,
    type JWSTransactionDecodedPayload,
} from "@apple/app-store-server-library";
import { ApiError } from "@/lib/http";
import {
    appleSpecialProductIds,
    type AppleSpecialPurchaseContext,
} from "@/lib/types/apple/special-purchase";
import appleRootCertificates from "./apple-root-certificates.json";
import {
    verifySpecialPurchase,
    verifySpecialNotification,
} from "./special-purchase";

const { privateKey } = generateKeyPairSync("ec", { namedCurve: "P-256" });
process.env.APPLE_IAP_KEY_ID = "ABCDEFGHIJ";
process.env.APPLE_IAP_ISSUER_ID = "48c6ad27-cd69-4457-9d9b-395069167251";
process.env.APPLE_IAP_PRIVATE_KEY = privateKey
    .export({ type: "pkcs8", format: "pem" })
    .toString();

const expected: AppleSpecialPurchaseContext = {
    environment: "Production",
    appAccountToken: randomUUID(),
    companionId: "limited-pangolin",
};
const receipt: JWSTransactionDecodedPayload = {
    transactionId: "200000100001",
    originalTransactionId: "200000100001",
    bundleId: "com.fitfight.mvp",
    productId: "com.fitfight.mvp.special.pangolin",
    environment: "Production",
    type: "Non-Consumable",
    inAppOwnershipType: "PURCHASED",
    quantity: 1,
    appAccountToken: expected.appAccountToken.toUpperCase(),
    purchaseDate: 1_790_000_000_000,
    signedDate: 1_790_000_001_000,
    price: 4_990,
    currency: "EUR",
};

// Business cases replace only the Apple boundary; forgery cases use the real SDK.
function mockApple(
    context: TestContext,
    submitted: JWSTransactionDecodedPayload = receipt,
    current: JWSTransactionDecodedPayload = {
        ...submitted,
        signedDate: 1_790_000_002_000,
    },
) {
    const verification = context.mock.method(
        SignedDataVerifier.prototype,
        "verifyAndDecodeTransaction",
        async (signedTransaction: string) => {
            if (signedTransaction === "submitted-receipt") return submitted;
            assert.equal(signedTransaction, "current-receipt");
            return current;
        },
    );
    const lookup = context.mock.method(
        AppStoreServerAPIClient.prototype,
        "getTransactionInfo",
        async (transactionId: string) => {
            assert.equal(transactionId, submitted.transactionId);
            return { signedTransactionInfo: "current-receipt" };
        },
    );
    return { verification, lookup };
}

test("the 40 immutable Apple product IDs match the Specials collection", () => {
    assert.equal(appleSpecialProductIds.size, 40);
    assert.equal(
        appleSpecialProductIds.get("com.fitfight.mvp.special.pangolin"),
        "limited-pangolin",
    );
    assert.equal(
        appleSpecialProductIds.get("com.fitfight.mvp.special.spotted_quoll"),
        "limited-spotted-quoll",
    );
    assert.equal(
        appleSpecialProductIds.has("com.fitfight.mvp.special.spotted-quoll"),
        false,
    );
    assert.equal(new Set(appleSpecialProductIds.values()).size, 40);
});

test("bundled public roots retain their Apple fingerprints and valid CA signatures", () => {
    assert.equal(appleRootCertificates.length, 3);
    for (const root of appleRootCertificates) {
        const bytes = Buffer.from(root.der, "base64");
        const certificate = new X509Certificate(bytes);
        assert.equal(
            createHash("sha256").update(bytes).digest("hex"),
            root.sha256,
        );
        assert.match(root.source, /^https:\/\/www\.apple\.com\//);
        assert.equal(certificate.ca, true);
        assert.equal(certificate.verify(certificate.publicKey), true);
        assert.ok(Date.parse(certificate.validTo) > Date.now());
    }
});

test("the real Apple verifier rejects an attacker-signed claim with copied Apple certificates", async (context) => {
    const lookup = context.mock.method(
        AppStoreServerAPIClient.prototype,
        "getTransactionInfo",
        async () => {
            throw new Error(
                "A forged transaction must never reach the Apple API",
            );
        },
    );
    const header = Buffer.from(
        JSON.stringify({
            alg: "ES256",
            x5c: Array(3).fill(appleRootCertificates[2].der),
        }),
    ).toString("base64url");
    const payload = Buffer.from(JSON.stringify(receipt)).toString("base64url");
    const message = `${header}.${payload}`;
    const signature = sign("sha256", Buffer.from(message), {
        key: privateKey,
        dsaEncoding: "ieee-p1363",
    }).toString("base64url");

    await assert.rejects(
        verifySpecialPurchase(`${message}.${signature}`, expected),
        {
            status: 400,
            code: "validation",
        },
    );
    assert.equal(lookup.mock.callCount(), 0);
});

test("current verified payment evidence is returned with the normalized account binding", async (context) => {
    const apple = mockApple(context);
    const result = await verifySpecialPurchase("submitted-receipt", expected);
    assert.equal(result.companionId, "limited-pangolin");
    assert.equal(result.appAccountToken, expected.appAccountToken);
    assert.equal(result.signedDate, 1_790_000_002_000);
    assert.equal(result.price, 4_990);
    assert.equal(apple.verification.mock.callCount(), 2);
    assert.equal(apple.lookup.mock.callCount(), 1);
});

test("an old valid receipt returns the current refund evidence without granting ownership", async (context) => {
    mockApple(context, receipt, {
        ...receipt,
        signedDate: 1_790_000_004_000,
        revocationDate: 1_790_000_003_000,
        revocationReason: 0,
        revocationType: "REFUND_FULL",
        revocationPercentage: 100_000,
    });
    const result = await verifySpecialPurchase("submitted-receipt", expected);
    assert.equal(result.revocationDate, 1_790_000_003_000);
    assert.equal(result.revocationType, "REFUND_FULL");
    assert.equal(result.revocationPercentage, 100_000);
});

test("a refund reversal uses the current record instead of a stale refunded receipt", async (context) => {
    mockApple(
        context,
        {
            ...receipt,
            revocationDate: 1_790_000_000_500,
            revocationType: "REFUND_FULL",
        },
        { ...receipt, signedDate: 1_790_000_002_000 },
    );
    const result = await verifySpecialPurchase("submitted-receipt", expected);
    assert.equal(result.revocationDate, undefined);
    assert.equal(result.revocationType, undefined);
});

test("Sandbox evidence can only be reconciled against a Sandbox account context", async (context) => {
    mockApple(context, { ...receipt, environment: "Sandbox" });
    const result = await verifySpecialPurchase("submitted-receipt", {
        ...expected,
        environment: "Sandbox",
    });
    assert.equal(result.environment, "Sandbox");
});

for (const [name, change] of Object.entries({
    "another account": {
        appAccountToken: randomUUID(),
    },
    "another Special": { productId: "com.fitfight.mvp.special.platypus" },
    "sandbox evidence on a production account": { environment: "Sandbox" },
})) {
    test(`${name} is rejected before a server lookup`, async (context) => {
        const apple = mockApple(context, { ...receipt, ...change });
        await assert.rejects(
            verifySpecialPurchase("submitted-receipt", expected),
            { status: 403 },
        );
        assert.equal(apple.lookup.mock.callCount(), 0);
    });
}

for (const [name, change] of Object.entries({
    "unknown products": { productId: "com.fitfight.mvp.special.forged" },
    "Family Sharing": { inAppOwnershipType: "FAMILY_SHARED" },
    consumables: { type: "Consumable" },
    "multiple quantities": { quantity: 2 },
    "missing account tokens": { appAccountToken: undefined },
    "missing transaction identifiers": { transactionId: undefined },
    "unsafe transaction paths": { transactionId: "../another-transaction" },
    "missing original identifiers": { originalTransactionId: undefined },
})) {
    test(`${name} cannot enter the Special purchase path`, async (context) => {
        const apple = mockApple(context, { ...receipt, ...change });
        await assert.rejects(
            verifySpecialPurchase("submitted-receipt", expected),
            { status: 400 },
        );
        assert.equal(apple.lookup.mock.callCount(), 0);
    });
}

for (const [name, change] of Object.entries({
    "changed owner": {
        appAccountToken: randomUUID(),
    },
    "different charge": { transactionId: "200000100002" },
    "different original charge": { originalTransactionId: "200000100002" },
    "different animal": { productId: "com.fitfight.mvp.special.platypus" },
    "different environment": { environment: "Sandbox" },
    "older record": { signedDate: 1_790_000_000_000 },
})) {
    test(`a current Apple response with a ${name} cannot validate the claim`, async (context) => {
        mockApple(context, receipt, { ...receipt, ...change });
        await assert.rejects(
            verifySpecialPurchase("submitted-receipt", expected),
            { status: 409 },
        );
    });
}

test("an unavailable Apple record never falls back to the submitted receipt", async (context) => {
    const apple = mockApple(context);
    apple.lookup.mock.mockImplementation(async () => {
        throw new Error("Apple unavailable");
    });
    await assert.rejects(verifySpecialPurchase("submitted-receipt", expected), {
        status: 502,
    });
    assert.equal(apple.verification.mock.callCount(), 1);
});

test("both submitted and server-returned signatures must verify", async (context) => {
    const apple = mockApple(context);
    apple.verification.mock.mockImplementation(
        async (signedTransaction: string) => {
            if (signedTransaction === "submitted-receipt") return receipt;
            throw new VerificationException(
                VerificationStatus.INVALID_CERTIFICATE,
            );
        },
    );
    await assert.rejects(verifySpecialPurchase("submitted-receipt", expected), {
        status: 502,
    });
});

test("temporary certificate verification failures remain distinguishable from invalid purchases", async (context) => {
    const apple = mockApple(context);
    apple.verification.mock.mockImplementation(async () => {
        throw new VerificationException(
            VerificationStatus.RETRYABLE_VERIFICATION_FAILURE,
        );
    });
    await assert.rejects(verifySpecialPurchase("submitted-receipt", expected), {
        status: 503,
    });
    assert.equal(apple.lookup.mock.callCount(), 0);
});

test("missing server credentials fail closed without including secret values in the error", async (context) => {
    const previous = process.env.APPLE_IAP_ISSUER_ID;
    delete process.env.APPLE_IAP_ISSUER_ID;
    context.after(() => {
        process.env.APPLE_IAP_ISSUER_ID = previous;
    });
    await assert.rejects(
        verifySpecialPurchase("submitted-receipt", expected),
        (error: unknown) => {
            assert.ok(error instanceof ApiError);
            assert.equal(error.status, 503);
            assert.equal(error.code, "config");
            assert.equal(error.message.includes("PRIVATE KEY"), false);
            return true;
        },
    );
});

test("signed refund notifications verify the envelope and reconcile Apple's current transaction", async (context) => {
    const current = {
        ...receipt,
        signedDate: 1_790_000_002_000,
        revocationDate: 1_790_000_001_000,
    };
    const { lookup } = mockApple(context, receipt, current);
    context.mock.method(
        SignedDataVerifier.prototype,
        "verifyAndDecodeNotification",
        async () => ({
            notificationUUID: "48c6ad27-cd69-4457-9d9b-395069167251",
            notificationType: "REFUND",
            data: { signedTransactionInfo: "submitted-receipt" },
        }),
    );
    const result = await verifySpecialNotification(
        "signed-envelope",
        "Production",
    );
    assert.equal(result.transaction?.revocationDate, current.revocationDate);
    assert.equal(result.transaction?.appAccountToken, expected.appAccountToken);
    assert.equal(lookup.mock.callCount(), 1);
});

test("Apple TEST notifications do not fabricate a purchase", async (context) => {
    context.mock.method(
        SignedDataVerifier.prototype,
        "verifyAndDecodeNotification",
        async () => ({
            notificationUUID: "48c6ad27-cd69-4457-9d9b-395069167251",
            notificationType: "TEST",
        }),
    );
    const result = await verifySpecialNotification(
        "signed-test-envelope",
        "Sandbox",
    );
    assert.equal(result.transaction, null);
});

test("a valid notification envelope cannot bypass transaction signature verification", async (context) => {
    context.mock.method(
        SignedDataVerifier.prototype,
        "verifyAndDecodeNotification",
        async () => ({
            notificationUUID: "48c6ad27-cd69-4457-9d9b-395069167251",
            notificationType: "ONE_TIME_CHARGE",
            data: { signedTransactionInfo: "forged" },
        }),
    );
    await assert.rejects(
        verifySpecialNotification("signed-envelope", "Sandbox"),
    );
});

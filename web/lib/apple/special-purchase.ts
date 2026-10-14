import {
    AppStoreServerAPIClient,
    Environment,
    SignedDataVerifier,
    VerificationException,
    VerificationStatus,
} from "@apple/app-store-server-library";
import type { z } from "zod";
import { ApiError, ERROR_CODES } from "@/lib/http";
import { appleCustomCharacterTransactionSchema } from "@/lib/types/apple/custom-character-purchase";
import {
    applePurchaseCredentialsSchema,
    appleSpecialConsumableTransactionSchema,
    appleSpecialTransactionSchema,
    type AppleConsumableTransaction,
    type AppleSpecialPurchaseContext,
    type AppleSpecialTransaction,
    type ApplePurchaseEnvironment,
} from "@/lib/types/apple/special-purchase";
import { specialNotificationSchema } from "@/lib/types/companions/specials";
import appleRootCertificates from "./apple-root-certificates.json";

const verifiers = new Map<Environment, SignedDataVerifier>();

function specialVerifier(environment: Environment): SignedDataVerifier {
    let verifier = verifiers.get(environment);
    if (!verifier) {
        verifier = new SignedDataVerifier(
            appleRootCertificates.map((certificate) =>
                Buffer.from(certificate.der, "base64"),
            ),
            true,
            environment,
            "com.fitfight.mvp",
            6804230516,
        );
        verifiers.set(environment, verifier);
    }
    return verifier;
}

/** Both the notification envelope and embedded charge must pass Apple's verifier. */
export async function verifySpecialNotification(
    signedPayload: string,
    environment: ApplePurchaseEnvironment,
) {
    const verifier = specialVerifier(
        environment === "Production"
            ? Environment.PRODUCTION
            : Environment.SANDBOX,
    );
    let decoded;
    try {
        decoded = await verifier.verifyAndDecodeNotification(signedPayload);
    } catch (error) {
        if (!(error instanceof VerificationException)) throw error;
        throw new ApiError(
            error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
                ? 503
                : 400,
            "validation",
            "Apple notification could not be verified",
        );
    }
    const notification = specialNotificationSchema.parse(decoded);
    if (!notification.data?.signedTransactionInfo)
        return { notification, transaction: null };
    const decodedTransaction = await verifier.verifyAndDecodeTransaction(
        notification.data.signedTransactionInfo,
    );
    const legacy = appleSpecialTransactionSchema.safeParse(decodedTransaction);
    if (legacy.success) {
        const transaction = await verifySpecialPurchase(
            notification.data.signedTransactionInfo,
            {
                environment,
                appAccountToken: legacy.data.appAccountToken,
                companionId: legacy.data.companionId,
            },
        );
        return { notification, transaction };
    }
    const special = appleSpecialConsumableTransactionSchema.safeParse(decodedTransaction);
    if (special.success) {
        const transaction = await verifySpecialConsumablePurchase(
            notification.data.signedTransactionInfo,
            { environment, appAccountToken: special.data.appAccountToken },
        );
        return { notification, transaction };
    }
    const character = appleCustomCharacterTransactionSchema.safeParse(decodedTransaction);
    if (character.success) {
        const transaction = await verifyCustomCharacterPurchase(
            notification.data.signedTransactionInfo,
            { environment, appAccountToken: character.data.appAccountToken },
        );
        return { notification, transaction };
    }
    throw new ApiError(400, ERROR_CODES.validation, "Not a supported FitFight purchase");
}

/**
 * Legacy one-of-a-kind products only; they are no longer sold.
 * Checks a receipt against Apple's current record, bound to server-owned context.
 * Refund evidence is returned for reconciliation, never converted into a grant.
 */
export async function verifySpecialPurchase(
    signedTransaction: string,
    expected: AppleSpecialPurchaseContext,
): Promise<AppleSpecialTransaction> {
    const credentials = applePurchaseCredentialsSchema.safeParse({
        keyId: process.env.APPLE_IAP_KEY_ID,
        issuerId: process.env.APPLE_IAP_ISSUER_ID,
        privateKey: process.env.APPLE_IAP_PRIVATE_KEY?.replace(/\\n/g, "\n"),
    });
    if (!credentials.success) {
        throw new ApiError(
            503,
            ERROR_CODES.config,
            "Apple purchases are not configured",
        );
    }
    const environment =
        expected.environment === "Production"
            ? Environment.PRODUCTION
            : Environment.SANDBOX;
    const verifier = specialVerifier(environment);

    // 1. Verify the caller's evidence before using its transaction ID with Apple.
    let decoded;
    try {
        decoded = await verifier.verifyAndDecodeTransaction(signedTransaction);
    } catch (error) {
        if (!(error instanceof VerificationException)) throw error;
        if (
            error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE
        ) {
            throw new ApiError(
                503,
                ERROR_CODES.internal,
                "Apple purchase verification is temporarily unavailable",
            );
        }
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "Apple purchase signature could not be verified",
        );
    }
    const submitted = appleSpecialTransactionSchema.safeParse(decoded);
    if (!submitted.success) {
        throw new ApiError(
            400,
            ERROR_CODES.validation,
            "Not a supported Special purchase",
        );
    }
    if (
        submitted.data.environment !== expected.environment ||
        submitted.data.companionId !== expected.companionId ||
        submitted.data.appAccountToken !==
            expected.appAccountToken.toLowerCase()
    ) {
        throw new ApiError(
            403,
            ERROR_CODES.forbidden,
            "Purchase does not match this account and Special",
        );
    }

    // 2. An authentic historical receipt can predate a refund or account recovery.
    const client = new AppStoreServerAPIClient(
        credentials.data.privateKey,
        credentials.data.keyId,
        credentials.data.issuerId,
        "com.fitfight.mvp",
        environment,
    );
    let currentResponse;
    try {
        currentResponse = await client.getTransactionInfo(
            submitted.data.transactionId,
        );
    } catch {
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            "Apple's current purchase record could not be retrieved",
        );
    }
    if (!currentResponse.signedTransactionInfo) {
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            "Apple did not return a signed purchase record",
        );
    }

    // 3. The server response must independently verify and describe the same charge.
    let currentDecoded;
    try {
        currentDecoded = await verifier.verifyAndDecodeTransaction(
            currentResponse.signedTransactionInfo,
        );
    } catch (error) {
        if (!(error instanceof VerificationException)) throw error;
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            "Apple's current purchase signature could not be verified",
        );
    }
    const current = appleSpecialTransactionSchema.safeParse(currentDecoded);
    if (!current.success) {
        throw new ApiError(
            502,
            ERROR_CODES.internal,
            "Apple returned an unsupported purchase record",
        );
    }
    if (
        current.data.transactionId !== submitted.data.transactionId ||
        current.data.originalTransactionId !==
            submitted.data.originalTransactionId ||
        current.data.productId !== submitted.data.productId ||
        current.data.environment !== expected.environment ||
        current.data.appAccountToken !==
            expected.appAccountToken.toLowerCase() ||
        current.data.signedDate < submitted.data.signedDate
    ) {
        throw new ApiError(
            409,
            ERROR_CODES.conflict,
            "Apple's current purchase record no longer matches this claim",
        );
    }
    return current.data;
}

/** Consumable purchases must be verified against Apple's current record before one character or Special is granted. */
async function verifyConsumablePurchase<Transaction extends AppleConsumableTransaction>(
    signedTransaction: string,
    expected: { environment: ApplePurchaseEnvironment; appAccountToken: string },
    schema: z.ZodType<Transaction, z.ZodTypeDef, unknown>,
): Promise<Transaction> {
    const credentials = applePurchaseCredentialsSchema.safeParse({
        keyId: process.env.APPLE_IAP_KEY_ID,
        issuerId: process.env.APPLE_IAP_ISSUER_ID,
        privateKey: process.env.APPLE_IAP_PRIVATE_KEY?.replace(/\\n/g, "\n"),
    });
    if (!credentials.success)
        throw new ApiError(503, ERROR_CODES.config, "Apple purchases are not configured");
    const environment = expected.environment === "Production" ? Environment.PRODUCTION : Environment.SANDBOX;
    const verifier = specialVerifier(environment);
    let decoded;
    try {
        decoded = await verifier.verifyAndDecodeTransaction(signedTransaction);
    } catch (error) {
        if (!(error instanceof VerificationException)) throw error;
        throw new ApiError(
            error.status === VerificationStatus.RETRYABLE_VERIFICATION_FAILURE ? 503 : 400,
            ERROR_CODES.validation,
            "Apple purchase signature could not be verified",
        );
    }
    const submitted = schema.safeParse(decoded);
    if (!submitted.success)
        throw new ApiError(400, ERROR_CODES.validation, "Not a supported FitFight purchase");
    if (submitted.data.environment !== expected.environment ||
        submitted.data.appAccountToken !== expected.appAccountToken.toLowerCase())
        throw new ApiError(403, ERROR_CODES.forbidden, "Purchase belongs to another FitFight account");
    const client = new AppStoreServerAPIClient(
        credentials.data.privateKey,
        credentials.data.keyId,
        credentials.data.issuerId,
        "com.fitfight.mvp",
        environment,
    );
    let response;
    try {
        response = await client.getTransactionInfo(submitted.data.transactionId);
    } catch {
        throw new ApiError(502, ERROR_CODES.internal, "Apple's current purchase record could not be retrieved");
    }
    if (!response.signedTransactionInfo)
        throw new ApiError(502, ERROR_CODES.internal, "Apple did not return a signed purchase record");
    let currentDecoded;
    try {
        currentDecoded = await verifier.verifyAndDecodeTransaction(response.signedTransactionInfo);
    } catch (error) {
        if (!(error instanceof VerificationException)) throw error;
        throw new ApiError(502, ERROR_CODES.internal, "Apple's current purchase signature could not be verified");
    }
    const current = schema.safeParse(currentDecoded);
    if (!current.success)
        throw new ApiError(502, ERROR_CODES.internal, "Apple returned an unsupported purchase record");
    if (current.data.transactionId !== submitted.data.transactionId ||
        current.data.originalTransactionId !== submitted.data.originalTransactionId ||
        current.data.environment !== expected.environment ||
        current.data.appAccountToken !== expected.appAccountToken.toLowerCase() ||
        current.data.signedDate < submitted.data.signedDate)
        throw new ApiError(409, ERROR_CODES.conflict, "Apple's current purchase record no longer matches this claim");
    return current.data;
}

export function verifyCustomCharacterPurchase(
    signedTransaction: string,
    expected: { environment: ApplePurchaseEnvironment; appAccountToken: string },
) {
    return verifyConsumablePurchase(signedTransaction, expected, appleCustomCharacterTransactionSchema);
}

/** The claim, not the receipt, names the Special: every Special is the same consumable product. */
export function verifySpecialConsumablePurchase(
    signedTransaction: string,
    expected: { environment: ApplePurchaseEnvironment; appAccountToken: string },
) {
    return verifyConsumablePurchase(signedTransaction, expected, appleSpecialConsumableTransactionSchema);
}

/** Unverified: only picks the shelf the charge is then verified against. */
export function claimsSandbox(signedTransaction: string) {
    try {
        const payload = Buffer.from(signedTransaction.split(".")[1], "base64url").toString();
        return JSON.parse(payload).environment === "Sandbox";
    } catch {
        return false;
    }
}

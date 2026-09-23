import { createHash } from "node:crypto";
import { openAes256Gcm, sealAes256Gcm } from "@/lib/crypto/aes-256-gcm";
import { readApnsEnvironment } from "./apns-config";

export type EncryptedApnsDeviceToken = {
    encryptedToken: string;
    encryptionIv: string;
    encryptionTag: string;
};

export function fingerprintApnsDeviceToken(token: string): string {
    return createHash("sha256").update(token, "utf8").digest("hex");
}

export function encryptApnsDeviceToken(
    token: string,
): EncryptedApnsDeviceToken {
    const environment = readApnsEnvironment();
    if (!environment) {
        throw new Error("APNS_TOKEN_ENCRYPTION_KEY is not configured");
    }
    const sealed = sealAes256Gcm(token, environment.tokenEncryptionKey);
    return {
        encryptedToken: sealed.ciphertext,
        encryptionIv: sealed.iv,
        encryptionTag: sealed.tag,
    };
}

export function decryptApnsDeviceToken(
    token: EncryptedApnsDeviceToken,
): string {
    const environment = readApnsEnvironment();
    if (!environment) {
        throw new Error("APNS_TOKEN_ENCRYPTION_KEY is not configured");
    }
    return openAes256Gcm(
        {
            ciphertext: token.encryptedToken,
            iv: token.encryptionIv,
            tag: token.encryptionTag,
        },
        environment.tokenEncryptionKey,
    );
}

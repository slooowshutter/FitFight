import { createCipheriv, createDecipheriv, randomBytes } from "node:crypto";

export function sealAes256Gcm(
    plaintext: string,
    base64Key: string,
): { ciphertext: string; iv: string; tag: string } {
    const iv = randomBytes(12);
    const cipher = createCipheriv(
        "aes-256-gcm",
        Buffer.from(base64Key, "base64"),
        iv,
    );
    const ciphertext = Buffer.concat([
        cipher.update(plaintext, "utf8"),
        cipher.final(),
    ]);
    return {
        ciphertext: ciphertext.toString("base64"),
        iv: iv.toString("base64"),
        tag: cipher.getAuthTag().toString("base64"),
    };
}

export function openAes256Gcm(
    sealed: ReturnType<typeof sealAes256Gcm>,
    base64Key: string,
): string {
    const decipher = createDecipheriv(
        "aes-256-gcm",
        Buffer.from(base64Key, "base64"),
        Buffer.from(sealed.iv, "base64"),
    );
    decipher.setAuthTag(Buffer.from(sealed.tag, "base64"));
    return Buffer.concat([
        decipher.update(Buffer.from(sealed.ciphertext, "base64")),
        decipher.final(),
    ]).toString("utf8");
}

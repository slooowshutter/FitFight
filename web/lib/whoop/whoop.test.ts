import assert from "node:assert/strict";
import { createHmac, randomBytes } from "node:crypto";
import test from "node:test";
import { verifyWhoopSignature } from "@/lib/whoop/whoop";

test("verifyWhoopSignature accepts WHOOP's signature and rejects anything else", () => {
    process.env.WHOOP_CLIENT_SECRET = "test-secret";
    process.env.WHOOP_TOKEN_ENCRYPTION_KEY = randomBytes(32).toString("base64");
    const body = JSON.stringify({
        user_id: 456,
        id: "550e8400-e29b-41d4-a716-446655440000",
        type: "sleep.updated",
    });
    const timestamp = "1760000000000";
    const signature = createHmac("sha256", "test-secret")
        .update(timestamp + body)
        .digest("base64");
    const headers = (values: Record<string, string>) => new Headers(values);

    verifyWhoopSignature(
        body,
        headers({
            "X-WHOOP-Signature": signature,
            "X-WHOOP-Signature-Timestamp": timestamp,
        }),
    );
    for (const rejected of [
        { body: `${body} `, signature, timestamp },
        { body, signature, timestamp: "1760000000001" },
        {
            body,
            signature: createHmac("sha256", "other")
                .update(timestamp + body)
                .digest("base64"),
            timestamp,
        },
        { body, signature: "", timestamp },
        { body, signature, timestamp: "" },
    ]) {
        assert.throws(
            () =>
                verifyWhoopSignature(
                    rejected.body,
                    headers({
                        "X-WHOOP-Signature": rejected.signature,
                        "X-WHOOP-Signature-Timestamp": rejected.timestamp,
                    }),
                ),
            /Invalid WHOOP signature/,
        );
    }
});

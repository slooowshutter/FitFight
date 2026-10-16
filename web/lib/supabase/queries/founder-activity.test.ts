import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import { test } from "node:test";
import { runInNewContext } from "node:vm";
import { ModuleKind, transpileModule } from "typescript";
import { z } from "zod";
import { POST as RECEIVE } from "@/app/api/internal/founder-activity/route";
import { founderUserIds } from "@/lib/types/fights/founder-fight";

const require = createRequire(import.meta.url);

const batch = {
    collected_at: "2026-10-15T12:00:00Z",
    time_zone: "GMT",
    totals: [
        {
            metric: "steps",
            day: "2026-10-15",
            starts_at: "2026-10-15T00:00:00Z",
            ends_at: "2026-10-15T12:00:00Z",
            value: 4200,
            unit: "steps",
        },
    ],
};

for (const entry of [
    { user: founderUserIds.beta, copied: true },
    { user: "4f1c2a8e-6b0d-4c3e-9a7f-2d5e8b1c0a93", copied: false },
]) {
    test(`a staging activity sync by ${entry.copied ? "the founder is" : "anyone else is not"} copied to production after responding`, async () => {
        const callbacks: Array<() => Promise<void>> = [];
        const copies: Array<{ url: string; init: RequestInit }> = [];
        const exports: Record<string, unknown> = {};
        // Execute the real handler with only auth, persistence, and the network replaced.
        const { outputText } = transpileModule(
            readFileSync(
                new URL(
                    "../../../app/api/v1/healthkit/activity/route.ts",
                    import.meta.url,
                ),
                "utf8",
            ),
            { compilerOptions: { module: ModuleKind.CommonJS } },
        );
        runInNewContext(outputText, {
            exports,
            process: { env: { CRON_SECRET: "secret" } },
            fetch: async (url: string, init: RequestInit) => {
                copies.push({ url, init });
                return Response.json({ processing: "processed" });
            },
            require(specifier: string) {
                if (specifier === "next/server") {
                    return {
                        after: (callback: () => Promise<void>) =>
                            callbacks.push(callback),
                    };
                }
                if (specifier.endsWith("/auth-supabase-query")) {
                    return { verifyUser: async () => ({ userId: entry.user }) };
                }
                if (specifier.endsWith("/activity-pipeline-supabase-query")) {
                    return {
                        receiveHealthKitActivity: async () => ({
                            processing: "processed",
                        }),
                    };
                }
                if (specifier.endsWith("/referral-rewards")) {
                    return { rewardReferrals: async () => {} };
                }
                return require(specifier);
            },
        });

        const response = z.instanceof(Response).parse(
            await z.function().parse(exports.POST)(
                new Request(
                    "https://staging.fitfight.app/api/v1/healthkit/activity",
                    {
                        method: "POST",
                        headers: { "Content-Type": "application/json" },
                        body: JSON.stringify(batch),
                    },
                ),
                { params: Promise.resolve({}) },
            ),
        );

        assert.equal(response.status, 200);
        assert.equal(copies.length, 0, "The sync must not wait for production");
        await Promise.all(callbacks.map((callback) => callback()));
        assert.deepEqual(
            copies.map(({ url, init }) => ({
                url,
                authorization: new Headers(init.headers).get("authorization"),
                body: JSON.parse(String(init.body)),
            })),
            entry.copied
                ? [
                      {
                          url: "https://fitfight.app/api/internal/founder-activity",
                          authorization: "Bearer secret",
                          body: batch,
                      },
                  ]
                : [],
        );
    });
}

test("production refuses a founder activity copy without the shared secret", async () => {
    process.env.CRON_SECRET = "secret";
    const response = await RECEIVE(
        new Request("https://fitfight.app/api/internal/founder-activity", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                Authorization: "Bearer wrong",
            },
            body: JSON.stringify(batch),
        }),
        { params: Promise.resolve({}) },
    );

    assert.equal(response.status, 401);
});

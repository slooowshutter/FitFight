import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createRequire } from "node:module";
import test from "node:test";
import { runInNewContext } from "node:vm";
import { ModuleKind, transpileModule } from "typescript";
import { z } from "zod";

const require = createRequire(import.meta.url);
const userId = "11111111-1111-4111-8111-111111111111";
const fightId = "22222222-2222-4222-8222-222222222222";

for (const entry of [
    {
        route: "fights/route.ts",
        method: "POST",
        command: "createFight",
        body: {
            name: "Walk together",
            startsAt: "2026-09-17T12:00:00Z",
            endsAt: "2026-09-24T12:00:00Z",
            timeZone: "UTC",
            outcomeRule: "highest_total",
            stakeKind: "action",
        },
        response: { id: fightId, state: "live" },
        status: 201,
    },
    {
        route: "fights/[fightID]/route.ts",
        method: "PATCH",
        command: "updateFight",
        body: { name: "Updated fight" },
        response: { id: fightId, state: "live" },
        status: 200,
    },
    {
        route: "fights/[fightID]/invites/route.ts",
        method: "POST",
        command: "createInvite",
        body: { handle: "maya" },
        response: { status: "invited" },
        status: 200,
    },
    {
        route: "fights/[fightID]/suggested/route.ts",
        method: "PATCH",
        command: "setFightSuggested",
        body: { suggested: true },
        response: { suggested: true },
        status: 200,
    },
]) {
    test(`${entry.command} returns its saved response before a failing notification delivery`, async () => {
        let saved = false;
        let queued = false;
        let deliveries = 0;
        const callbacks: Array<() => Promise<void>> = [];
        const series = {
            id: fightId,
            owner_id: userId,
            name: "Walk together",
            suggested: false,
        };
        const admin = {
            from(table: string) {
                return {
                    select: () => ({
                        eq: () => ({
                            maybeSingle: async () => ({
                                data:
                                    table === "fight_series"
                                        ? series
                                        : { handle: "marc", display_name: "Marc" },
                                error: null,
                            }),
                        }),
                    }),
                    update: () => ({
                        eq: async () => {
                            saved = true;
                            return { error: null };
                        },
                    }),
                };
            },
        };

        // Execute the production handlers with only persistence, auth, and delivery boundaries replaced.
        function loadProduction(path: string): Record<string, unknown> {
            const exports: Record<string, unknown> = {};
            const source = readFileSync(
                new URL(`../../${path}`, import.meta.url),
                "utf8",
            );
            const { outputText } = transpileModule(source, {
                compilerOptions: { module: ModuleKind.CommonJS },
            });
            runInNewContext(outputText, {
                exports,
                require(specifier: string) {
                    if (specifier === "next/server") {
                        return {
                            after: (callback: () => Promise<void>) => callbacks.push(callback),
                        };
                    }
                    if (specifier.endsWith("/auth-supabase-query")) {
                        return {
                            verifyUser: async () => ({ userId }),
                            readAdminViewer: async () => ({}),
                        };
                    }
                    if (specifier.endsWith("/supabase/postgres")) {
                        return { createDatabaseClient: () => ({}) };
                    }
                    if (specifier.endsWith("/process-notification-outbox-supabase-query")) {
                        return {
                            processNotificationOutbox: async () => {
                                assert.equal(saved, true);
                                deliveries += 1;
                                throw new Error("APNs transport unavailable");
                            },
                        };
                    }
                    if (specifier.endsWith("/suggest-fight-supabase-query")) {
                        return loadProduction(
                            "lib/supabase/queries/suggest-fight-supabase-query.ts",
                        );
                    }
                    if (specifier.endsWith("/is-fitfight-admin")) {
                        return {
                            isFitFightAdmin: () => true,
                        };
                    }
                    if (specifier.endsWith("/supabase/admin")) {
                        return { createAdminClient: () => admin };
                    }
                    if (specifier.endsWith("/fight-access-supabase-query")) {
                        return { loadFight: async () => ({ series_id: fightId }) };
                    }
                    if (specifier.endsWith("/join-fight-supabase-query")) {
                        return { currentJoinableFight: async () => ({ id: fightId }) };
                    }
                    if (specifier.endsWith("/app-wide-fight-invite-supabase-query")) {
                        return { inviteEveryoneToOpenFight: async () => [userId] };
                    }
                    if (specifier.endsWith("/notification-intents-supabase-query")) {
                        return {
                            enqueueFightInviteNotifications: async () => {
                                queued = true;
                            },
                        };
                    }
                    const imported = require(specifier);
                    if (
                        [
                            "/create-fight-supabase-query",
                            "/update-fight-supabase-query",
                            "/create-invite-supabase-query",
                        ].some((name) => specifier.endsWith(name))
                    ) {
                        return {
                            ...imported,
                            [entry.command]: async () => {
                                saved = true;
                                return entry.response;
                            },
                        };
                    }
                    return imported;
                },
            });
            return exports;
        }

        const module = loadProduction(`app/api/v1/${entry.route}`);
        const handler = z.function().parse(module[entry.method]);
        const response = z.instanceof(Response).parse(
            await handler(
                new Request("https://fitfight.app/api/v1/fights", {
                    method: entry.method,
                    headers: {
                        "Content-Type": "application/json",
                        "Idempotency-Key": "delivery-regression",
                    },
                    body: JSON.stringify(entry.body),
                }),
                { params: Promise.resolve({ fightID: fightId }) },
            ),
        );
        assert.equal(saved, true);
        assert.equal(
            response.status,
            entry.status,
            "A saved command must not become HTTP 500",
        );
        assert.deepEqual(await response.json(), entry.response);
        assert.equal(deliveries, 0, "The response must not wait for APNs");
        if (entry.command === "setFightSuggested") assert.equal(queued, true);
        assert.equal(callbacks.length, 1);
        await assert.rejects(callbacks[0], /APNs transport unavailable/);
        assert.equal(deliveries, 1);
        assert.equal(response.status, entry.status);
    });
}

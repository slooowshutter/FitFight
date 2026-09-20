import assert from "node:assert/strict";
import { test } from "node:test";
import {
    chooseAccountToKeep,
    isDisposableGoogleAccount,
} from "./google-identity-supabase-query";

test("Google sign-in keeps one existing account when verified emails match", () => {
    assert.equal(chooseAccountToKeep([]), null);
    assert.equal(
        chooseAccountToKeep([
            {
                userId: "apple-user",
                createdAt: "2026-01-01T00:00:00.000Z",
                handle: "marc",
                handleSetAt: "2026-01-02T00:00:00.000Z",
            },
            {
                userId: "google-user",
                createdAt: "2026-09-19T18:36:00.000Z",
                handle: "user_398d1631ebc1",
                handleSetAt: null,
            },
        ]),
        "apple-user",
    );
    assert.equal(
        chooseAccountToKeep([
            {
                userId: "first",
                createdAt: "2026-01-01T00:00:00.000Z",
                handle: "user_aaaaaaaaaaaa",
                handleSetAt: "2026-01-02T00:00:00.000Z",
            },
            {
                userId: "second",
                createdAt: "2026-02-01T00:00:00.000Z",
                handle: "user_bbbbbbbbbbbb",
                handleSetAt: "2026-02-02T00:00:00.000Z",
            },
        ]),
        null,
    );
});

test("only unused generated Google accounts can be replaced during linking", () => {
    assert.equal(
        isDisposableGoogleAccount({
            otherProviders: 0,
            fightMemberships: 0,
            ownedFights: 0,
            handle: "user_398d1631ebc1",
            handleSetAt: null,
        }),
        true,
    );
    assert.equal(
        isDisposableGoogleAccount({
            otherProviders: 1,
            fightMemberships: 0,
            ownedFights: 0,
            handle: "user_398d1631ebc1",
            handleSetAt: null,
        }),
        false,
    );
    assert.equal(
        isDisposableGoogleAccount({
            otherProviders: 0,
            fightMemberships: 1,
            ownedFights: 0,
            handle: "user_398d1631ebc1",
            handleSetAt: null,
        }),
        false,
    );
    assert.equal(
        isDisposableGoogleAccount({
            otherProviders: 0,
            fightMemberships: 0,
            ownedFights: 0,
            handle: "marc",
            handleSetAt: "2026-01-02T00:00:00.000Z",
        }),
        false,
    );
});

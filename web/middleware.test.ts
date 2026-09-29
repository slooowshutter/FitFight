import assert from "node:assert/strict";
import test from "node:test";
import { NextRequest } from "next/server";
import {
    getRedirectUrl,
    getRewrittenUrl,
    unstable_doesMiddlewareMatch,
} from "next/experimental/testing/server";
import { config, middleware } from "./middleware";

const referral = "/r/8b8c3f3e-6f2e-4c55-9d7a-0f4e2b1c9a10";

function visit(path: string, headers: Record<string, string>) {
    return middleware(
        new NextRequest(`https://fitfight.app${path}`, { headers }),
    );
}

test("French browsers get French pages at the same address", () => {
    assert.equal(
        getRewrittenUrl(
            visit("/", { "accept-language": "fr-CA,fr;q=0.9,en;q=0.8" }),
        ),
        "https://fitfight.app/fr",
    );
    assert.equal(
        getRewrittenUrl(
            visit("/j/ABCD", { "accept-language": "de-DE,fr;q=0.9,en;q=0.8" }),
        ),
        "https://fitfight.app/fr/j/ABCD",
    );
});

test("English and unsupported languages keep the English page", () => {
    for (const header of [
        "en-US,en;q=0.9,fr;q=0.8",
        "de,en;q=0.8,fr;q=0.5",
        "fr;q=0,en",
        "es-ES",
        "",
    ]) {
        const response = visit("/privacy", { "accept-language": header });
        assert.equal(getRewrittenUrl(response), null, header);
        assert.equal(getRedirectUrl(response), null, header);
    }
});

test("a saved language choice beats the browser language", () => {
    assert.equal(
        getRewrittenUrl(
            visit("/support", {
                "accept-language": "fr-FR",
                cookie: "NEXT_LOCALE=en",
            }),
        ),
        null,
    );
    assert.equal(
        getRewrittenUrl(
            visit(referral, {
                "accept-language": "en-US",
                cookie: "NEXT_LOCALE=fr",
            }),
        ),
        `https://fitfight.app/fr${referral}`,
    );
});

test("the language link saves the choice and returns to the clean address", () => {
    const response = visit("/privacy?lang=fr", { "accept-language": "en-US" });

    assert.equal(getRedirectUrl(response), "https://fitfight.app/privacy");
    assert.equal(response.cookies.get("NEXT_LOCALE")?.value, "fr");
});

test("only the website pages run the language check", () => {
    for (const path of ["/", "/privacy", "/support", "/j/ABCD", referral]) {
        assert.equal(unstable_doesMiddlewareMatch({ config, url: path }), true);
    }
    for (const path of [
        "/fr",
        "/fr/privacy",
        "/api/v1/fights",
        "/.well-known/apple-app-site-association",
        "/icon.svg",
    ]) {
        assert.equal(
            unstable_doesMiddlewareMatch({ config, url: path }),
            false,
            path,
        );
    }
});

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { test } from "node:test";
import { GET } from "@/app/api/v1/alerts/route";
import { POST } from "@/app/api/v1/alerts/[alertID]/responses/route";
import { alertsFor, inAppAlerts, versionAtLeast } from "@/lib/alerts/in-app-alerts";
import {
    alertResponseRequestSchema,
    inAppAlertListSchema,
    type AlertDefinition,
    type AlertFacts,
} from "@/lib/types/alerts/in-app-alert";

const newcomer: AlertFacts = {
    appVersion: "1.2.0",
    latestRelease: null,
    daysSinceSignup: 0,
    fights: 0,
    customCharacters: 0,
    companionPicture: true,
    purchases: 0,
    friends: 0,
    stepsLast7Days: 0,
    answered: new Set(),
};

test("alerts share their response fixture with the native decoder", () => {
    const fixture = JSON.parse(
        readFileSync(new URL("../../../contracts/fixtures/in-app-alerts.json", import.meta.url), "utf8"),
    );
    assert.equal(inAppAlertListSchema.parse(fixture).alerts.length, 2);
});

test("alert ids fit the database and copy follows the house rules", () => {
    const ids = inAppAlerts.map((alert) => alert.id);
    assert.equal(new Set(ids).size, ids.length);
    for (const alert of inAppAlerts) {
        assert.match(alert.id, /^[a-z0-9][a-z0-9-]{0,79}$/);
        assert.ok(alert.buttons.length >= 1 && alert.buttons.length <= 2, alert.id);
        const copy = [alert.title, alert.body, ...alert.buttons.map((button) => button.title)];
        for (const text of copy.flatMap((item) => [item.en, item.fr])) {
            assert.ok(text.trim().length > 0, alert.id);
            assert.doesNotMatch(text, /[\u2013\u2014]/, `${alert.id} uses an en or em dash`);
        }
    }
});

test("marketing versions compare number by number", () => {
    assert.ok(versionAtLeast("1.10.0", "1.9.0"));
    assert.ok(versionAtLeast("1.2.0", "1.2.0"));
    assert.ok(!versionAtLeast("1.1.3", "1.2.0"));
});

test("rules pick alerts in order, skip answered ones, and speak the requested language", () => {
    assert.deepEqual(alertsFor(newcomer, "en", "https://fitfight.app"), []);

    const dayThree = { ...newcomer, daysSinceSignup: 3 };
    const alerts = alertsFor(dayThree, "en", "https://staging.fitfight.app");
    assert.deepEqual(alerts.map((alert) => alert.id), ["start-first-fight", "make-your-character"]);
    assert.equal(alerts[1]?.image_url, "https://staging.fitfight.app/landing/companion-alpaca-1.webp");
    assert.deepEqual(alerts[0]?.buttons.map((button) => [button.action, button.primary, button.url]), [
        ["new_fight", true, null],
        ["dismiss", false, null],
    ]);
    inAppAlertListSchema.parse({ alerts });

    const fighter = { ...dayThree, fights: 1, answered: new Set(["make-your-character"]) };
    assert.deepEqual(alertsFor(fighter, "en", "https://fitfight.app"), []);

    const [french] = alertsFor(dayThree, "fr", "https://fitfight.app");
    assert.equal(french?.title, "Lancez votre premier défi");
});

test("people without a companion picture are asked to choose one first, from 1.3.0", () => {
    const pictureless = { ...newcomer, appVersion: "1.3.0", daysSinceSignup: 3, companionPicture: false };
    const alerts = alertsFor(pictureless, "en", "https://fitfight.app");
    assert.deepEqual(alerts.map((alert) => alert.id), ["choose-your-companion", "start-first-fight", "make-your-character"]);
    assert.deepEqual(alerts[0]?.buttons.map((button) => [button.action, button.primary]), [
        ["choose_companion", true],
        ["dismiss", false],
    ]);
    assert.deepEqual(alertsFor({ ...pictureless, appVersion: "1.2.1" }, "en", "https://fitfight.app").map((alert) => alert.id), [
        "start-first-fight",
        "make-your-character",
    ]);
    assert.deepEqual(alertsFor({ ...newcomer, appVersion: "1.3.0", companionPicture: false }, "fr", "https://fitfight.app").map((alert) => alert.title), [
        "Choisissez votre compagnon",
    ]);
});

test("an update button links to Apple's installable build and hides without one", () => {
    const pitch: AlertDefinition = {
        id: "update-to-1-3-0",
        who: (facts) =>
            !versionAtLeast(facts.appVersion, "1.3.0") &&
            facts.latestRelease !== null &&
            versionAtLeast(facts.latestRelease.version, "1.3.0"),
        title: { en: "New", fr: "Nouveau" },
        body: { en: "Update.", fr: "Mettez à jour." },
        buttons: [{ title: { en: "Update", fr: "Mettre à jour" }, action: "update" }],
    };
    const latestRelease = { version: "1.3.0", updateUrl: "https://apps.apple.com/app/id6804230516" };
    assert.deepEqual(alertsFor(newcomer, "en", "https://fitfight.app", [pitch]), []);
    assert.equal(
        alertsFor({ ...newcomer, latestRelease }, "en", "https://fitfight.app", [pitch])[0]?.buttons[0]?.url,
        latestRelease.updateUrl,
    );
    assert.deepEqual(
        alertsFor({ ...newcomer, latestRelease, appVersion: "1.3.0" }, "en", "https://fitfight.app", [pitch]),
        [],
    );
});

test("responses accept known values only", () => {
    assert.ok(alertResponseRequestSchema.safeParse({ response: "shown" }).success);
    assert.ok(alertResponseRequestSchema.safeParse({ response: "tapped", action: "open_character" }).success);
    for (const input of [{}, { response: "seen" }, { response: "tapped", action: "buy" }, { response: "shown", user_id: "x" }]) {
        assert.equal(alertResponseRequestSchema.safeParse(input).success, false);
    }
});

test("reading alerts and answering them require authentication", async () => {
    const list = await GET(new Request("https://fitfight.app/api/v1/alerts"), { params: Promise.resolve({}) });
    assert.equal(list.status, 401);
    const answer = await POST(
        new Request("https://fitfight.app/api/v1/alerts/start-first-fight/responses", { method: "POST" }),
        { params: Promise.resolve({ alertID: "start-first-fight" }) },
    );
    assert.equal(answer.status, 401);
});

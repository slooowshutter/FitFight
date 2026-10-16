import assert from "node:assert/strict";
import { test } from "node:test";
import { isApnsConfigured, readApnsEnvironment } from "@/lib/apns/apns-config";
import {
    friendsResultsNotificationAlert,
    inviteNotificationAlert,
    mentionNotificationAlert,
    notificationAlert,
} from "@/lib/notifications/notification-copy";

test("APNs is not configured without server secrets", () => {
    delete process.env.APNS_KEY_ID;
    delete process.env.APNS_PRIVATE_KEY;
    delete process.env.APNS_TOKEN_ENCRYPTION_KEY;
    assert.equal(isApnsConfigured(), false);
    assert.equal(readApnsEnvironment(), null);
});

test("mention alerts name the person and stay off scores", () => {
    const alert = mentionNotificationAlert("post", "marc", "en");
    assert.equal(alert.title, "FitFight");
    assert.equal(alert.body, "@marc tagged you in a post.");
    assert.doesNotMatch(alert.body, /score/i);
    assert.doesNotMatch(alert.body, /step/i);
    assert.doesNotMatch(alert.body, /\d{3,}/);
    assert.equal(
        mentionNotificationAlert("comment", "marc", "fr").body,
        "@marc t’a mentionné dans un commentaire.",
    );
});

test("invite alerts name the person and fight and stay off scores", () => {
    const alert = inviteNotificationAlert("marc", "EVERYBODY ON THE APP", "en");
    assert.equal(alert.title, "FitFight");
    assert.equal(alert.body, "@marc invited you to EVERYBODY ON THE APP.");
    assert.doesNotMatch(alert.body, /score/i);
    assert.doesNotMatch(alert.body, /\d{3,}/);
    assert.equal(
        inviteNotificationAlert("marc", "EVERYBODY ON THE APP", "fr").body,
        "@marc t'a invité à EVERYBODY ON THE APP.",
    );
});

test("friend fight pushes batch every friend into one sync and one results alert", () => {
    assert.deepEqual(notificationAlert("friends_sync", "en"), {
        title: "Your friend fights just ended",
        body: "Open FitFight to sync your last steps.",
    });
    assert.deepEqual(notificationAlert("friends_sync", "fr"), {
        title: "Tes défis entre amis viennent de se terminer",
        body: "Ouvre FitFight pour envoyer tes derniers pas.",
    });
    assert.equal(
        friendsResultsNotificationAlert("2026-10", 7, 12, "en").title,
        "October: you won 7 of 12 friend fights",
    );
    assert.equal(
        friendsResultsNotificationAlert("2026-10", 7, 12, "fr").title,
        "Octobre : tu as gagné 7 défis entre amis sur 12",
    );
    assert.equal(
        friendsResultsNotificationAlert("2026-12", 0, 1, "en").title,
        "December: you won 0 of 1 friend fight",
    );
    assert.equal(
        friendsResultsNotificationAlert("2027-01", 1, 3, "fr").title,
        "Janvier : tu as gagné 1 défi entre amis sur 3",
    );
    for (const locale of ["en", "fr"] as const) {
        for (const alert of [
            notificationAlert("friends_sync", locale),
            notificationAlert("friends_results", locale),
            friendsResultsNotificationAlert("2026-10", 7, 12, locale),
        ]) {
            assert.doesNotMatch(alert.title + alert.body, /[\u2013\u2014]/);
        }
    }
});

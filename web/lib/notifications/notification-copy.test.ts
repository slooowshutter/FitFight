import assert from "node:assert/strict";
import { test } from "node:test";
import { isApnsConfigured, readApnsEnvironment } from "@/lib/apns/apns-config";
import {
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

test("notification copy stays generic on the lock screen", () => {
    const alert = notificationAlert("grace_6h", "en");
    assert.equal(alert.title, "FitFight");
    assert.match(alert.body, /6 hours left/i);
    assert.doesNotMatch(alert.body, /\$/);
});

test("mention alerts name the person and stay off scores", () => {
    const alert = mentionNotificationAlert("post", "Marc", "en");
    assert.equal(alert.title, "FitFight");
    assert.equal(alert.body, "Marc tagged you in a post.");
    assert.doesNotMatch(alert.body, /score/i);
    assert.doesNotMatch(alert.body, /step/i);
    assert.doesNotMatch(alert.body, /\d{3,}/);
    assert.equal(
        mentionNotificationAlert("comment", "Marc", "fr").body,
        "Marc t’a mentionné dans un commentaire.",
    );
});

test("invite alerts name the person and fight and stay off scores", () => {
    const alert = inviteNotificationAlert("Marc", "EVERYBODY ON THE APP", "en");
    assert.equal(alert.title, "FitFight");
    assert.equal(alert.body, "Marc invited you to EVERYBODY ON THE APP.");
    assert.doesNotMatch(alert.body, /score/i);
    assert.doesNotMatch(alert.body, /\d{3,}/);
    assert.equal(
        inviteNotificationAlert("Marc", "EVERYBODY ON THE APP", "fr").body,
        "Marc t'a invité à EVERYBODY ON THE APP.",
    );
});

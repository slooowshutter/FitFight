import assert from "node:assert/strict";
import test from "node:test";
import { resolveNotificationAlert } from "./resolve-notification-alert";

test("resolveNotificationAlert uses a stored social alert body", () => {
    const alert = resolveNotificationAlert({
        kind: "feed_post",
        copyKey: "feed_post",
        alertBody: "Alex posted in the feed.",
        locale: "en",
    });
    assert.equal(alert.title, "FitFight");
    assert.equal(alert.body, "Alex posted in the feed.");
});

test("resolveNotificationAlert uses custom alert body for daily status", () => {
    const alert = resolveNotificationAlert({
        kind: "daily_status",
        copyKey: "daily_status",
        alertBody: "You are pulling ahead. Keep moving.",
        locale: "en",
    });
    assert.equal(alert.title, "FitFight");
    assert.equal(alert.body, "You are pulling ahead. Keep moving.");
});

test("resolveNotificationAlert keeps static grace copy", () => {
    const alert = resolveNotificationAlert({
        kind: "grace_reminder",
        copyKey: "grace_6h",
        alertBody: null,
        locale: "en",
    });
    assert.match(alert.body, /6 hours left/);
});

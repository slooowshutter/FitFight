import assert from "node:assert/strict";
import test from "node:test";
import { defaultNotificationPreferences, notificationPreferenceKeyValues, updateNotificationPreferencesRequestSchema } from "@/lib/types/notifications/notification-preferences";

test("every notification control accepts an independent opt-out", () => {
    for (const key of notificationPreferenceKeyValues) {
        assert.deepEqual(updateNotificationPreferencesRequestSchema.parse({ [key]: false }), { [key]: false });
    }
    assert.equal(defaultNotificationPreferences.feed_post, false);
    assert.equal(defaultNotificationPreferences.daily_status, false);
    assert.equal(defaultNotificationPreferences.ending_week, false);
    assert.equal(defaultNotificationPreferences.fight_ended, false);
    assert.equal(defaultNotificationPreferences.post_reaction, true);
    assert.equal(defaultNotificationPreferences.final_sync, true);
    assert.equal(updateNotificationPreferencesRequestSchema.safeParse({ enabled: "false" }).success, false);
    assert.equal(updateNotificationPreferencesRequestSchema.safeParse({ unrelated: true }).success, false);
});

@main
struct NotificationPreferencesTests {
    static func main() throws {
        let decoder = JSONDecoder()
        let old = Data(#"{"feed_post":true,"post_comment":false,"comment_reply":true,"post_reaction":true,"challenge_reminder":false,"daily_status":true}"#.utf8)
        let legacy = try decoder.decode(LegacyNotificationPreferences.self, from: old)
        let current = try decoder.decode(FitFightNotificationPreferences.self, from: old)
        precondition(current.feedPost == legacy.feedPost && current.postComment == legacy.postComment)
        precondition(current.challengeReminder == legacy.challengeReminder && current.dailyStatus == legacy.dailyStatus)
        var settings = FitFightNotificationPreferences()
        settings.enabled = false
        settings.mention = false
        let newResponse = try JSONEncoder().encode(settings)
        let oldReader = try decoder.decode(LegacyNotificationPreferences.self, from: newResponse)
        precondition(!oldReader.feedPost && !oldReader.dailyStatus)
        precondition(oldReader.postReaction && oldReader.postComment)
        let patch = try JSONEncoder().encode(FitFightNotificationPreferencesUpdate(enabled: false))
        let object = try JSONSerialization.jsonObject(with: patch) as! [String: Bool]
        precondition(object == ["enabled": false], "A master switch must preserve all category choices")
        let legacyPatch = try JSONEncoder().encode(LegacyNotificationPreferencesUpdate(challengeReminder: false))
        let legacyObject = try JSONSerialization.jsonObject(with: legacyPatch) as! [String: Bool]
        precondition(legacyObject == ["challenge_reminder": false])
        precondition(NotificationImagePolicy.isAllowedImageURL(URL(string: "https://zstzbfocunthczzubggz.supabase.co/storage/v1/object/sign/user-media/photo.jpg?token=example")!))
        for raw in ["http://zstzbfocunthczzubggz.supabase.co/storage/v1/object/sign/user-media/photo.jpg", "https://example.com/photo.jpg", "file:///tmp/photo.jpg", "https://user@zstzbfocunthczzubggz.supabase.co/storage/v1/object/sign/user-media/photo.jpg"] {
            precondition(!NotificationImagePolicy.isAllowedImageURL(URL(string: raw)!))
        }
        print("Notification controls: released decoders, partial patches, defaults, and photo URL policy passed")
    }
}

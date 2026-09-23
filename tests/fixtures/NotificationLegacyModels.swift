// Frozen notification preference contracts from the released client.
import Foundation

struct LegacyNotificationPreferences: Codable, Equatable {
    var feedPost: Bool = true
    var postComment: Bool = true
    var commentReply: Bool = true
    var postReaction: Bool = true
    var challengeReminder: Bool = true
    var dailyStatus: Bool = true

    enum CodingKeys: String, CodingKey {
        case feedPost = "feed_post"
        case postComment = "post_comment"
        case commentReply = "comment_reply"
        case postReaction = "post_reaction"
        case challengeReminder = "challenge_reminder"
        case dailyStatus = "daily_status"
    }
}

struct LegacyNotificationPreferencesUpdate: Encodable {
    var feedPost: Bool?
    var postComment: Bool?
    var commentReply: Bool?
    var postReaction: Bool?
    var challengeReminder: Bool?
    var dailyStatus: Bool?

    enum CodingKeys: String, CodingKey {
        case feedPost = "feed_post"
        case postComment = "post_comment"
        case commentReply = "comment_reply"
        case postReaction = "post_reaction"
        case challengeReminder = "challenge_reminder"
        case dailyStatus = "daily_status"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(feedPost, forKey: .feedPost)
        try container.encodeIfPresent(postComment, forKey: .postComment)
        try container.encodeIfPresent(commentReply, forKey: .commentReply)
        try container.encodeIfPresent(postReaction, forKey: .postReaction)
        try container.encodeIfPresent(challengeReminder, forKey: .challengeReminder)
        try container.encodeIfPresent(dailyStatus, forKey: .dailyStatus)
    }
}

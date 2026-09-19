// Frozen feedback decoders from internal/review build 204 (c80e642a).
// Preserve this released contract when extending the current models.
import Foundation

struct Build204FeedbackPost: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var kind: String
    var title: String
    var body: String
    var voteCount: Int
    var commentCount: Int
    var voted: Bool
    var authorId: UUID
    var authorHandle: String
    var mine: Bool
    var createdAt: Date
    var metadata: FitFightFeedbackMetadata
    var media: [FitFightMedia]

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case body
        case voteCount = "vote_count"
        case commentCount = "comment_count"
        case voted
        case authorId = "author_id"
        case authorHandle = "author_handle"
        case mine
        case createdAt = "created_at"
        case metadata
        case media
    }

    init(
        id: UUID,
        kind: String,
        title: String,
        body: String,
        voteCount: Int,
        commentCount: Int,
        voted: Bool,
        authorId: UUID,
        authorHandle: String,
        mine: Bool,
        createdAt: Date,
        metadata: FitFightFeedbackMetadata = FitFightFeedbackMetadata(),
        media: [FitFightMedia] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
        self.voteCount = voteCount
        self.commentCount = commentCount
        self.voted = voted
        self.authorId = authorId
        self.authorHandle = authorHandle
        self.mine = mine
        self.createdAt = createdAt
        self.metadata = metadata
        self.media = media
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        voteCount = try container.decode(Int.self, forKey: .voteCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        voted = try container.decode(Bool.self, forKey: .voted)
        authorId = try container.decode(UUID.self, forKey: .authorId)
        authorHandle = try container.decode(String.self, forKey: .authorHandle)
        mine = try container.decode(Bool.self, forKey: .mine)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(FitFightFeedbackMetadata.self, forKey: .metadata)
            ?? FitFightFeedbackMetadata()
        media = try container.decodeIfPresent([FitFightMedia].self, forKey: .media) ?? []
    }
}

struct Build204FeedbackComment: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var body: String
    var authorId: UUID?
    var authorHandle: String
    var createdAt: Date
    var metadata: FitFightFeedbackMetadata

    enum CodingKeys: String, CodingKey {
        case id
        case body
        case authorId = "author_id"
        case authorHandle = "author_handle"
        case createdAt = "created_at"
        case metadata
    }

    init(
        id: UUID,
        body: String,
        authorHandle: String,
        createdAt: Date,
        metadata: FitFightFeedbackMetadata = FitFightFeedbackMetadata(),
        authorId: UUID? = nil
    ) {
        self.id = id
        self.body = body
        self.authorId = authorId
        self.authorHandle = authorHandle
        self.createdAt = createdAt
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        authorId = try container.decodeIfPresent(UUID.self, forKey: .authorId)
        authorHandle = try container.decode(String.self, forKey: .authorHandle)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        metadata = try container.decodeIfPresent(FitFightFeedbackMetadata.self, forKey: .metadata)
            ?? FitFightFeedbackMetadata()
    }
}

struct Build204FeedbackList: Decodable, Equatable {
    var posts: [Build204FeedbackPost]
}

struct Build204FeedbackDetail: Decodable, Equatable {
    var post: Build204FeedbackPost
    var comments: [Build204FeedbackComment]
    var canLaunchFix: Bool
    var canDelete: Bool

    enum CodingKeys: String, CodingKey {
        case post
        case comments
        case canLaunchFix = "can_launch_fix"
        case canDelete = "can_delete"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        post = try container.decode(Build204FeedbackPost.self, forKey: .post)
        comments = try container.decode([Build204FeedbackComment].self, forKey: .comments)
        canLaunchFix = try container.decodeIfPresent(Bool.self, forKey: .canLaunchFix) ?? false
        canDelete = try container.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
    }
}


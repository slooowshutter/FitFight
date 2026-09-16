import Foundation

struct FitFightMedia: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let kind: String
    let purpose: String
    let status: String
    let originalFilename: String
    let contentType: String
    let byteSize: Int
    let width: Int
    let height: Int
    let durationMs: Int?
    let sha256: String
    let url: URL?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, kind, purpose, status, url
        case originalFilename = "original_filename"
        case contentType = "content_type"
        case byteSize = "byte_size"
        case width, height, sha256
        case durationMs = "duration_ms"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(String.self, forKey: .kind)
        purpose = try container.decode(String.self, forKey: .purpose)
        status = try container.decode(String.self, forKey: .status)
        originalFilename = try container.decode(String.self, forKey: .originalFilename)
        contentType = try container.decode(String.self, forKey: .contentType)
        byteSize = try container.decode(Int.self, forKey: .byteSize)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        durationMs = try container.decodeIfPresent(Int.self, forKey: .durationMs)
        sha256 = try container.decode(String.self, forKey: .sha256)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        if let parsed = try? container.decodeIfPresent(URL.self, forKey: .url) {
            url = parsed
        } else if let raw = try container.decodeIfPresent(String.self, forKey: .url), !raw.isEmpty {
            url = URL(string: raw)
        } else {
            url = nil
        }
    }
}

struct FitFightMediaUpload: Decodable {
    let media: FitFightMedia
    let upload: Upload

    struct Upload: Decodable {
        let url: URL
        let token: String
        let method: String
    }
}

struct FitFightMediaResponse: Decodable {
    let media: FitFightMedia
}

struct FitFightFightPost: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let audience: String
    let fightId: UUID?
    let fightName: String
    let body: String
    let createdAt: String
    let author: Author
    let media: [FitFightMedia]
    let tags: [Tag]
    let reactions: [Reaction]
    let commentCount: Int
    let mine: Bool
    let broadcast: Bool
    let channels: [Channel]

    struct Channel: Codable, Equatable, Hashable {
        let fightId: UUID
        let name: String

        enum CodingKeys: String, CodingKey {
            case fightId = "fight_id"
            case name
        }
    }

    struct Tag: Codable, Equatable, Hashable {
        let userId: UUID
        let handle: String
        let displayName: String

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case handle
            case displayName = "display_name"
        }
    }

    struct Reaction: Codable, Equatable, Hashable {
        let emoji: String
        let count: Int
        let mine: Bool
    }

    struct Author: Codable, Equatable, Hashable {
        let userId: UUID
        let handle: String
        let displayName: String
        let avatar: FitFightMedia?
        var companionId: String? = nil

        var atHandle: String { "@\(handle)" }
        var initials: String {
            let parts = displayName.split(separator: " ").filter { !$0.isEmpty }
            if parts.count >= 2 {
                return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased()
            }
            if let first = parts.first, !first.isEmpty {
                return String(first.prefix(2)).uppercased()
            }
            return String(handle.prefix(2)).uppercased()
        }

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case handle
            case displayName = "display_name"
            case avatar
            case companionId = "companion_id"
        }
    }

    init(
        id: UUID,
        audience: String,
        fightId: UUID?,
        fightName: String,
        body: String,
        createdAt: String,
        author: Author,
        media: [FitFightMedia],
        tags: [Tag],
        reactions: [Reaction],
        commentCount: Int,
        mine: Bool,
        broadcast: Bool = false,
        channels: [Channel] = []
    ) {
        self.id = id
        self.audience = audience
        self.fightId = fightId
        self.fightName = fightName
        self.body = body
        self.createdAt = createdAt
        self.author = author
        self.media = media
        self.tags = tags
        self.reactions = reactions
        self.commentCount = commentCount
        self.mine = mine
        self.broadcast = broadcast
        self.channels = channels
    }

    var createdDate: Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: createdAt) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: createdAt) ?? .distantPast
    }

    var isMain: Bool { audience == "main" }

    var channelLabel: String {
        if broadcast || isMain {
            return String(localized: "Public")
        }
        let names = channels.map(\.name).filter { !$0.isEmpty }
        if names.isEmpty { return fightName }
        if names.count == 1 { return names[0] }
        return names.joined(separator: " · ")
    }

    func updating(
        reactions: [Reaction]? = nil,
        commentCount: Int? = nil
    ) -> FitFightFightPost {
        FitFightFightPost(
            id: id,
            audience: audience,
            fightId: fightId,
            fightName: fightName,
            body: body,
            createdAt: createdAt,
            author: author,
            media: media,
            tags: tags,
            reactions: reactions ?? self.reactions,
            commentCount: commentCount ?? self.commentCount,
            mine: mine,
            broadcast: broadcast,
            channels: channels
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, audience, body, author, media, tags, reactions, mine, broadcast, channels
        case fightId = "fight_id"
        case fightName = "fight_name"
        case createdAt = "created_at"
        case commentCount = "comment_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        audience = try container.decode(String.self, forKey: .audience)
        fightId = try container.decodeIfPresent(UUID.self, forKey: .fightId)
        fightName = try container.decode(String.self, forKey: .fightName)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        author = try container.decode(Author.self, forKey: .author)
        media = try container.decode([FitFightMedia].self, forKey: .media)
        tags = try container.decode([Tag].self, forKey: .tags)
        reactions = try container.decode([Reaction].self, forKey: .reactions)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        mine = try container.decode(Bool.self, forKey: .mine)
        broadcast = try container.decodeIfPresent(Bool.self, forKey: .broadcast) ?? false
        channels = try container.decodeIfPresent([Channel].self, forKey: .channels) ?? []
    }
}

enum FightPostCommentSort: String, CaseIterable, Hashable {
    case comments
    case recent

    var title: String {
        switch self {
        case .comments:
            String(localized: "Most comments")
        case .recent:
            String(localized: "Most recent")
        }
    }
}

struct FitFightFightPostComment: Codable, Equatable, Hashable, Identifiable {
    let id: UUID
    let postId: UUID
    let parentId: UUID?
    let body: String
    let createdAt: String
    let author: FitFightFightPost.Author
    let mine: Bool

    var createdDate: Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: createdAt) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: createdAt) ?? .distantPast
    }

    enum CodingKeys: String, CodingKey {
        case id, body, author, mine
        case postId = "post_id"
        case parentId = "parent_id"
        case createdAt = "created_at"
    }
}

struct FitFightFightPostCommentList: Decodable {
    let comments: [FitFightFightPostComment]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case comments
        case nextCursor = "next_cursor"
    }
}

struct FitFightFightPostCommentResponse: Decodable {
    let comment: FitFightFightPostComment
    let commentCount: Int?

    enum CodingKeys: String, CodingKey {
        case comment
        case commentCount = "comment_count"
    }
}

struct FitFightFightPostCommentDeletion: Decodable {
    let deleted: Bool
    let commentCount: Int?

    enum CodingKeys: String, CodingKey {
        case deleted
        case commentCount = "comment_count"
    }
}

struct FitFightFightPostReactionList: Decodable {
    let reactions: [FitFightFightPost.Reaction]
}

struct FitFightFightPostReactionPerson: Decodable, Identifiable {
    let userId: UUID
    let handle: String
    let displayName: String
    let emoji: String

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case displayName = "display_name"
        case handle, emoji
    }
}

struct FitFightFightPostReactionPeople: Decodable {
    let people: [FitFightFightPostReactionPerson]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case people
        case nextCursor = "next_cursor"
    }
}

struct FitFightFightPostList: Decodable {
    let posts: [FitFightFightPost]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case posts
        case nextCursor = "next_cursor"
    }
}

struct FitFightFightPostResponse: Decodable {
    let post: FitFightFightPost
}

struct FitFightFightPostBatch: Decodable {
    let posts: [FitFightFightPost]
}

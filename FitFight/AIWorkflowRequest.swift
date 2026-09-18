import Foundation

struct FitFightAIError: Decodable, LocalizedError {
    let code: String
    let message: String?
    let requestID: UUID?
    let retryAfterSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case code
        case message = "error"
        case requestID = "request_id"
        case retryAfterSeconds = "retry_after_seconds"
    }

    var errorDescription: String? {
        switch code {
        case "ai_insufficient_credits":
            return String(localized: "You do not have enough available credits.")
        case "ai_request_expired":
            return String(localized: "This request has expired. Start a new action to generate again.")
        case "ai_rate_limited":
            return String(localized: "You have made a few requests recently. Try again shortly.")
        case "ai_daily_limit":
            return String(localized: "You have reached today's AI limit. It resets at midnight UTC.")
        case "ai_in_progress":
            return String(localized: "Your previous request is still unresolved. Check its status.")
        case "ai_request_conflict":
            return String(localized: "This request was already used with different parameters.")
        case "ai_busy":
            return String(localized: "AI is busy. Try again later.")
        case "ai_unavailable":
            return String(localized: "This feature is temporarily unavailable on our side.")
        case "ai_failed":
            return String(localized: "We couldn't complete this request.")
        case "ai_invalid_result":
            return String(localized: "We couldn't read the generated result.")
        case "ai_status_unavailable":
            return String(localized: "We couldn't check the result. Check again.")
        case "ai_start_unconfirmed":
            return String(localized: "We couldn't confirm whether this request started. Check again later.")
        case "ai_cancelled":
            return String(localized: "This request was cancelled.")
        default:
            return message ?? String(localized: "We couldn't complete this request.")
        }
    }
}

struct FitFightAIRequest: Decodable {
    enum Workflow: String, Codable, CaseIterable {
        case avatar, fitness
        case groupPhoto = "group_photo"
    }

    enum Status: String, Decodable {
        case pending, running, completed, failed, cancelled
        case startUnconfirmed = "start_unconfirmed"
    }

    let requestID: UUID
    let workflow: Workflow
    let status: Status
    let pollAfterSeconds: Int?
    let imageURL: URL?
    let fitnessImages: FitFightAIFitnessImages?
    let failure: FitFightAIError?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case workflow, status
        case pollAfterSeconds = "poll_after_seconds"
        case data
    }

    private struct AvatarResult: Decodable {
        let imageURL: URL

        enum CodingKeys: String, CodingKey {
            case imageURL = "image_url"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        workflow = try container.decode(Workflow.self, forKey: .workflow)
        status = try container.decode(Status.self, forKey: .status)
        switch status {
        case .pending, .running:
            pollAfterSeconds = try container.decode(Int.self, forKey: .pollAfterSeconds)
            imageURL = nil
            fitnessImages = nil
            failure = nil
        case .completed:
            pollAfterSeconds = nil
            switch workflow {
            case .avatar, .groupPhoto:
                imageURL = try container.decode(AvatarResult.self, forKey: .data).imageURL
                fitnessImages = nil
            case .fitness:
                imageURL = nil
                fitnessImages = try container.decode(FitFightAIFitnessImages.self, forKey: .data)
            }
            failure = nil
        case .failed, .cancelled, .startUnconfirmed:
            pollAfterSeconds = nil
            imageURL = nil
            fitnessImages = nil
            failure = try FitFightAIError(from: decoder)
        }
    }
}

struct FitFightAvatarRequest: Encodable {
    let workflow = "avatar"
    let parameters: Parameters

    struct Parameters: Encodable {
        let description: String
    }
}

struct FitFightAIAllowance: Decodable {
    let available: Int
    let reserved: Int
    let avatarPrice: Int
    let fitnessPrice: Int?
    let groupPhotoPrice: Int?

    enum CodingKeys: String, CodingKey {
        case available, reserved
        case avatarPrice = "avatar_price"
        case fitnessPrice = "fitness_price"
        case groupPhotoPrice = "group_photo_price"
    }
}


struct FitFightAIFitnessImages: Decodable {
    let resting: URL
    let soft: URL
    let average: URL
    let fit: URL
    let strong: URL
}

struct FitFightAICharacter: Codable {
    let avatarRequestID: UUID
    let identityDetails: String

    enum CodingKeys: String, CodingKey {
        case avatarRequestID = "avatar_request_id"
        case identityDetails = "identity_details"
    }
}

struct FitFightFitnessRequest: Encodable {
    let workflow = "fitness"
    let parameters: FitFightAICharacter
}

struct FitFightGroupPhotoRequest: Encodable {
    let workflow = "group_photo"
    let parameters: Parameters

    struct Parameters: Encodable {
        let characters: [FitFightAICharacter]
        let scene: String
    }
}

struct FitFightAILibraryEntry: Decodable, Identifiable {
    let requestID: UUID
    let workflow: FitFightAIRequest.Workflow
    let description: String
    let images: [Image]

    var id: UUID { requestID }

    struct Image: Decodable, Identifiable {
        let stage: String
        let media: FitFightMedia
        var id: UUID { media.id }
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case workflow, description, images
    }
}

struct FitFightAISaveImages: Encodable {
    let description: String
    let images: [Image]

    struct Image: Encodable {
        let stage: String
        let mediaID: UUID

        enum CodingKeys: String, CodingKey {
            case stage
            case mediaID = "media_id"
        }
    }
}

/// The exact paid action survives dismissal and relaunch until its result is saved.
struct AICompanionAction: Codable {
    let key: UUID
    let workflow: FitFightAIRequest.Workflow
    let description: String
    let characters: [FitFightAICharacter]
    var requestID: UUID?
    var uploaded: [String: FitFightMedia] = [:]
}

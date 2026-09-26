import Foundation

struct FitFightProfile: Codable, Equatable {
    let userId: UUID
    let handle: String
    let displayName: String
    let handleSetAt: String?
    var referralCode: UUID?
    var avatar: FitFightMedia?
    var companionId: String? = nil
    var companionPrompt: String? = nil
    var companionImageURL: URL? = nil
    var timeZone: String? = nil

    var photoURL: URL? { companionId == "custom" ? companionImageURL ?? avatar?.url : avatar?.url }

    var calendarTimeZone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? .current }

    var atHandle: String { "@\(handle)" }

    var looksGenerated: Bool {
        handle.hasPrefix("user_") && handle.count == 17
    }

    var initials: String { monogram(displayName: displayName, handle: handle) }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case handle
        case displayName = "display_name"
        case handleSetAt = "handle_set_at"
        case referralCode = "referral_code"
        case avatar
        case companionId = "companion_id"
        case companionPrompt = "companion_prompt"
        case companionImageURL = "companion_image_url"
        case timeZone = "time_zone"
    }
}

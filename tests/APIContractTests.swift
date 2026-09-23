import Foundation

@main
struct APIContractTests {
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let allowance = try decoder.decode(FitFightAIAllowance.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-allowance.json")))
        precondition(allowance.available == 2 && allowance.reserved == 1 && allowance.avatarPrice == 1)
        let pendingAI = try decoder.decode(FitFightAIRequest.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-run-pending.json")))
        precondition(pendingAI.status == .pending && pendingAI.pollAfterSeconds == 3)
        precondition(pendingAI.failure == nil && pendingAI.imageURL == nil)
        let completedAI = try decoder.decode(FitFightAIRequest.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-run-completed.json")))
        precondition(completedAI.status == .completed && completedAI.imageURL?.scheme == "https")
        precondition(completedAI.pollAfterSeconds == nil && completedAI.failure == nil)
        let fitnessAI = try decoder.decode(FitFightAIRequest.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-run-fitness.json")))
        precondition(fitnessAI.workflow == .fitness && fitnessAI.status == .completed)
        precondition(fitnessAI.imageURL == nil && fitnessAI.fitnessImages?.strong.lastPathComponent == "strong.png")
        let groupAI = try decoder.decode(FitFightAIRequest.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-run-group-photo.json")))
        precondition(groupAI.workflow == .groupPhoto && groupAI.imageURL?.lastPathComponent == "photo.png")
        precondition(groupAI.fitnessImages == nil)
        precondition(allowance.fitnessPrice == nil && allowance.groupPhotoPrice == nil)
        let aiLibrary = try decoder.decode([FitFightAILibraryEntry].self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-library.json")))
        precondition(aiLibrary.map(\.workflow) == [.avatar, .fitness, .groupPhoto])
        precondition(aiLibrary[1].images.map(\.stage) == ["resting", "soft", "average", "fit", "strong"])
        precondition(aiLibrary[0].images[0].url.absoluteString == "https://supabase.tryblend.ai/avatar-image_url.png")
        let unconfirmedAI = try decoder.decode(FitFightAIRequest.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-run-unconfirmed.json")))
        precondition(unconfirmedAI.failure?.code == "ai_start_unconfirmed")
        precondition(unconfirmedAI.failure?.requestID == unconfirmedAI.requestID)
        let busyAI = try decoder.decode(FitFightAIError.self,
            from: Data(contentsOf: fixtures.appendingPathComponent("ai-error.json")))
        precondition(busyAI.retryAfterSeconds == 30 && busyAI.requestID == pendingAI.requestID)
        // Older errors remain decodable without the additive recovery fields.
        let olderAI = try decoder.decode(FitFightAIError.self,
            from: Data("{\"code\":\"ai_failed\",\"error\":\"Try again later.\"}".utf8))
        precondition(olderAI.retryAfterSeconds == nil && olderAI.requestID == nil)
        let legacyCommentData = try Data(contentsOf: fixtures.appendingPathComponent("post-comment-list-legacy-response.json"))
        let currentCommentData = try Data(contentsOf: fixtures.appendingPathComponent("post-comment-list-like-response.json"))
        let legacyComments = try decoder.decode(FitFightFightPostCommentList.self, from: legacyCommentData)
        let currentComments = try decoder.decode(FitFightFightPostCommentList.self, from: currentCommentData)
        precondition(legacyComments.comments[0].likeCount == nil && legacyComments.comments[0].likedByMe == nil,
                     "Responses for installed clients remain decodable without comment like fields")
        precondition(currentComments.comments[0].likeCount == 2 && currentComments.comments[0].likedByMe == true)
        let encodedComment = try JSONSerialization.jsonObject(with: JSONEncoder().encode(currentComments.comments[0])) as! [String: Any]
        precondition(encodedComment["like_count"] as? Int == 2 && encodedComment["liked_by_me"] as? Bool == true,
                     "Cached comment like fields retain their API snake-case keys")
        let releasedComments = try decoder.decode(Build201FightPostCommentList.self, from: currentCommentData)
        precondition(releasedComments.comments[0].body == "See you on the walk!",
                     "The byte-identical build 201, 202, and 204 comment decoder ignores additive like fields")
        let likeData = try Data(contentsOf: fixtures.appendingPathComponent("post-comment-like-response.json"))
        let like = try decoder.decode(FitFightFightPostCommentLike.self, from: likeData)
        precondition(like.likeCount == 3 && like.likedByMe)

        let reactionPeopleData = try Data(contentsOf: fixtures.appendingPathComponent("post-reaction-people-response.json"))
        let reactionPeople = try decoder.decode(FitFightFightPostReactionPeople.self, from: reactionPeopleData)
        precondition(reactionPeople.people.count == 2)
        precondition(reactionPeople.people[0].handle == "marc" && reactionPeople.people[0].emoji == "❤️")
        precondition(reactionPeople.people[0].displayName == "Marc Lamy")
        precondition(reactionPeople.nextCursor == reactionPeople.people[1].id.uuidString.lowercased())
        let emptyReactions = try decoder.decode(FitFightFightPostReactionPeople.self, from: Data("{\"people\":[],\"next_cursor\":null}".utf8))
        precondition(emptyReactions.people.isEmpty && emptyReactions.nextCursor == nil)

        let profileData = try Data(contentsOf: fixtures.appendingPathComponent("profile.json"))
        let profile = try decoder.decode(FitFightProfile.self, from: profileData)
        precondition(profile.userId.uuidString.lowercased() == "11111111-1111-4111-8111-111111111111")
        precondition(profile.atHandle == "@marc" && profile.initials == "ML")
        precondition(profile.handleSetAt == "2026-09-01T10:00:00Z")
        precondition(profile.referralCode?.uuidString.lowercased() == "22222222-2222-4222-8222-222222222222")
        precondition(profile.companionId == nil)
        precondition(profile.companionPrompt == nil)
        precondition(profile.timeZone == nil, "Older profiles remain decodable")
        var generatedProfile = profile
        generatedProfile.companionId = "custom"
        generatedProfile.companionImageURL = aiLibrary[0].images[0].url
        precondition(generatedProfile.photoURL == aiLibrary[0].images[0].url)
        let restoredGeneratedProfile = try decoder.decode(FitFightProfile.self, from: JSONEncoder().encode(generatedProfile))
        precondition(restoredGeneratedProfile == generatedProfile)
        let oldProfile = try decoder.decode(PreBlendProfile.self, from: profileData)
        let oldReaderWithGeneratedImage = try decoder.decode(PreBlendProfile.self, from: JSONEncoder().encode(generatedProfile))
        precondition(oldReaderWithGeneratedImage.userId == oldProfile.userId)
        precondition(oldReaderWithGeneratedImage.handle == oldProfile.handle)
        precondition(oldReaderWithGeneratedImage.avatar == oldProfile.avatar)
        precondition(oldReaderWithGeneratedImage.companionId == "custom")


        var zonedProfileJSON = try JSONSerialization.jsonObject(with: profileData) as! [String: Any]
        zonedProfileJSON["time_zone"] = "Pacific/Kiritimati"
        let zonedProfile = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: zonedProfileJSON))
        precondition(zonedProfile.calendarTimeZone.identifier == "Pacific/Kiritimati")
        let cachedZonedProfile = try decoder.decode(FitFightProfile.self, from: JSONEncoder().encode(zonedProfile))
        precondition(cachedZonedProfile == zonedProfile)

        var withCompanionJSON = try JSONSerialization.jsonObject(with: profileData) as! [String: Any]
        withCompanionJSON["companion_id"] = "fox"
        let withCompanion = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: withCompanionJSON))
        precondition(withCompanion.companionId == "fox")
        precondition(withCompanion.companionPrompt == nil)
        withCompanionJSON["companion_id"] = "custom"
        withCompanionJSON["companion_prompt"] = "a cream frenchie with gold sunglasses"
        let customCompanion = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: withCompanionJSON))
        precondition(customCompanion.companionId == "custom")
        precondition(customCompanion.companionPrompt == "a cream frenchie with gold sunglasses")

        guard var extendedProfile = try JSONSerialization.jsonObject(with: profileData) as? [String: Any] else {
            preconditionFailure("Profile fixture must be a JSON object")
        }
        extendedProfile["future_field"] = ["enabled": true]
        let extended = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: extendedProfile))
        precondition(extended == profile)
        extendedProfile["handle"] = "user_123456789012"
        extendedProfile["handle_set_at"] = NSNull()
        let onboarding = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: extendedProfile))
        precondition(onboarding.looksGenerated && onboarding.handleSetAt == nil)
        extendedProfile.removeValue(forKey: "handle_set_at")
        extendedProfile.removeValue(forKey: "referral_code")
        let cached = try decoder.decode(FitFightProfile.self,
            from: JSONSerialization.data(withJSONObject: extendedProfile))
        precondition(cached.handleSetAt == nil && cached.referralCode == nil)

        let snapshotData = try Data(contentsOf: fixtures.appendingPathComponent("fight-snapshot.json"))
        guard var extendedSnapshot = try JSONSerialization.jsonObject(with: snapshotData) as? [String: Any] else {
            preconditionFailure("Snapshot fixture must be a JSON object")
        }
        extendedSnapshot["future_field"] = true
        let snapshot = try decoder.decode(FitFightSnapshot.self,
            from: JSONSerialization.data(withJSONObject: extendedSnapshot))
        precondition(snapshot.fights.count == 1 && snapshot.members.count == 2)
        precondition(snapshot.fights[0].timeZone == nil, "Older Fight snapshots remain decodable")
        var zonedFights = extendedSnapshot["fights"] as! [[String: Any]]
        zonedFights[0]["time_zone"] = "Europe/Paris"
        extendedSnapshot["fights"] = zonedFights
        let zonedSnapshot = try decoder.decode(FitFightSnapshot.self,
            from: JSONSerialization.data(withJSONObject: extendedSnapshot))
        precondition(zonedSnapshot.fights[0].timeZone == "Europe/Paris")
        precondition(snapshot.fights[0].name == "September Steps" && snapshot.fights[0].actionText == nil)
        precondition(snapshot.members[0].currentValue == 8500 && snapshot.members[0].rank == 1)
        precondition(snapshot.members[0].lastSyncedAt != nil && snapshot.members[0].finalValue == nil)
        precondition(snapshot.members[1].state == "deferred" && snapshot.members[1].rank == nil)
        precondition(snapshot.profiles[0].handle == "marc" && snapshot.profiles[0].handleSetAt == nil)
        precondition(snapshot.profiles[0].avatar?.url?.absoluteString == "https://example.com/marc.jpg")
        precondition(snapshot.profiles[0].companionId == "fox")
        precondition(snapshot.profiles[1].avatar == nil && snapshot.profiles[1].companionId == nil)
        precondition(snapshot.series[0].joinCode == "ABCD" && snapshot.series[0].recurring)
        precondition(snapshot.members[0].stepCheckpoints == nil, "Older snapshot responses remain decodable")
        let checkpointData = try Data(contentsOf: fixtures.appendingPathComponent("fight-snapshot-checkpoints.json"))
        let checkpoints = try decoder.decode(FitFightSnapshot.self, from: checkpointData)
        precondition(checkpoints.members[0].stepCheckpoints?.last?.steps == 8500)
        precondition(checkpoints.members[1].stepCheckpoints == nil)
        print("API contracts: comment likes, profile, onboarding, cached profiles, extra fields, Fight snapshot passed")
    }
}

private struct Build201FightPostCommentList: Decodable {
    let comments: [Build201FightPostComment]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case comments
        case nextCursor = "next_cursor"
    }
}

private struct Build201FightPostComment: Decodable {
    let id: UUID
    let postId: UUID
    let parentId: UUID?
    let body: String
    let createdAt: String
    let author: FitFightFightPost.Author
    let mine: Bool

    enum CodingKeys: String, CodingKey {
        case id, body, author, mine
        case postId = "post_id"
        case parentId = "parent_id"
        case createdAt = "created_at"
    }
}


private struct PreBlendProfile: Codable, Equatable {
    let userId: UUID
    let handle: String
    let displayName: String
    let handleSetAt: String?
    var referralCode: UUID?
    var avatar: FitFightMedia?
    var companionId: String? = nil
    var companionPrompt: String? = nil
    var timeZone: String? = nil

    var calendarTimeZone: TimeZone { timeZone.flatMap(TimeZone.init(identifier:)) ?? .current }

    var atHandle: String { "@\(handle)" }

    var looksGenerated: Bool {
        handle.hasPrefix("user_") && handle.count == 17
    }

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
        case handleSetAt = "handle_set_at"
        case referralCode = "referral_code"
        case avatar
        case companionId = "companion_id"
        case companionPrompt = "companion_prompt"
        case timeZone = "time_zone"
    }
}

import Foundation

@main
struct FeedbackCompatibilityTests {
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldData = try Data(contentsOf: fixtures.appendingPathComponent("feedback-detail-legacy.json"))
        let profileData = try Data(contentsOf: fixtures.appendingPathComponent("feedback-detail-profile.json"))
        let legacy = try decoder.decode(FitFightFeedbackDetail.self, from: oldData)
        let current = try decoder.decode(FitFightFeedbackDetail.self, from: profileData)
        precondition(legacy.comments[0].authorId == nil)
        precondition(current.comments[0].authorId?.uuidString.lowercased() == "33333333-3333-4333-8333-333333333333")
        precondition(current.post == legacy.post)
        precondition(current.comments[0].body == legacy.comments[0].body)
        precondition(current.comments.count == current.post.commentCount)
        precondition(current.canLaunchFix == legacy.canLaunchFix)

        let oldReader = try decoder.decode(LegacyFeedbackDetail.self, from: oldData)
        let profileReader = try decoder.decode(LegacyFeedbackDetail.self, from: profileData)
        precondition(oldReader.post == profileReader.post)
        precondition(oldReader.comments == profileReader.comments)
        precondition(oldReader.canLaunchFix == profileReader.canLaunchFix)
        precondition(!current.post.archived && current.post.archiveReason == nil && !current.canArchive)
        let archivedData = try Data(contentsOf: fixtures.appendingPathComponent("feedback-detail-archived.json"))
        let archived = try decoder.decode(FitFightFeedbackDetail.self, from: archivedData)
        precondition(archived.post.archived && archived.post.archiveReason == "Resolved")
        precondition(archived.canArchive && archived.canDelete)
        let archivedOldReader = try decoder.decode(LegacyFeedbackDetail.self, from: archivedData)
        precondition(archivedOldReader.post == profileReader.post)
        precondition(archivedOldReader.comments == profileReader.comments)
        let build204 = try decoder.decode(Build204FeedbackDetail.self, from: profileData)
        let build204Archived = try decoder.decode(Build204FeedbackDetail.self, from: archivedData)
        precondition(build204.post == build204Archived.post)
        precondition(build204.comments == build204Archived.comments)
        precondition(build204Archived.canDelete)
        print("Feedback: frozen builds 201, 202, 204 and current decoding preserve feedback and Profile fields")
    }
}

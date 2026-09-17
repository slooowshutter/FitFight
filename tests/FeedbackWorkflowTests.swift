import Foundation

@main
struct FeedbackWorkflowTests {
    static func main() throws {
        let fixtures = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let oldData = try Data(contentsOf: fixtures.appendingPathComponent("feedback-detail-legacy.json"))
        let currentData = try Data(contentsOf: fixtures.appendingPathComponent("feedback-detail-workflow.json"))
        let legacy = try decoder.decode(FitFightFeedbackDetail.self, from: oldData)
        precondition(legacy.post.workflowStatus == nil && !legacy.canManageStatus)
        precondition(legacy.comments[0].workflowStatus == nil && legacy.comments[0].actorId == nil)
        let current = try decoder.decode(FitFightFeedbackDetail.self, from: currentData)
        precondition(current.post.workflowStatus == "building")
        precondition(current.comments.count == current.post.commentCount)
        precondition(current.comments[1].actorId?.uuidString.lowercased() == "11111111-1111-4111-8111-111111111111")
        precondition(current.comments[2].actorId == nil)
        precondition(current.comments[1].workflowStatus == "approved")
        precondition(current.comments[2].authorHandle == "FitFight")

        let oldReader = try decoder.decode(LegacyFeedbackDetail.self, from: currentData)
        precondition(oldReader.comments.count == 3)
        precondition(oldReader.comments[1].authorHandle == "FitFight")
        precondition(oldReader.comments[1].body == "Approved by Marc for build.")
        precondition(oldReader.comments[2].body == "This feature is now being built.")
        precondition(oldReader.post.commentCount == 3)
        _ = try decoder.decode(LegacyFeedbackDetail.self, from: oldData)

        let futureData = Data(String(decoding: currentData, as: UTF8.self).replacingOccurrences(of: "building", with: "future_status").utf8)
        let future = try decoder.decode(FitFightFeedbackDetail.self, from: futureData)
        precondition(future.post.workflowStatus == "future_status")
        precondition(future.comments[2].workflowStatus == "future_status")
        precondition(FeedbackWorkflowStatus(rawValue: "future_status") == nil)
        precondition(FeedbackWorkflowStatus.available.next == nil)
        precondition(FeedbackWorkflowStatus.allCases.filter { $0.next == nil } == [.available])
        precondition(FeedbackWorkflowStatus.allCases.count == 8)
        print("Feedback: new, legacy build 201/202, authorless system updates, and future metadata decode")
    }
}

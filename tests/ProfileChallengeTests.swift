import Foundation

private final class AppModel {
    var profileChallenge: ProfileChallengeDraft?
}

private final class Composer {
    let model = AppModel()
    var opening = NewFightOpening.choose
    var step = 2
    var durationDays = 30
    var customSchedule = true
    var recurring = false
    var fightTitle = "An earlier draft"
    var visibilityJoinable = true
    var inviteHandles = ["someone_else"]
    var actionText = ""

    func apply(_ rematch: ProfileRematch?) {
        model.profileChallenge = ProfileChallengeDraft(
            handle: "opponent", durationSeconds: rematch?.durationSeconds,
            actionText: rematch?.actionText, durationDays: rematch?.durationDays
        )
        applyProfileChallenge()
    }

    // PROFILE_CHALLENGE_METHOD
}

@main private struct ProfileChallengeTests {
    static func main() throws {
        let decoder = JSONDecoder()
        for seconds in [71 * 3600, 73 * 3600] {
            let data = Data("{\"duration_seconds\":\(seconds),\"duration_days\":3,\"action_text\":\"Make coffee\"}".utf8)
            let rematch = try decoder.decode(ProfileRematch.self, from: data)
            let composer = Composer()
            composer.apply(rematch)
            precondition(composer.durationDays == 3, "A three-day Fight must stay three days across either clock change")
            precondition(composer.inviteHandles == ["opponent"] && composer.actionText == "Make coffee")
            precondition(composer.opening == .create && composer.step == 0 && !composer.customSchedule)
            precondition(!composer.visibilityJoinable && composer.fightTitle.isEmpty && composer.recurring)
            precondition(composer.model.profileChallenge == nil, "The draft is consumed once")
        }
        for days in [3, 7, 14, 30] {
            let data = Data("{\"duration_seconds\":\(days * 86400),\"action_text\":null}".utf8)
            let rematch = try decoder.decode(ProfileRematch.self, from: data)
            precondition(rematch.durationDays == nil, "Existing API responses remain decodable")
            let composer = Composer()
            composer.apply(rematch)
            precondition(composer.durationDays == days)
        }
        let composer = Composer()
        composer.apply(nil)
        precondition(composer.durationDays == 7 && composer.actionText.isEmpty, "A fresh challenge keeps the default")
        print("Profile challenge checks passed: spring/fall clock changes, released responses, and fresh challenge defaults")
    }
}

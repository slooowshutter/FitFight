import Foundation

enum FFTab { case fights, newFight, feed, feedback, you }
enum FightStatus { case live, pending, invited, finished }
enum NewFightOpening { case choose, create, join }

struct Fight {
    let id: String
    let seriesId: String?
    let status: FightStatus
    let windowStart: Date
}

@MainActor final class AppModel {
    // MODEL_STATE
    var fights: [Fight] = []
    var pendingJoinable: Fight?
    var profileChallenge: ProfileChallengeDraft?
    // MODEL_METHODS
}

@MainActor final class ProfileActions {
    let model: AppModel
    init(model: AppModel) { self.model = model }
    func dismiss() {}
    func openHistory(_ fightID: UUID) {
        // HISTORY_ACTION
    }
    func openFeed(_ fightID: UUID) {
        // FEED_ACTION
    }
    func destination(id: String) -> Fight? {
        // DESTINATION
    }
}

@MainActor final class DetailState {
    let model: AppModel
    let initialFight: Fight
    init(model: AppModel, initialFight: Fight) { self.model = model; self.initialFight = initialFight }
    // DETAIL_SELECTION
}

enum FightComposer {
    // END_DATE
}

@MainActor final class ComposerState {
    let model: AppModel
    var opening = NewFightOpening.choose
    var step = 0
    var durationDays = 7
    var customSchedule = false
    var selectedTimeZone: TimeZone?
    var savedTimeZone = TimeZone(secondsFromGMT: 0)!
    var fightTimeZone: TimeZone { selectedTimeZone ?? savedTimeZone }
    var customStart = Date()
    var customEnd = Date()
    var recurring = true
    var fightTitle = ""
    var visibilityJoinable = false
    var inviteHandles: [String] = []
    var actionText = ""
    init(model: AppModel) { self.model = model }
    // PREPARE_REMATCH
}

@main struct ProfileNavigationTests {
    @MainActor static var failures: [String] = []
    @MainActor static func check(_ condition: Bool, _ message: String) {
        if !condition { failures.append(message); print("FAIL: \(message)") }
    }

    @MainActor static func main() async {
        NSTimeZone.default = TimeZone(secondsFromGMT: 0)!
        let model = AppModel()
        let composer = ComposerState(model: model)
        for seconds in [5 * 86_400, 3 * 86_400 - 3600, 14 * 86_400 + 3600] {
            model.profileChallenge = ProfileChallengeDraft(handle: "opponent", durationSeconds: seconds, actionText: "Make coffee")
            composer.applyProfileChallenge()
            check(composer.customSchedule, "Rematch \(seconds) seconds uses a custom schedule")
            check(Int(composer.customEnd.timeIntervalSince(composer.customStart)) == seconds, "Rematch keeps its exact prior duration")
            check(composer.customStart > Date(), "Custom rematch can be submitted with a future start")
            check(composer.inviteHandles == ["opponent"] && composer.actionText == "Make coffee", "Rematch keeps the opponent and action")
            check(model.profileChallenge == nil, "Rematch draft is consumed once")
        }
        for days in [3, 7, 14, 30] {
            model.profileChallenge = ProfileChallengeDraft(handle: "opponent", durationSeconds: days * 86_400, actionText: nil)
            composer.applyProfileChallenge()
            check(!composer.customSchedule && composer.durationDays == days, "Ordinary \(days)-day rematches retain their preset")
        }
        NSTimeZone.default = TimeZone(identifier: "Europe/Paris")!
        composer.savedTimeZone = TimeZone(identifier: "Europe/Paris")!
        let beforeDST = ISO8601DateFormatter().date(from: "2026-10-24T12:00:00Z")!
        model.profileChallenge = ProfileChallengeDraft(handle: "opponent", durationSeconds: 3 * 86_400, actionText: nil)
        composer.applyProfileChallenge(now: beforeDST)
        check(composer.customSchedule, "A new daylight-saving transition cannot change the rematch duration")
        check(composer.customEnd.timeIntervalSince(composer.customStart) == 3 * 86_400, "The new custom window preserves elapsed time across daylight saving")

        let paris = TimeZone(identifier: "Europe/Paris")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        NSTimeZone.default = tokyo
        let parisEnd = FightComposer.endDate(from: beforeDST, days: 3, timeZone: paris)
        check(parisEnd.timeIntervalSince(beforeDST) == 3 * 86_400 + 3600, "Calendar durations use the saved zone across DST")
        let movedStart = FightComposer.moveWallTime(beforeDST, from: paris, to: tokyo)
        let movedEnd = FightComposer.moveWallTime(parisEnd, from: paris, to: tokyo)
        check(movedStart == ISO8601DateFormatter().date(from: "2026-10-24T05:00:00Z")!, "Custom 14:00 stays 14:00 in the selected zone")
        check(movedEnd.timeIntervalSince(movedStart) == 3 * 86_400, "The selected zone determines the actual custom window")

        let historical = Fight(id: UUID().uuidString, seriesId: "series", status: .finished, windowStart: Date(timeIntervalSince1970: 1000))
        let current = Fight(id: UUID().uuidString, seriesId: "series", status: .live, windowStart: Date(timeIntervalSince1970: 2000))
        model.fights = [historical, current]
        let actions = ProfileActions(model: model)
        model.tab = .you
        actions.openHistory(UUID(uuidString: historical.id)!)
        for _ in 0..<10_000 { if model.openFightID != nil { break }; await Task.yield() }
        check(model.openFightID == historical.id, "History opens the selected round, not the newest round")
        if let id = model.openFightID, let routed = actions.destination(id: id) {
            let detail = DetailState(model: model, initialFight: routed)
            check(detail.fight.id == historical.id, "Navigation and detail resolve the selected historical round")
            let newer = Fight(id: UUID().uuidString, seriesId: "series", status: .live, windowStart: Date(timeIntervalSince1970: 3000))
            model.fights.append(newer)
            check(detail.fight.id == historical.id, "A refreshed series does not replace the open historical result")
            model.fights = [historical, current]
        } else {
            check(false, "The selected history destination exists")
        }
        model.openFightID = nil
        model.tab = .feed
        actions.openFeed(UUID(uuidString: historical.id)!)
        for _ in 0..<10_000 { if model.openFightID != nil { break }; await Task.yield() }
        check(model.openFightID == current.id, "Feed navigation still opens the current round")
        if let id = model.openFightID, let routed = actions.destination(id: id) {
            check(DetailState(model: model, initialFight: routed).fight.id == current.id, "Normal detail navigation is not pinned to old history")
        }
        precondition(failures.isEmpty, failures.joined(separator: "\n"))
        print("Profile navigation: exact history, refresh, normal navigation, custom and DST rematches passed")
    }
}

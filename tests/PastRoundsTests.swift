import Foundation

// PRODUCTION_MODELS

enum FFTab { case fights, you }

@MainActor final class AppModel {
    var fights: [Fight] = []
    var pendingJoinable: Fight?
    var hostedRounds: [Fight] = []
    var showingHosted = false
    var friendRounds: [Fight] = []
    var showingFriends = false

    // TAB_STATE
    // PRODUCTION_METHODS
}

@MainActor func tapPastRow(_ fight: Fight, model: AppModel) {
    // PAST_ROW_TAP
}

@main struct PastRoundsTests {
    @MainActor static func main() async {
        let you = Person(id: "you", name: "You", handle: "@you", initials: "Y", isYou: true)
        let ana = Person(id: "ana", name: "Ana", handle: "@ana", initials: "A")
        let seriesStart = Date(timeIntervalSince1970: 1_800_000_000)
        let week = 7.0 * 86_400
        func round(
            _ id: String, series: String?, week index: Int, _ status: FightStatus,
            you youStanding: Standing? = Standing(person: you, score: 9_000, rank: 1)
        ) -> Fight {
            Fight(
                id: id, name: "Croissant run", metric: .steps, lengthDays: 7, actionText: "",
                status: status, rank: 1, of: 2, kickerEmphasis: "", listSubtitle: "",
                standings: [youStanding, Standing(person: ana, score: 1_000, rank: 2)].compactMap { $0 },
                windowStart: seriesStart.addingTimeInterval(Double(index) * week),
                windowEnd: seriesStart.addingTimeInterval(Double(index + 1) * week),
                serverState: status == .live ? "live" : "final", seriesId: series
            )
        }
        let weekly = [
            round("weekly-0", series: "weekly", week: 0, .finished),
            round("weekly-1", series: "weekly", week: 1, .finished),
            round("weekly-2", series: "weekly", week: 2, .finished),
            round("weekly-3", series: "weekly", week: 3, .live),
        ]
        let model = AppModel()
        model.fights = weekly

        precondition(model.live.map(\.id) == ["weekly-3"], "Current shows one card for the weekly fight")
        precondition(model.finished.map(\.id) == ["weekly-2", "weekly-1", "weekly-0"],
                     "Past shows every finished round of the weekly fight, newest first")

        for row in model.finished {
            model.openFightID = nil
            tapPastRow(row, model: model)
            for _ in 0..<1_000 where model.openFightID == nil { await Task.yield() }
            precondition(model.openFightID.flatMap(model.detailFight(for:))?.id == row.id,
                         "Tapping \(row.id) opens that round, not the live one")
            model.fights = weekly.reversed()
            precondition(model.openFightID.flatMap(model.detailFight(for:))?.id == row.id,
                         "\(row.id) stays open after a refresh")
        }

        let invited = Standing(person: you, score: 0, invited: true)
        let deferred = Standing(person: you, score: 0, deferred: true)
        model.fights = weekly + [
            round("suggested-0", series: "suggested", week: 0, .finished, you: invited),
            round("suggested-1", series: "suggested", week: 1, .finished, you: invited),
            round("app-wide-0", series: "app-wide", week: 0, .finished, you: nil),
            round("app-wide-1", series: "app-wide", week: 1, .live, you: invited),
            round("joined-late-0", series: "joined-late", week: 0, .pending, you: deferred),
            round("joined-late-1", series: "joined-late", week: 1, .live),
            round("one-off", series: nil, week: 1, .finished, you: invited),
        ]
        precondition(Set(model.finished.map(\.id)) == ["weekly-0", "weekly-1", "weekly-2", "suggested-1", "one-off"],
                     "Extra rounds need you as a member; each series still keeps the round it showed before")
        precondition(Set(model.live.map(\.id)) == ["weekly-3", "app-wide-1", "joined-late-1"],
                     "Current still shows one round per series")
        print("PASS: Past lists every finished round you played, and each row opens its own round")
    }
}

import Foundation

// PRODUCTION_MODELS

@MainActor final class AppModel {
    var fights: [Fight] = []

    // PRODUCTION_METHODS
}

@main struct TrophyStreakTests {
    @MainActor static func main() {
        let ana = Person(id: "ana", name: "Ana", handle: "@ana", initials: "A")
        let ben = Person(id: "ben", name: "Ben", handle: "@ben", initials: "B")
        let seriesStart = Date(timeIntervalSince1970: 1_800_000_000)
        // Rounds follow the server schedule: each one starts when the previous one ends.
        func round(_ index: Int, _ winners: [Person], state: String = "final") -> Fight {
            let standings = [ana, ben].map { person in
                Standing(person: person, score: winners.contains(person) ? 9_000 : 1_000, rank: winners.contains(person) ? 1 : 2)
            }
            return Fight(
                id: "round-\(index)", name: "Steps Fight", metric: .steps, lengthDays: 1, actionText: "",
                status: state == "live" ? .live : .finished, rank: 1, of: 2, kickerEmphasis: "", listSubtitle: "",
                standings: standings,
                windowStart: seriesStart.addingTimeInterval(Double(index) * 86_400),
                windowEnd: seriesStart.addingTimeInterval(Double(index + 1) * 86_400),
                serverState: state, seriesId: "series"
            )
        }
        let model = AppModel()
        func streak(_ rounds: [Fight], for fight: Fight) -> String {
            model.fights = rounds + [fight]
            return model.trophyStreak(for: fight).map { "\($0.userId) x\($0.count)" } ?? "none"
        }
        let current = round(3, [], state: "live")

        precondition(streak([round(0, [ana]), round(1, [ana]), round(2, [ana])], for: current) == "ana x3",
                     "Consecutive wins count every round")
        precondition(streak([round(0, [ben]), round(1, [ana]), round(2, [ana])], for: current) == "ana x2",
                     "A different earlier winner ends the streak")
        precondition(streak([round(0, [ana]), round(2, [ana])], for: current) == "ana x1",
                     "A round missing from this user's snapshot ends the streak")
        precondition(streak([round(0, [ana]), round(1, [ana])], for: current) == "none",
                     "Only the directly preceding round can hold the trophy")
        precondition(streak([round(0, [ana]), round(1, [ana]), round(2, [], state: "cancelled")], for: current) == "none",
                     "A cancelled previous round leaves no trophy")
        precondition(streak([round(0, [ana]), round(1, [], state: "cancelled"), round(2, [ana])], for: current) == "ana x1",
                     "A cancelled round ends the streak instead of being skipped")
        precondition(streak([round(0, [ana]), round(1, [ana, ben])], for: round(2, [], state: "live")) == "none",
                     "A tied previous round has no single winner")
        precondition(streak([round(0, [ana]), round(1, [ana]), round(3, [ana])], for: round(2, [ben])) == "ben x1",
                     "A final round's own winner holds its trophy, counting only rounds up to it")
        precondition(streak([round(0, [ana]), round(1, [ana])], for: round(2, [ana])) == "ana x3",
                     "A final round counts itself in its winner's streak")
        let history = [round(0, [ana]), round(1, [ana]), round(2, [ana]), round(3, [ben]), round(4, [ana])]
        precondition(streak(history, for: round(5, [], state: "live")) == "ana x1",
                     "A loss resets the live round's count even when the holder won more rounds before")
        precondition(streak(history.filter { $0.id != "round-3" }, for: round(3, [ben])) == "ben x1",
                     "A History card puts the trophy on that round's winner, not the previous round's")
        precondition(streak([round(0, [ana])], for: round(1, [], state: "cancelled")) == "none",
                     "A cancelled round has no trophy holder")
        var single = round(0, [ana])
        single.seriesId = nil
        precondition(streak([], for: single) == "ana x1",
                     "A one-off final fight gives its winner the trophy")
        var truncated = round(2, [ana])
        truncated.windowEnd = current.windowStart.addingTimeInterval(0.000_4)
        precondition(streak([round(1, [ana]), truncated], for: current) == "ana x2",
                     "Server millisecond truncation still chains adjacent rounds")
        func mine(_ fight: Fight) -> Fight {
            var fight = fight
            fight.recurring = true
            fight.standings[0].person.isYou = true
            return fight
        }
        func lastRound(_ rounds: [Fight], for fight: Fight) -> String {
            model.fights = rounds + [fight]
            return model.lastRound(before: fight)?.id ?? "none"
        }
        let next = mine(round(3, [], state: "live"))
        precondition(lastRound([mine(round(1, [ana])), mine(round(2, [ben]))], for: next) == "round-2",
                     "The card shows the round that ended as the live one started")
        precondition(lastRound([mine(round(1, [ana]))], for: next) == "none",
                     "A round you were not in hides the card")
        precondition(lastRound([mine(round(2, [], state: "awaiting_final_sync"))], for: next) == "none",
                     "A round still settling hides the card")
        var deferred = mine(round(2, [ana]))
        deferred.standings[0].deferred = true
        precondition(lastRound([deferred], for: next) == "none",
                     "A round you only waited out hides the card")
        precondition(lastRound([mine(round(1, [ana]))], for: mine(round(2, [ana]))) == "none",
                     "A finished History round shows no card")
        print("PASS: trophy streaks follow each round's own result and stop at missing, cancelled, tied, or lost rounds")
    }
}

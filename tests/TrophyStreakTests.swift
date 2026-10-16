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
        func trophies(_ rounds: [Fight], for fight: Fight) -> String {
            model.fights = rounds + [fight]
            let counts = model.trophies(in: fight)
            return counts.isEmpty ? "none" : counts.sorted { $0.key < $1.key }.map { "\($0.key) x\($0.value)" }.joined(separator: ", ")
        }
        let current = round(3, [], state: "live")

        precondition(trophies([round(0, [ana]), round(1, [ana]), round(2, [ana])], for: current) == "ana x3",
                     "Every round won counts")
        let history = [round(0, [ana]), round(1, [ana]), round(2, [ana]), round(3, [ben]), round(4, [ana])]
        precondition(trophies(history, for: round(5, [], state: "live")) == "ana x4, ben x1",
                     "A loss does not reset a player's total, and every winner keeps their trophies")
        precondition(trophies([round(0, [ana]), round(2, [ana])], for: current) == "ana x2",
                     "A round missing from this user's snapshot is skipped")
        precondition(trophies([round(0, [ana]), round(1, [], state: "cancelled"), round(2, [ben])], for: current) == "ana x1, ben x1",
                     "A cancelled round gives no trophy")
        precondition(trophies([round(0, [ana]), round(1, [ana, ben])], for: round(2, [], state: "live")) == "ana x1",
                     "A tied round gives no trophy")
        precondition(trophies([round(0, [ana]), round(1, [], state: "awaiting_final_sync")], for: round(2, [], state: "live")) == "ana x1",
                     "A round still settling gives no trophy yet")
        precondition(trophies([round(0, [ben])], for: round(1, [], state: "live")) == "ben x1",
                     "The live round counts finished rounds only")
        precondition(trophies(history.filter { $0.id != "round-1" }, for: round(1, [ana])) == "ana x2",
                     "A History card counts its own round and earlier ones, not later ones")
        precondition(trophies(history.filter { $0.id != "round-3" }, for: round(3, [ben])) == "ana x3, ben x1",
                     "A History card shows every winner's total up to that round")
        precondition(trophies([round(0, [ana])], for: round(1, [], state: "cancelled")) == "ana x1",
                     "A cancelled round still shows the trophies won before it")
        var single = round(0, [ana])
        single.seriesId = nil
        precondition(trophies([], for: single) == "ana x1",
                     "A one-off final fight gives its winner the trophy")
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
        print("PASS: trophies count every final round each player won outright, up to the round shown")
    }
}

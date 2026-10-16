import Foundation

// PRODUCTION_MODELS

@main struct SeriesStatsTests {
    static func main() {
        let ana = Person(id: "ana", name: "Ana", handle: "@ana", initials: "A")
        let ben = Person(id: "ben", name: "Ben", handle: "@ben", initials: "B")
        let you = Person(id: "you", name: "You", handle: "@you", initials: "Y", isYou: true)
        let seriesStart = Date(timeIntervalSince1970: 1_800_000_000)
        // Three-day rounds back to back. Each person's steps per day, round by round.
        func round(_ index: Int, _ steps: [Person: [Double]], ranks: [Person: Int], state: String = "final") -> Fight {
            let people = [ana, ben, you].filter { steps[$0] != nil }
            let days = (0..<3).map { day in
                FightDay(
                    label: "Day \(day)",
                    scores: people.map { DayScore(person: $0, value: steps[$0]![day]) },
                    day: "2027-01-\(String(format: "%02d", index * 3 + day + 1))"
                )
            }
            return Fight(
                id: "round-\(index)", name: "Steps Fight", metric: .steps, lengthDays: 3, actionText: "",
                status: state == "live" ? .live : .finished, rank: 1, of: people.count, kickerEmphasis: "", listSubtitle: "",
                standings: people.map { Standing(person: $0, score: steps[$0]!.reduce(0, +), rank: ranks[$0]) },
                days: days,
                windowStart: seriesStart.addingTimeInterval(Double(index * 3) * 86_400),
                windowEnd: seriesStart.addingTimeInterval(Double(index * 3 + 3) * 86_400),
                serverState: state, seriesId: "series"
            )
        }

        let rounds = [
            // Live round: steps and days count, the result does not.
            round(3, [ana: [1_000, 1_000, 1_000], ben: [30_000, 1_000, 1_000]], ranks: [:], state: "live"),
            // Ana and Ben tie: nobody wins.
            round(2, [ana: [5_000, 5_000, 5_000], ben: [5_000, 5_000, 5_000], you: [1_000, 1_000, 1_000]],
                  ranks: [ana: 1, ben: 1, you: 3]),
            // Cancelled rounds count for nothing.
            round(9, [ana: [99_000, 99_000, 99_000], ben: [0, 0, 0]], ranks: [ana: 1, ben: 2], state: "cancelled"),
            // Ben wins by 100.
            round(1, [ana: [10_000, 10_000, 9_900], ben: [10_000, 10_000, 10_000], you: [8_000, 12_000, 8_000]],
                  ranks: [ben: 1, ana: 2, you: 3]),
            // Ana wins by 13,000 over You.
            round(0, [ana: [12_000, 12_000, 12_000], ben: [4_000, 4_000, 8_000], you: [11_000, 6_000, 6_000]],
                  ranks: [ana: 1, you: 2, ben: 3]),
        ]
        let stats = SeriesStats(rounds: rounds)
        let byName = Dictionary(uniqueKeysWithValues: stats.entries.map { ($0.person.name, $0) })

        precondition(stats.rounds == 4, "Cancelled rounds are not counted")
        precondition(stats.entries.map(\.person.name) == ["Ana", "Ben", "You"], "Everyone who raced is listed once")
        precondition(byName["Ana"]!.wins == 1 && byName["Ben"]!.wins == 1 && byName["You"]!.wins == 0,
                     "A tied first place and the live round give nobody a win")
        precondition(byName["Ana"]!.podiums == 3 && byName["You"]!.podiums == 3, "Top 3 counts final rounds only")
        precondition(byName["Ana"]!.rounds == 4 && byName["You"]!.rounds == 3, "Rounds played include the live round")
        precondition(byName["Ben"]!.steps == 30_000 + 15_000 + 30_000 + 16_000 + 2_000, "Steps add up every round")
        precondition(stats.together == stats.entries.map(\.steps).reduce(0, +), "Together is everyone's steps")
        precondition(stats.since == seriesStart, "The overview counts from the first round")
        precondition(stats.yourPlaces.map(\.rank) == [3, 3, 2] && stats.yourPlaces.map(\.round.id) == ["round-2", "round-1", "round-0"],
                     "Your places run newest first over final rounds you raced")
        precondition(stats.bestDay.holder?.name == "Ben" && stats.bestDay.value == 30_000 && stats.bestDay.you == 12_000,
                     "Best day names its holder and keeps your own best, including the live round")
        precondition(stats.bestRound.holder?.name == "Ana" && stats.bestRound.value == 36_000 && stats.bestRound.you == 28_000,
                     "Best round comes from final rounds")
        precondition(stats.closestFinish?.winner.name == "Ben" && stats.closestFinish?.margin == 100
                     && stats.closestFinish?.runnerUp.name == "Ana", "Closest finish is the smallest winning margin")
        precondition(stats.biggestWin?.winner.name == "Ana" && stats.biggestWin?.margin == 13_000
                     && stats.biggestWin?.runnerUp.name == "You", "Biggest win is the largest winning margin over the runner-up")
        let yours = SeriesStats(rounds: [round(0, [ana: [1_000, 1_000, 1_000], you: [9_000, 9_000, 9_000]], ranks: [you: 1, ana: 2])])
        precondition(yours.bestDay.holder?.isYou == true && yours.bestDay.you == 9_000, "Your own record names you")
        precondition(yours.yourPlaces.map(\.rank) == [1], "A first place is listed")

        let short = SeriesStats(rounds: [rounds[1], rounds[3]])
        precondition(short.biggestWin == nil && short.closestFinish?.margin == 100,
                     "With one decided round, only the closest finish is shown")
        var forfeit = round(4, [ana: [5_000, 5_000, 5_000], ben: [9_000, 9_000, 9_000]], ranks: [ana: 1, ben: 2])
        forfeit.standings = forfeit.standings.map { var row = $0; row.finalStepsComplete = row.person == ana; return row }
        let walkover = SeriesStats(rounds: [forfeit, rounds[3]])
        precondition(walkover.entries.first { $0.person == ana }?.wins == 1, "A forfeit still gives the winner the round")
        precondition(walkover.closestFinish?.margin == 100 && walkover.biggestWin == nil,
                     "A forfeited runner-up's stale score is not a finish margin")
        print("PASS: series leaderboard and records count final results, every synced day, and skip ties and cancelled rounds")
    }
}

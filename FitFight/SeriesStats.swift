import Foundation

enum SeriesBoard: CaseIterable {
    case wins, podiums, steps
}

/// All-time leaderboard and records of a repeating fight, read from rounds already on the phone.
/// Wins, podiums and round records count final rounds only. Days and steps also count the live round.
/// ponytail: only rounds this user raced are in the snapshot, so a late joiner's stats start at their first round.
struct SeriesStats {
    struct Entry: Identifiable {
        let person: Person
        var rounds = 0
        var wins = 0
        var podiums = 0
        var steps = 0.0

        var id: String { person.id }

        func value(_ board: SeriesBoard) -> Double {
            switch board {
            case .wins: return Double(wins)
            case .podiums: return Double(podiums)
            case .steps: return steps
            }
        }
    }

    /// Who holds a record and when they set it, plus your own best for the same stat.
    struct Record {
        var holder: Person?
        var value = 0.0
        var start: Date?
        var end: Date?
        var you: Double?

        mutating func offer(_ person: Person, _ value: Double, from start: Date? = nil, to end: Date? = nil) {
            if person.isYou {
                you = max(you ?? value, value)
            }
            if holder == nil || value > self.value {
                holder = person
                self.value = value
                self.start = start
                self.end = end
            }
        }
    }

    /// A decided round's winning margin. `end` is the round's last day.
    struct Finish {
        let winner: Person
        let runnerUp: Person
        let margin: Double
        let start: Date
        let end: Date
    }

    var entries: [Entry] = []
    var rounds = 0
    var together = 0.0
    /// When the first round on this phone started.
    var since: Date?
    /// Your finishing place in each final round, newest first.
    var yourPlaces: [(rank: Int, round: Fight)] = []
    var bestDay = Record()
    var bestRound = Record()
    var closestFinish: Finish?
    var biggestWin: Finish?

    /// Pass the newest round first so each person keeps their current name and companion.
    init(rounds series: [Fight]) {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        // Noon, because some time zones skip midnight on their DST day.
        parser.dateFormat = "yyyy-MM-dd HH"
        var byID: [String: Entry] = [:]
        var order: [String] = []
        var days: [String: [Date: Double]] = [:]
        var finishes: [Finish] = []

        for round in series where round.serverState != "cancelled" {
            let racers = round.standings.filter { !$0.invited && !$0.deferred }
            let final = round.serverState == "final"
            rounds += 1
            since = min(since ?? round.windowStart, round.windowStart)
            for row in racers {
                if byID[row.id] == nil {
                    byID[row.id] = Entry(person: row.person)
                    order.append(row.id)
                }
                byID[row.id]?.rounds += 1
                byID[row.id]?.steps += row.score
                together += row.score
                guard final, let rank = row.rank else { continue }
                if rank <= 3 { byID[row.id]?.podiums += 1 }
                bestRound.offer(row.person, row.score, from: round.windowStart, to: round.windowEnd.addingTimeInterval(-1))
            }
            // A tied first place gives nobody the win, like the trophy.
            let leaders = racers.filter { $0.rank == 1 }
            if final, leaders.count == 1 {
                byID[leaders[0].id]?.wins += 1
            }
            if final, let rank = racers.first(where: { $0.person.isYou })?.rank {
                yourPlaces.append((rank, round))
            }
            // A racer who never sent final steps forfeits, so their stale score is not a finish.
            if final, leaders.count == 1,
               let second = racers.filter({ $0.id != leaders[0].id && $0.finalStepsComplete != false }).max(by: { $0.score < $1.score }),
               second.score <= leaders[0].score {
                finishes.append(Finish(
                    winner: leaders[0].person, runnerUp: second.person, margin: leaders[0].score - second.score,
                    start: round.windowStart, end: round.windowEnd.addingTimeInterval(-1)
                ))
            }
            for day in round.days {
                guard let key = day.day, let date = parser.date(from: key + " 12") else { continue }
                for score in day.scores where score.hasData {
                    // A civil day split across two rounds adds up to its full total.
                    days[score.person.id, default: [:]][date, default: 0] += score.value
                }
            }
        }

        closestFinish = finishes.min { $0.margin < $1.margin }
        if finishes.count > 1 {
            biggestWin = finishes.max { $0.margin < $1.margin }
        }

        for id in order {
            guard let person = byID[id]?.person, let personDays = days[id] else { continue }
            for (date, steps) in personDays.sorted(by: { $0.key < $1.key }) {
                bestDay.offer(person, steps, from: date, to: date)
            }
        }
        entries = order.compactMap { byID[$0] }
    }
}

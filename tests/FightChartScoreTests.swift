import Foundation

struct Person: Codable, Hashable { var id: String; var name: String; var isYou = false }
struct Standing {
    var person: Person; var score: Double
    var invited = false; var deferred = false
    var finalStepsComplete: Bool? = nil; var rank: Int? = nil
}
// DAY_SCORE
struct FightDay { var label: String; var scores: [DayScore] }
struct MemberRow { var userId: UUID; var stepCheckpoints: [FightStepCheckpoint]? }
enum FightStatus { case live, pending, finished }
enum Color { case unused }
struct Theme {
    var mossFill = Color.unused; var gold = Color.unused
    var emberFill = Color.unused; var mossEdge = Color.unused
    var emberText = Color.unused; var textSecondary = Color.unused
}
// CHECKPOINT_TYPE
// CHART_MODEL

enum AppModel {
    // PRODUCTION_METHODS

    static func run() {
        let a = Person(id: UUID().uuidString, name: "A")
        let b = Person(id: UUID().uuidString, name: "B")
        let encodedDay = try! JSONEncoder().encode(DayScore(person: a, value: 12000))
        var oldCacheDay = try! JSONSerialization.jsonObject(with: encodedDay) as! [String: Any]
        oldCacheDay.removeValue(forKey: "hasData")
        let oldCacheData = try! JSONSerialization.data(withJSONObject: oldCacheDay)
        precondition((try? JSONDecoder().decode(DayScore.self, from: oldCacheData)) == nil,
                     "Legacy chart caches must not decode as confirmed history")
        let standings = orderedStandings([Standing(person: a, score: 4000), Standing(person: b, score: 6000)], status: .live)
        var members = [
            MemberRow(userId: UUID(uuidString: a.id)!, stepCheckpoints: [
                FightStepCheckpoint(day: "2026-09-15", cutoffAt: "2026-09-15T18:00:00Z", steps: 4000)
            ]),
            MemberRow(userId: UUID(uuidString: b.id)!, stepCheckpoints: [
                FightStepCheckpoint(day: "2026-09-15", cutoffAt: "2026-09-15T18:00:00Z", steps: 6000)
            ])
        ]
        var model = FightDayChartModel(days: dayCards(from: members, standings: standings), standings: standings, theme: Theme())
        precondition(model.dayCount == 1)
        precondition(model.series.first?.person.id == b.id)
        precondition(model.series.map(\.total) == [6000, 4000])
        precondition(model.series.map { $0.cumulative.last! } == [6000, 4000])

        // Reproduce the old noon-start chart, including steps before the Fight.
        let unrelatedDays = [FightDay(label: "Sep 15", scores: [DayScore(person: a, value: 12000), DayScore(person: b, value: 7000)])]
        model = FightDayChartModel(days: unrelatedDays, standings: standings, theme: Theme())
        precondition(model.dayCount == 1, "Rejected calendar leftovers still plot the confirmed totals")
        precondition(model.series.map(\.daily) == [[6000], [4000]], "Unrelated calendar totals must never appear as Fight history")
        precondition(model.series.map(\.total) == [6000, 4000], "Oval always uses the ranked scores")

        members[0].stepCheckpoints = nil
        var mixed = FightDayChartModel(days: dayCards(from: members, standings: standings), standings: standings, theme: Theme())
        precondition(mixed.dayCount == 1, "A confirmed history still charts when a peer has none")
        precondition(mixed.series[0].daily == [6000])
        precondition(mixed.series[1].daily == [nil], "Legacy uploads cannot invent a daily curve")
        members[0].stepCheckpoints = [FightStepCheckpoint(day: "2026-09-15", cutoffAt: "2026-09-15T18:00:00Z", steps: 9000)]
        mixed = FightDayChartModel(days: dayCards(from: members, standings: standings), standings: standings, theme: Theme())
        precondition(mixed.dayCount == 1, "A stale history must not accompany a newer total")
        precondition(mixed.series[0].daily == [6000])
        precondition(mixed.series[1].daily == [nil])
        var none = members
        none[0].stepCheckpoints = nil
        none[1].stepCheckpoints = nil
        precondition(dayCards(from: none, standings: standings).isEmpty, "No confirmed history stays empty")
        let totals = FightDayChartModel(days: [], standings: standings, theme: Theme())
        precondition(totals.dayCount == 1, "Bars and pace still plot the same confirmed totals as the oval")
        precondition(totals.series.map(\.daily) == [[6000], [4000]])
        precondition(totals.series.map { $0.cumulative.last! } == [6000, 4000])

        members[0].stepCheckpoints = [FightStepCheckpoint(day: "2026-09-15", cutoffAt: "2026-09-15T18:00:00Z", steps: 4000)]
        members[1].stepCheckpoints = [
            FightStepCheckpoint(day: "2026-09-15", cutoffAt: "2026-09-15T22:00:00Z", steps: 5000),
            FightStepCheckpoint(day: "2026-09-16", cutoffAt: "2026-09-16T12:00:00Z", steps: 6000)
        ]
        model = FightDayChartModel(days: dayCards(from: members, standings: standings), standings: standings, theme: Theme())
        precondition(model.dayCount == 2, "The graph ends at the latest saved day, without future zeros")
        precondition(model.series[1].daily[1] == nil, "A participant who has not synced has missing data, not zero steps")
        precondition(model.series[1].cumulative == [4000, 4000], "The cumulative curve keeps the last confirmed total")
        precondition(model.series[0].daily == [5000, 1000])

        let correctedStandings = orderedStandings([Standing(person: a, score: 4000), Standing(person: b, score: 3000)], status: .live)
        members[1].stepCheckpoints = [
            FightStepCheckpoint(day: "2026-09-15", cutoffAt: "2026-09-15T22:00:00Z", steps: 2000),
            FightStepCheckpoint(day: "2026-09-16", cutoffAt: "2026-09-16T12:00:00Z", steps: 3000)
        ]
        model = FightDayChartModel(days: dayCards(from: members, standings: correctedStandings), standings: correctedStandings, theme: Theme())
        precondition(model.series.first?.person.id == a.id, "A late correction changes the graph and standings together")
        precondition(model.series[1].daily == [2000, 1000])

        let final = orderedStandings([
            Standing(person: a, score: 4000, rank: 2), Standing(person: b, score: 3000, rank: 1)
        ], status: .finished)
        model = FightDayChartModel(days: dayCards(from: members, standings: final), standings: final, theme: Theme())
        precondition(model.series.first?.person.id == b.id, "Final forfeits keep the official ranking")
        print("Fight charts: matching totals, noon-start regression, legacy data, stale data, late sync, corrections, and final ranks passed")
    }
}

@main struct FightChartScoreTests { static func main() { AppModel.run() } }

import Foundation
import SwiftUI

enum MetricKind: String, CaseIterable, Identifiable {
    case activeMinutes
    case steps
    case workouts

    var id: String { rawValue }

    var eyebrow: String {
        switch self {
        case .activeMinutes: return "Active minutes"
        case .steps: return "Steps total"
        case .workouts: return "Workout count"
        }
    }

    var blurb: String {
        switch self {
        case .activeMinutes: return "Best cross-source metric"
        case .steps: return "Daily friend battles"
        case .workouts: return "Low-friction bragging rights"
        }
    }

    var unit: String {
        switch self {
        case .activeMinutes: return "min"
        case .steps: return "steps"
        case .workouts: return "workouts"
        }
    }
}

enum SettlementKind: String, CaseIterable, Identifiable {
    case winner
    case proportional
    case goal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .winner: return "Winner takes all"
        case .proportional: return "Proportional"
        case .goal: return "Hit your goal"
        }
    }

    var blurb: String {
        switch self {
        case .winner: return "First place takes everything. Everyone else is out their stake."
        case .proportional: return "Your share of the work is your share of the pot."
        case .goal: return "Hit the daily goal and your stake comes back. Miss it and you’re funding the ones who did."
        }
    }
}

enum StakeKind: String, CaseIterable, Identifiable {
    case bragging
    case ten
    case custom

    var id: String { rawValue }
}

enum CustomStakeKind: String {
    case money
    case action
}

enum FightStatus {
    case live
    case invited
    case finished
}

struct Person: Identifiable, Hashable {
    var id: String
    var name: String
    var handle: String
    var initials: String
    var isYou: Bool = false
}

struct Standing: Identifiable, Hashable {
    var person: Person
    var score: Double
    var today: Double
    var projectedNet: Int
    var invited: Bool = false
    var safe: Bool? = nil

    var id: String { person.id }
}

struct Fight: Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var metric: MetricKind
    var daysLeft: Int? = nil
    var endedLabel: String? = nil
    var pot: Int
    var buyIn: Int
    var settlement: SettlementKind
    var status: FightStatus
    var rank: Int
    var of: Int
    var pending: Int
    var headline: String
    var dailyGoal: Double? = nil
    var standings: [Standing]
    var inviteAction: String? = nil
}

struct RequestItem: Identifiable, Hashable {
    var id: String
    var title: String
    var body: String
    var kind: Kind
    var status: Status
    var author: Person
    var ago: String
    var comments: Int
    var votes: Int

    enum Kind { case feature, bug }
    enum Status { case open, planned, shipped }
}

struct HistoryItem: Identifiable, Hashable {
    var id: String
    var name: String
    var detail: String
    var net: Int
    var won: Bool
}

final class AppModel: ObservableObject {
    @Published var tab: FFTab = .fights {
        didSet {
            if oldValue != tab {
                openFightID = nil
            }
        }
    }

    @Published var openFightID: String?
    @Published var showingVersions = false
    @Published var voted: Set<String> = ["r1"]
    @Published var joined: Set<String> = []

    let you = Person(id: "you", name: "You", handle: "@maya.moves", initials: "MM", isYou: true)
    let people: [Person]
    let fights: [Fight]
    let requests: [RequestItem]
    let history: [HistoryItem]

    init() {
        let leo = Person(id: "leo", name: "Leo", handle: "@leo.runs", initials: "L")
        let sam = Person(id: "sam", name: "Sam", handle: "@sam.moves", initials: "S")
        let ivy = Person(id: "ivy", name: "Ivy", handle: "@ivy.climbs", initials: "I")
        let theo = Person(id: "theo", name: "Theo", handle: "@theo", initials: "T")
        let nina = Person(id: "nina", name: "Nina", handle: "@nina", initials: "N")
        people = [leo, sam, ivy, theo, nina]

        let you = Person(id: "you", name: "You", handle: "@maya.moves", initials: "MM", isYou: true)

        fights = [
            Fight(
                id: "sweat",
                code: "FIGHT-742",
                name: "7-Day Sweat Ladder",
                metric: .activeMinutes,
                daysLeft: 4,
                pot: 30,
                buyIn: 10,
                settlement: .winner,
                status: .live,
                rank: 2,
                of: 3,
                pending: 0,
                headline: "12 min behind Leo",
                standings: [
                    Standing(person: leo, score: 54, today: 18, projectedNet: 20),
                    Standing(person: you, score: 42, today: 11, projectedNet: -10),
                    Standing(person: sam, score: 37, today: 9, projectedNet: -10)
                ]
            ),
            Fight(
                id: "derby",
                code: "FIGHT-801",
                name: "Step Derby",
                metric: .steps,
                daysLeft: 2,
                pot: 50,
                buyIn: 10,
                settlement: .proportional,
                status: .live,
                rank: 1,
                of: 5,
                pending: 1,
                headline: "Holding 1st with 2d to go",
                standings: [
                    Standing(person: you, score: 61200, today: 8400, projectedNet: 1),
                    Standing(person: ivy, score: 54800, today: 6100, projectedNet: -4),
                    Standing(person: theo, score: 49100, today: 5200, projectedNet: -8),
                    Standing(person: nina, score: 22000, today: 0, projectedNet: -10, invited: true)
                ]
            ),
            Fight(
                id: "club",
                code: "FIGHT-655",
                name: "10K Club",
                metric: .steps,
                daysLeft: 3,
                pot: 80,
                buyIn: 20,
                settlement: .goal,
                status: .live,
                rank: 2,
                of: 4,
                pending: 2,
                headline: "3.2k steps behind Sam",
                dailyGoal: 10000,
                standings: [
                    Standing(person: sam, score: 44800, today: 12100, projectedNet: 7, safe: true),
                    Standing(person: you, score: 41600, today: 8240, projectedNet: 7, safe: true),
                    Standing(person: nina, score: 28100, today: 4100, projectedNet: -20, safe: false)
                ]
            ),
            Fight(
                id: "desk",
                code: "FIGHT-220",
                name: "Desk Job Revenge",
                metric: .activeMinutes,
                daysLeft: 5,
                pot: 0,
                buyIn: 0,
                settlement: .winner,
                status: .invited,
                rank: 0,
                of: 2,
                pending: 0,
                headline: "Leo · 5 days",
                inviteAction: "Accept",
                standings: [
                    Standing(person: leo, score: 0, today: 0, projectedNet: 0)
                ]
            ),
            Fight(
                id: "sprint",
                code: "FIGHT-221",
                name: "City Sprint",
                metric: .steps,
                daysLeft: 3,
                pot: 20,
                buyIn: 10,
                settlement: .winner,
                status: .invited,
                rank: 0,
                of: 3,
                pending: 0,
                headline: "Ivy · 3 days",
                inviteAction: "Join",
                standings: [
                    Standing(person: ivy, score: 0, today: 0, projectedNet: 0)
                ]
            ),
            Fight(
                id: "weekend",
                code: "FIGHT-109",
                name: "Weekend Step Duel",
                metric: .steps,
                endedLabel: "Ended Jul 13",
                pot: 20,
                buyIn: 10,
                settlement: .winner,
                status: .finished,
                rank: 1,
                of: 2,
                pending: 0,
                headline: "1st of 2",
                standings: [
                    Standing(person: you, score: 24000, today: 0, projectedNet: 10),
                    Standing(person: sam, score: 18100, today: 0, projectedNet: -10)
                ]
            )
        ]

        requests = [
            RequestItem(
                id: "r1",
                title: "Apple Watch live rings on the fight card",
                body: "See today’s close without opening Health. The card should move as the day does.",
                kind: .feature,
                status: .planned,
                author: leo,
                ago: "3d ago",
                comments: 8,
                votes: 24
            ),
            RequestItem(
                id: "r2",
                title: "Split pots when two people finish tied",
                body: "Winner-takes-all currently panics on a tie. Split the pot and call it a day.",
                kind: .feature,
                status: .open,
                author: ivy,
                ago: "1w ago",
                comments: 5,
                votes: 18
            ),
            RequestItem(
                id: "r3",
                title: "Strava ride doesn’t land on the same day",
                body: "Evening rides sometimes show up tomorrow and wreck the daily goal.",
                kind: .bug,
                status: .open,
                author: theo,
                ago: "2d ago",
                comments: 3,
                votes: 11
            )
        ]

        history = [
            HistoryItem(id: "weekend", name: "Weekend Step Duel", detail: "Ended Jul 13 · 1st of 2", net: 10, won: true)
        ]
    }

    func fight(id: String) -> Fight? {
        fights.first { $0.id == id }
    }

    var live: [Fight] { fights.filter { $0.status == .live } }
    var invitations: [Fight] { fights.filter { $0.status == .invited } }
    var finished: [Fight] { fights.filter { $0.status == .finished } }

    var projectedNet: Int {
        live.reduce(0) { $0 + (youStanding(in: $1)?.projectedNet ?? 0) }
    }

    func youStanding(in fight: Fight) -> Standing? {
        fight.standings.first { $0.person.isYou }
    }

    func formatScore(_ value: Double, metric: MetricKind) -> String {
        switch metric {
        case .activeMinutes, .workouts:
            return String(format: "%.0f", value)
        case .steps:
            if value >= 1000 {
                return String(format: "%.1fk", value / 1000)
            }
            return String(format: "%.0f", value)
        }
    }
}

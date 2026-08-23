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

    var title: String {
        switch self {
        case .activeMinutes: return "Active Minutes"
        case .steps: return "Steps Total"
        case .workouts: return "Workout Count"
        }
    }

    var blurb: String {
        switch self {
        case .activeMinutes: return "Best cross-source metric"
        case .steps: return "Daily friend battles"
        case .workouts: return "Low-friction bragging rights"
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
        case .proportional: return "Your share of the effort is your share of the pot — do 60% of the steps, take 60% of the money."
        case .goal: return "Hit your daily goal and your money comes back. Miss it and it goes to whoever made it."
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

struct DayScore: Identifiable, Hashable {
    var person: Person
    var value: Double

    var id: String { person.id }
}

struct FightDay: Identifiable, Hashable {
    var label: String
    var scores: [DayScore]

    var id: String { label }
}

struct Fight: Identifiable, Hashable {
    var id: String
    var code: String
    var name: String
    var metric: MetricKind
    var lengthDays: Int
    var daysLeft: Int? = nil
    var endedLabel: String? = nil
    var pot: Int
    var buyIn: Int
    var settlement: SettlementKind
    var status: FightStatus
    var rank: Int
    var of: Int
    var pending: Int
    var kickerPrefix: String = ""
    var kickerEmphasis: String
    var kickerRest: String = ""
    var listSubtitle: String
    var payoutLine: String
    var invitePitch: String? = nil
    var inviteAction: String? = nil
    var paceNote: String? = nil
    var standingsMeta: String? = nil
    var dailyGoal: Double? = nil
    var standings: [Standing]
    var days: [FightDay] = []
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
    @Published var voted: Set<String> = ["r1", "r3", "r6"]
    @Published var joined: Set<String> = []

    let you = Person(id: "you", name: "You", handle: "@maya.moves", initials: "MM", isYou: true)
    let people: [Person]
    let fights: [Fight]
    let requests: [RequestItem]
    let history: [HistoryItem]

    init() {
        let leo = Person(id: "leo", name: "Leo", handle: "@leo.runs", initials: "L")
        let sam = Person(id: "sam", name: "Sam", handle: "@sam.sweats", initials: "S")
        let ivy = Person(id: "ivy", name: "Ivy", handle: "@ivy.climbs", initials: "I")
        let theo = Person(id: "theo", name: "Theo", handle: "@theo.rows", initials: "T")
        let nina = Person(id: "nina", name: "Nina", handle: "@nina.lifts", initials: "N")
        people = [leo, sam, nina, theo, ivy]

        let you = Person(id: "you", name: "You", handle: "@maya.moves", initials: "MM", isYou: true)

        fights = [
            Fight(
                id: "sweat",
                code: "FIGHT-742",
                name: "7-Day Sweat Ladder",
                metric: .activeMinutes,
                lengthDays: 7,
                daysLeft: 4,
                pot: 30,
                buyIn: 10,
                settlement: .winner,
                status: .live,
                rank: 2,
                of: 3,
                pending: 0,
                kickerEmphasis: "12 min",
                kickerRest: "behind Leo",
                listSubtitle: "12 min behind Leo",
                payoutLine: "Winner takes the whole $30",
                paceNote: "At this pace you finish on 98 min.",
                standings: [
                    Standing(person: leo, score: 54, today: 16, projectedNet: 20),
                    Standing(person: you, score: 42, today: 14, projectedNet: -10),
                    Standing(person: sam, score: 37, today: 12, projectedNet: -10)
                ],
                days: [
                    FightDay(label: "Day 1", scores: [
                        DayScore(person: leo, value: 20),
                        DayScore(person: you, value: 12),
                        DayScore(person: sam, value: 15)
                    ]),
                    FightDay(label: "Day 2", scores: [
                        DayScore(person: leo, value: 18),
                        DayScore(person: you, value: 16),
                        DayScore(person: sam, value: 10)
                    ]),
                    FightDay(label: "Day 3", scores: [
                        DayScore(person: leo, value: 16),
                        DayScore(person: you, value: 14),
                        DayScore(person: sam, value: 12)
                    ])
                ]
            ),
            Fight(
                id: "derby",
                code: "FIGHT-118",
                name: "Step Derby",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 2,
                pot: 50,
                buyIn: 10,
                settlement: .proportional,
                status: .live,
                rank: 1,
                of: 5,
                pending: 1,
                kickerPrefix: "Holding",
                kickerEmphasis: "1st",
                kickerRest: "with 2d to go",
                listSubtitle: "Holding 1st with 2d to go",
                payoutLine: "Your share of the steps is your share of the pot — 60% pays $30",
                standings: [
                    Standing(person: you, score: 61400, today: 8200, projectedNet: 1),
                    Standing(person: ivy, score: 59800, today: 6100, projectedNet: 1),
                    Standing(person: theo, score: 55200, today: 5200, projectedNet: 0),
                    Standing(person: leo, score: 40100, today: 4800, projectedNet: -8),
                    Standing(person: nina, score: 22000, today: 0, projectedNet: -10, invited: true)
                ]
            ),
            Fight(
                id: "club",
                code: "FIGHT-655",
                name: "10K Club",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 3,
                pot: 80,
                buyIn: 20,
                settlement: .goal,
                status: .live,
                rank: 2,
                of: 4,
                pending: 2,
                kickerEmphasis: "3.2k steps",
                kickerRest: "behind Sam",
                listSubtitle: "3.2k steps behind Sam",
                payoutLine: "Hit 10.0k steps/day and your $20 comes back",
                dailyGoal: 10000,
                standings: [
                    Standing(person: sam, score: 44800, today: 12100, projectedNet: 7, safe: true),
                    Standing(person: you, score: 41600, today: 8240, projectedNet: 7, safe: true),
                    Standing(person: nina, score: 31900, today: 4100, projectedNet: -20, safe: false),
                    Standing(person: ivy, score: 28100, today: 3900, projectedNet: -20, safe: false)
                ]
            ),
            Fight(
                id: "desk",
                code: "FIGHT-556",
                name: "Desk Job Revenge",
                metric: .steps,
                lengthDays: 5,
                daysLeft: 5,
                pot: 50,
                buyIn: 10,
                settlement: .winner,
                status: .invited,
                rank: 0,
                of: 4,
                pending: 2,
                kickerEmphasis: "Theo wants a piece of you",
                listSubtitle: "Theo · 5 days · $50 pot",
                payoutLine: "Winner takes the whole $50",
                invitePitch: "Theo wants a piece of you",
                inviteAction: "Accept",
                standingsMeta: "2 in · 2 not replied",
                standings: [
                    Standing(person: theo, score: 0, today: 0, projectedNet: 40),
                    Standing(person: nina, score: 0, today: 0, projectedNet: -10),
                    Standing(person: ivy, score: 0, today: 0, projectedNet: 0, invited: true)
                ]
            ),
            Fight(
                id: "sprint",
                code: "FIGHT-221",
                name: "City Sprint",
                metric: .steps,
                lengthDays: 7,
                daysLeft: 7,
                pot: 0,
                buyIn: 0,
                settlement: .winner,
                status: .invited,
                rank: 0,
                of: 3,
                pending: 0,
                kickerEmphasis: "Ivy wants a piece of you",
                listSubtitle: "Ivy · 7 days · No stake",
                payoutLine: "Bragging rights only",
                invitePitch: "Ivy wants a piece of you",
                inviteAction: "Join",
                standings: [
                    Standing(person: ivy, score: 0, today: 0, projectedNet: 0)
                ]
            ),
            Fight(
                id: "weekend",
                code: "FIGHT-088",
                name: "Weekend Step Duel",
                metric: .steps,
                lengthDays: 2,
                endedLabel: "Ended Jul 13",
                pot: 20,
                buyIn: 10,
                settlement: .winner,
                status: .finished,
                rank: 1,
                of: 2,
                pending: 0,
                kickerPrefix: "Leading by",
                kickerEmphasis: "2.2k steps",
                listSubtitle: "Ended Jul 13 · 1st of 2",
                payoutLine: "Winner takes the whole $20",
                standingsMeta: "2 in",
                standings: [
                    Standing(person: you, score: 24100, today: 0, projectedNet: 10),
                    Standing(person: leo, score: 21900, today: 0, projectedNet: -10)
                ]
            )
        ]

        requests = [
            RequestItem(
                id: "r1",
                title: "Custom challenge length",
                body: "Let me pick any number of days, not just 3 / 7 / 14.",
                kind: .feature,
                status: .planned,
                author: leo,
                ago: "3d ago",
                comments: 12,
                votes: 83
            ),
            RequestItem(
                id: "r2",
                title: "Team fights, 2 v 2",
                body: "Me and my wife against another couple. Scores add up per team.",
                kind: .feature,
                status: .open,
                author: nina,
                ago: "5d ago",
                comments: 9,
                votes: 71
            ),
            RequestItem(
                id: "r3",
                title: "Strava ride counted twice",
                body: "A ride synced from both Apple Health and Strava and I got double minutes.",
                kind: .bug,
                status: .planned,
                author: theo,
                ago: "1d ago",
                comments: 7,
                votes: 62
            ),
            RequestItem(
                id: "r4",
                title: "Rest days that don’t break a streak",
                body: "One planned rest day per week should not reset the streak counter.",
                kind: .feature,
                status: .open,
                author: ivy,
                ago: "1w ago",
                comments: 5,
                votes: 48
            ),
            RequestItem(
                id: "r5",
                title: "Apple Watch live standings",
                body: "A complication showing my position without opening the phone.",
                kind: .feature,
                status: .open,
                author: sam,
                ago: "1w ago",
                comments: 3,
                votes: 39
            ),
            RequestItem(
                id: "r6",
                title: "Pot shows the old amount after someone joins",
                body: "Joined a fight, the pot on the card kept the pre-join number until I killed the app.",
                kind: .bug,
                status: .shipped,
                author: Person(id: "maya", name: "Maya", handle: "@maya.moves", initials: "MM", isYou: true),
                ago: "2w ago",
                comments: 4,
                votes: 26
            ),
            RequestItem(
                id: "r7",
                title: "Pause a fight when you’re ill",
                body: "Freeze the clock for everyone rather than forcing a forfeit.",
                kind: .feature,
                status: .open,
                author: leo,
                ago: "2w ago",
                comments: 8,
                votes: 22
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

    func formatDelta(_ value: Double, metric: MetricKind) -> String {
        let body = formatScore(value, metric: metric)
        if value > 0 { return "+\(body)" }
        if value < 0 { return "−\(body)" }
        return body
    }

    func projectedPace(_ row: Standing, in fight: Fight) -> Double {
        let elapsed = max(1, fight.lengthDays - (fight.daysLeft ?? 0))
        return row.score * Double(fight.lengthDays) / Double(elapsed)
    }

    func paceLine(_ row: Standing, in fight: Fight) -> String {
        if row.invited { return "Hasn’t joined yet" }
        if fight.status == .invited {
            switch fight.metric {
            case .activeMinutes: return "on pace for 0 min"
            case .steps: return "on pace for 0 steps"
            case .workouts: return "0 so far"
            }
        }
        let pace = projectedPace(row, in: fight)
        switch fight.metric {
        case .activeMinutes:
            return "on pace for \(Int(pace.rounded())) min"
        case .steps:
            return "on pace for \(formatScore(pace, metric: .steps))"
        case .workouts:
            return "\(Int(row.score)) so far"
        }
    }
}

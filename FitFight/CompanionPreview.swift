import Foundation
import SwiftUI

enum CompanionPreview {
    static let isEnabled: Bool = {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--companion-preview")
            || ProcessInfo.processInfo.environment["FF_COMPANION_PREVIEW"] == "1"
        #else
        false
        #endif
    }()

    static var writeUnavailable: String {
        String(appLocalized: "Preview only. No fight, post, account or Health data is changed.")
    }

    /// Marc's fixture account, so You and profiles load sample data in the preview.
    static var youID: UUID? { isEnabled ? UUID(uuidString: "C0000000-0000-4000-8000-000000000001") : nil }

    struct WriteUnavailable: LocalizedError {
        var errorDescription: String? { CompanionPreview.writeUnavailable }
    }
}

#if DEBUG && targetEnvironment(simulator)
extension CompanionPreview {
    static let people = [
        Person(id: "C0000000-0000-4000-8000-000000000001", name: "Marc", handle: "@marc", initials: "ML", isYou: true),
        Person(id: "C0000000-0000-4000-8000-000000000002", name: "Bertille", handle: "@bertille", initials: "BE"),
        Person(id: "C0000000-0000-4000-8000-000000000003", name: "Nico", handle: "@nico", initials: "NI"),
        Person(id: "C0000000-0000-4000-8000-000000000004", name: "Léa", handle: "@lea", initials: "LE"),
        Person(id: "C0000000-0000-4000-8000-000000000005", name: "Hugo", handle: "@hugo", initials: "HU"),
    ]
    static let animals: [String: StockCompanion] = Dictionary(uniqueKeysWithValues:
        zip(people, [StockCompanion.badger, .fox, .turtle, .rabbit, .dog])
            .map { ($0.id.lowercased(), $1) }
    )
    static let groupID = "F0000000-0000-4000-8000-000000000001"
    static let duelID = "F0000000-0000-4000-8000-000000000002"
    static let invitationID = "F0000000-0000-4000-8000-000000000004"

    enum DisplayState: String, CaseIterable, Identifiable {
        case populated, tied, solo, deferred, pending, finished, empty, loading, offline
        var id: String { rawValue }
        var title: String {
            switch self {
            case .populated: String(appLocalized: "Populated")
            case .tied: String(appLocalized: "Tied")
            case .solo: String(appLocalized: "Solo")
            case .deferred: String(appLocalized: "Next round")
            case .pending: String(appLocalized: "Pending final sync")
            case .finished: String(appLocalized: "Finished")
            case .empty: String(appLocalized: "Empty")
            case .loading: String(appLocalized: "Loading")
            case .offline: String(appLocalized: "Cached / offline")
            }
        }
    }

    /// Uses the existing native fixture shape, with consistent UUIDs and exact windows.
    @MainActor
    static func model(state: DisplayState = .populated) -> AppModel {
        let model = AppModel(preview: ())
        let template = model.fights[0]
        let now = Date()
        let french = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true
        model.you = people[0]

        func fight(_ index: Int, name: String, code: String, totals: [Double], cast: [Person], length: Int, hoursLeft: Int) -> Fight {
            var fight = template
            fight.id = "F0000000-0000-4000-8000-\(String(format: "%012d", index))"
            fight.name = name
            fight.joinCode = code
            fight.lengthDays = length
            fight.windowEnd = now.addingTimeInterval(Double(hoursLeft) * 3_600)
            fight.windowStart = fight.windowEnd.addingTimeInterval(-Double(length) * 86_400)
            fight.daysLeft = max(0, hoursLeft / 24)
            fight.of = cast.count
            fight.standings = zip(cast, totals).enumerated().map { index, entry in
                Standing(person: entry.0, score: entry.1,
                         lastSyncedAt: now.addingTimeInterval(-Double(index + 1) * 300),
                         rank: 1 + totals.filter { $0 > entry.1 }.count)
            }.sorted { $0.score > $1.score }
            fight.rank = fight.standings.first { $0.person.isYou }?.rank ?? 0
            let gap = (totals.first ?? 0) - (totals.dropFirst().max() ?? 0)
            fight.kickerEmphasis = "\(gap >= 0 ? "+" : "−")\(abs(gap).formatted(.number.precision(.fractionLength(0))))"
            fight.listSubtitle = fight.timeLeftLabel
            fight.actionText = french ? "Apporte des croissants pour tout le monde" : "Brings croissants for everyone"
            let dayCount = min(length, max(1, length - hoursLeft / 24))
            let weights = (0..<dayCount).map { [0.8, 1.1, 1.3, 0.9][$0 % 4] }
            let weightTotal = weights.reduce(0, +)
            fight.days = (0..<dayCount).map { day in
                let previousWeight = weights.prefix(day).reduce(0, +)
                return FightDay(label: String(appLocalized: "companion.day", defaultValue: "Day \(day + 1)"),
                         scores: zip(cast, totals).map { person, total in
                    DayScore(person: person, value:
                        (total * (previousWeight + weights[day]) / weightTotal).rounded()
                        - (total * previousWeight / weightTotal).rounded())
                })
            }
            return fight
        }

        var group = fight(1, name: french ? "La course aux croissants" : "The croissant run", code: "K7M2",
                          totals: [28_430, 25_590, 22_340, 20_840], cast: Array(people.prefix(4)), length: 7, hoursLeft: 54)
        group.recurring = true
        group.seriesId = "A0000000-0000-4000-8000-000000000001"
        group.inviter = people[0]
        var duel = fight(2, name: french ? "Sans ascenseur, sans pitié" : "No lift, no mercy", code: "H8P4",
                         totals: [18_420, 19_680], cast: [people[0], people[4]], length: 7, hoursLeft: 124)
        duel.actionText = french ? "Prend les escaliers toute la semaine" : "Takes the stairs all next week"
        var weekend = fight(3, name: french ? "Les marcheurs du week-end" : "Weekend wanderers", code: "R3V6",
                            totals: [12_680, 11_820, 11_240, 10_740], cast: Array(people.prefix(4)), length: 3, hoursLeft: 32)
        weekend.actionText = french ? "Organise la prochaine balade du dimanche" : "Plans our next Sunday walk"
        var invite = fight(4, name: french ? "Le club du petit-déjeuner" : "The breakfast club", code: "B4K9",
                           totals: [0, 0], cast: [people[0], people[3]], length: 3, hoursLeft: 60)
        invite.status = .invited
        invite.inviter = people[3]
        invite.invitePitch = String(appLocalized: "companion.invitation", defaultValue: "\(people[3].name) invited you")
        invite.standings[0].invited = true
        invite.recurring = true
        invite.offersJoinNext = true
        invite.listSubtitle = String(appLocalized: "3-day Steps fight")
        var finished = fight(5, name: french ? "Le café est pour toi" : "Coffee is on you", code: "C9F2",
                             totals: [24_100, 21_900], cast: [people[0], people[4]], length: 3, hoursLeft: -96)
        finished.status = .finished
        finished.serverState = "final"
        finished.standings = finished.standings.map { var row = $0; row.finalStepsComplete = true; return row }
        // Five finished rounds won by Marc, so the live round shows a trophy ×5.
        let history = (1...5).map { round in
            var history = group
            history.id = "F0000000-0000-4000-8000-\(String(format: "%012d", 5 + round))"
            history.windowEnd = group.windowStart.addingTimeInterval(-Double(round - 1) * 7 * 86_400)
            history.windowStart = history.windowEnd.addingTimeInterval(-7 * 86_400)
            history.status = .finished
            history.serverState = "final"
            history.standings = history.standings.map { var row = $0; row.finalStepsComplete = true; return row }
            return history
        }

        switch state {
        case .populated, .offline:
            model.fights = [group, duel, weekend, invite, finished] + history
        case .empty, .loading:
            model.fights = []
        case .tied:
            duel.standings = duel.standings.map { var row = $0; row.score = 18_420; row.rank = 1; return row }
            duel.rank = 1
            duel.kickerEmphasis = String(appLocalized: "Tied")
            model.fights = [duel]
        case .solo:
            duel.standings = duel.standings.filter { $0.person.isYou }
            duel.rank = 1
            duel.of = 1
            model.fights = [duel]
        case .deferred:
            group.standings = group.standings.map { var row = $0; row.deferred = row.person.isYou; return row }
            model.fights = [group] + history
        case .pending:
            duel.status = .pending
            duel.serverState = "awaiting_final_sync"
            duel.windowEnd = now.addingTimeInterval(-3_600)
            duel.windowStart = duel.windowEnd.addingTimeInterval(-7 * 86_400)
            duel.graceEndsAt = now.addingTimeInterval(23 * 3_600)
            duel.kickerEmphasis = String(appLocalized: "Pending final sync")
            duel.listSubtitle = String(appLocalized: "Pending final sync")
            duel.standings = duel.standings.map { var row = $0; row.finalStepsComplete = !row.person.isYou; return row }
            model.fights = [duel]
        case .finished:
            model.fights = [finished]
        }
        return model
    }

    @MainActor
    static func posts(fightID: UUID? = nil) -> [FitFightFightPost] {
        let french = Bundle.main.preferredLocalizations.first?.hasPrefix("fr") == true
        let postFightID = fightID ?? UUID(uuidString: groupID)!
        let fightName = model().fight(id: postFightID.uuidString)!.listTitle
        let authors = [people[1], people[3], people[0]]
        // Keep a French post in the English preview so the translation icon can be inspected.
        let bodies = french
            ? ["Le grand détour par la boulangerie valait le coup.", "Qui est partant pour une balade dimanche ?", "Une petite pause dehors entre deux réunions."]
            : ["Le grand détour par la boulangerie valait le coup.", "Who’s up for a walk on Sunday?", "A little time outside between meetings."]
        return authors.enumerated().map { index, person in
            FitFightFightPost(
                id: UUID(uuidString: "D0000000-0000-4000-8000-\(String(format: "%012d", index + 1))")!,
                audience: "fight", fightId: postFightID,
                fightName: fightName,
                body: bodies[index], createdAt: Date().addingTimeInterval(-Double(index + 1) * 1_200).ISO8601Format(),
                author: .init(userId: UUID(uuidString: person.id)!, handle: String(person.handle.dropFirst()), displayName: person.name, avatar: nil),
                media: [], tags: [], reactions: index == 0
                    ? [.init(emoji: "🔥", count: 1, mine: true), .init(emoji: "👏", count: 3, mine: false)]
                    : [.init(emoji: "👏", count: 3 - index, mine: false)],
                commentCount: index == 0 ? 2 : 0, mine: person.isYou,
                broadcast: false, channels: [.init(fightId: postFightID, name: fightName)]
            )
        }
    }

    static func comments(postID: UUID) -> [FitFightFightPostComment] {
        let firstID = UUID(uuidString: "E0000000-0000-4000-8000-000000000001")!
        return [people[0], people[1]].enumerated().map { index, person in
            FitFightFightPostComment(
                id: index == 0 ? firstID : UUID(uuidString: "E0000000-0000-4000-8000-000000000002")!,
                postId: postID, parentId: index == 0 ? nil : firstID,
                body: index == 0 ? String(appLocalized: "See you on Sunday! Let's take the longer route by the river.") : String(appLocalized: "Count me in!"),
                createdAt: Date().addingTimeInterval(-600).ISO8601Format(),
                author: .init(userId: UUID(uuidString: person.id)!, handle: String(person.handle.dropFirst()), displayName: person.name, avatar: nil),
                mine: person.isYou, likeCount: index == 0 ? 2 : 1, likedByMe: index == 1
            )
        }
    }
}

struct CompanionPreviewControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var feed: FeedStore
    @EnvironmentObject private var steps: HealthKitStepsStore
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.ffTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FFScreen(clearance: false) {
            FFScreenTitle(title: String(appLocalized: "Companion preview"), subtitle: CompanionPreview.writeUnavailable)
            FFSection(title: String(appLocalized: "Display state")) {
                ForEach(CompanionPreview.DisplayState.allCases) { state in
                    FFButton(title: state.title, kind: .secondary, fullWidth: true) {
                        model.showCompanionPreviewState(state)
                        feed.posts = state == .empty || state == .loading ? [] : CompanionPreview.posts()
                        feed.isLoading = state == .loading
                        steps.setCompanionPreviewStatus(state == .empty ? .empty : state == .loading ? .reading : .steps(count: 8_432))
                        dismiss()
                    }
                }
            }
            FFSection(title: String(appLocalized: "Look")) {
                ForEach(Mode.allCases) { mode in
                    FFButton(title: mode.label, kind: .secondary, fullWidth: true) { themeStore.mode = mode }
                }
            }
            FFButton(title: String(appLocalized: "Close"), kind: .ghost, fullWidth: true) { dismiss() }
        }
    }
}
#endif

#if DEBUG && targetEnvironment(simulator)
extension CompanionPreview {
    /// 31 days of sample Steps and workout minutes, oldest first.
    static let sampleSteps: [Double] = [6_210, 9_480, 4_120, 8_760, 12_300, 7_050, 5_430, 10_900, 8_120, 3_980, 7_760, 11_450, 9_020, 6_640, 18_420, 8_310, 5_870, 9_940, 7_220, 13_150, 6_980, 8_450, 10_260, 4_760, 9_310, 12_880, 8_050, 7_430, 11_020, 9_870, 8_432]
    static let sampleWorkouts: [(String, String, [Double])] = [
        (String(appLocalized: "Run"), "figure.run", (0..<31).map { [3, 10, 17, 24, 29].contains($0) ? 32 + Double($0 % 4) * 6 : 0 }),
        (String(appLocalized: "Bike"), "bicycle", (0..<31).map { [5, 12, 19, 26].contains($0) ? 55 + Double($0 % 3) * 10 : 0 }),
        (String(appLocalized: "Swim"), "figure.pool.swim", (0..<31).map { [8, 22].contains($0) ? 30 : 0 }),
    ]

    /// Everyone but you, as friends.
    static let friendIdentities: [SharedProfileIdentity] = people.dropFirst().compactMap { person in
        let json = #"{"user_id": "\#(person.id)", "handle": "\#(person.handle.dropFirst())", "display_name": "\#(person.name)", "companion_id": "\#(animals[person.id.lowercased()]?.rawValue ?? "goat")", "avatar_url": null}"#
        return try? JSONDecoder().decode(SharedProfileIdentity.self, from: Data(json.utf8))
    }

    /// 18 finished fights, newest first: 12 won, 5 lost (one a group 2nd place) and 1 draw.
    static let sampleHistory: [ProfileHistoryRow] = {
        let names = ["Coffee run", "Weekend walkers", "Lunch laps", "No lift, no mercy", "The long way home", "The croissant run", "Park loops", "August challenge", "Sunrise club", "Heatwave", "Stair wars", "Bakery dash", "Commute clash", "Office stairs", "Beach week", "Rooftop run", "Hill repeats", "First blood"]
        let results = ["win", "loss", "draw", "loss", "win", "win", "win", "win", "loss", "win", "win", "win", "loss", "win", "loss", "win", "win", "win"]
        let rows = names.indices.map { i in
            """
            {"id": "\(UUID().uuidString)", "fight_id": null, "name": "\(names[i])", "starts_at": "2026-09-\(String(format: "%02d", max(1, 18 - i)))T00:00:00Z",
             "ends_at": "2026-09-\(String(format: "%02d", max(1, 18 - i)))T00:00:00Z", "category": "private", "result": "\(results[i])",
             "placement": \(results[i] == "win" ? "1" : results[i] == "draw" ? "1" : "2"), "field_size": 2, "counted": true, "complete": true}
            """
        }
        return (try? JSONDecoder().decode([ProfileHistoryRow].self, from: Data("[\(rows.joined(separator: ","))]".utf8))) ?? []
    }()

    /// A shared profile for any fixture person: statistics for everyone, a one-on-one record for friends.
    static func profile(userID: UUID) -> SharedProfile? {
        guard let index = people.firstIndex(where: { $0.id.lowercased() == userID.uuidString.lowercased() }) else { return nil }
        let person = people[index]
        let isYou = index == 0
        let records = [(5, 1, 1), (2, 3, 0), (1, 0, 0), (3, 2, 1)]
        let (wins, losses, draws) = records[(index + 3) % records.count]
        let steps = isYou ? sampleSteps : sampleSteps.map { $0 * (0.8 + Double(index) * 0.07) }
        let average = steps.reduce(0, +) / Double(steps.count)
        let json = """
        {
            "identity": {"user_id": "\(userID.uuidString)", "handle": "\(person.handle.dropFirst())", "display_name": "\(person.name)", "companion_id": "\(animals[person.id.lowercased()]?.rawValue ?? "goat")", "avatar_url": null},
            "access": "\(isYou ? "owner" : "friend")", "competitive": true, "friendship": "\(isYou ? "self" : "friends")",
            "record": {"played": 18, "wins": 12, "draws": 1, "losses": 5, "win_rate": 0.67, "categories": {}, "excluded": 0},
            "rivalry": \(isYou ? "null" : "{\"wins\": \(wins), \"losses\": \(losses), \"draws\": \(draws), \"rematch\": null}"),
            "activity": null,
            "step_statistics": {"scope_days": null, "from": null, "through": "2026-09-24", "time_zone": "Europe/Paris", "recorded_days": 31, "unknown_days": 0,
                "total_steps": \(steps.reduce(0, +)), "average_steps": \(average), "best_day": {"day": "2026-09-08", "steps": \(steps.max() ?? 0)},
                "week": {"starts_on": "2026-09-21", "elapsed_days": 4, "recorded_days": 4, "total_steps": \(steps.suffix(4).reduce(0, +)), "average_steps": \(steps.suffix(4).reduce(0, +) / 4)},
                "levels": []},
            "view_measurement_enabled": false
        }
        """
        return try? JSONDecoder().decode(SharedProfile.self, from: Data(json.utf8))
    }
}
#endif

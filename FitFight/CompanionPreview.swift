import Foundation
import SwiftUI

enum CompanionPreview {
    static var isEnabled: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--companion-preview")
            || ProcessInfo.processInfo.environment["FF_COMPANION_PREVIEW"] == "1"
        #else
        false
        #endif
    }

    static var writeUnavailable: String {
        String(localized: "Preview only. No fight, post, account or Health data is changed.")
    }

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
            case .populated: String(localized: "Populated")
            case .tied: String(localized: "Tied")
            case .solo: String(localized: "Solo")
            case .deferred: String(localized: "Next round")
            case .pending: String(localized: "Pending final sync")
            case .finished: String(localized: "Finished")
            case .empty: String(localized: "Empty")
            case .loading: String(localized: "Loading")
            case .offline: String(localized: "Cached / offline")
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
            fight.code = code
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
            fight.kickerPrefix = ""
            fight.kickerEmphasis = "\(gap >= 0 ? "+" : "−")\(abs(gap).formatted(.number.precision(.fractionLength(0))))"
            fight.kickerRest = ""
            fight.listSubtitle = fight.timeLeftLabel
            fight.actionText = french ? "Apporte des croissants pour tout le monde" : "Brings croissants for everyone"
            let dayCount = min(length, max(1, length - hoursLeft / 24))
            let weights = (0..<dayCount).map { [0.8, 1.1, 1.3, 0.9][$0 % 4] }
            let weightTotal = weights.reduce(0, +)
            fight.days = (0..<dayCount).map { day in
                let previousWeight = weights.prefix(day).reduce(0, +)
                return FightDay(label: String(localized: "companion.day", defaultValue: "Day \(day + 1)"),
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
        invite.invitePitch = String(localized: "companion.invitation", defaultValue: "\(people[3].name) invited you")
        invite.standings[0].invited = true
        invite.pending = 1
        invite.recurring = true
        invite.offersJoinNext = true
        invite.listSubtitle = String(localized: "3-day Steps fight")
        var finished = fight(5, name: french ? "Le café est pour toi" : "Coffee is on you", code: "C9F2",
                             totals: [24_100, 21_900], cast: [people[0], people[4]], length: 3, hoursLeft: -96)
        finished.status = .finished
        finished.serverState = "final"
        finished.standings = finished.standings.map { var row = $0; row.finalStepsComplete = true; return row }
        var history = group
        history.id = "F0000000-0000-4000-8000-000000000006"
        history.windowEnd = group.windowStart
        history.windowStart = group.windowStart.addingTimeInterval(-7 * 86_400)
        history.status = .finished
        history.serverState = "final"
        history.standings = history.standings.map { var row = $0; row.finalStepsComplete = true; return row }

        switch state {
        case .populated, .offline:
            model.fights = [group, duel, weekend, invite, finished, history]
        case .empty, .loading:
            model.fights = []
        case .tied:
            duel.standings = duel.standings.map { var row = $0; row.score = 18_420; row.rank = 1; return row }
            duel.rank = 1
            duel.kickerEmphasis = String(localized: "Tied")
            model.fights = [duel]
        case .solo:
            duel.standings = duel.standings.filter { $0.person.isYou }
            duel.rank = 1
            duel.of = 1
            model.fights = [duel]
        case .deferred:
            group.standings = group.standings.map { var row = $0; row.deferred = row.person.isYou; return row }
            model.fights = [group, history]
        case .pending:
            duel.status = .pending
            duel.serverState = "awaiting_final_sync"
            duel.windowEnd = now.addingTimeInterval(-3_600)
            duel.windowStart = duel.windowEnd.addingTimeInterval(-7 * 86_400)
            duel.graceEndsAt = now.addingTimeInterval(23 * 3_600)
            duel.kickerEmphasis = String(localized: "Pending final sync")
            duel.listSubtitle = String(localized: "Pending final sync")
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
                media: [], tags: [], reactions: [.init(emoji: "👏", count: 3 - index, mine: false)],
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
                body: index == 0 ? String(localized: "See you on Sunday!") : String(localized: "Count me in!"),
                createdAt: Date().addingTimeInterval(-600).ISO8601Format(),
                author: .init(userId: UUID(uuidString: person.id)!, handle: String(person.handle.dropFirst()), displayName: person.name, avatar: nil),
                mine: person.isYou
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
            FFScreenTitle(title: String(localized: "Companion preview"), subtitle: CompanionPreview.writeUnavailable)
            FFSection(title: String(localized: "Display state")) {
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
            FFSection(title: String(localized: "Look")) {
                ForEach(Mode.allCases) { mode in
                    FFButton(title: mode.label, kind: .secondary, fullWidth: true) { themeStore.mode = mode }
                }
            }
            FFButton(title: String(localized: "Close"), kind: .ghost, fullWidth: true) { dismiss() }
        }
    }
}
#endif

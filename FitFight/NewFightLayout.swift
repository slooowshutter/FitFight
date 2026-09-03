import Foundation
import SwiftUI

enum NewFightLayout: String, CaseIterable, Identifiable {
    case current
    case checklist
    case wizard
    case peopleFirst
    case stakeFirst
    case liveCard
    case plain
    case compact
    case sentence
    case ticket

    var id: String { rawValue }

    var number: Int {
        switch self {
        case .current: return 1
        case .checklist: return 2
        case .wizard: return 3
        case .peopleFirst: return 4
        case .stakeFirst: return 5
        case .liveCard: return 6
        case .plain: return 7
        case .compact: return 8
        case .sentence: return 9
        case .ticket: return 10
        }
    }

    var title: String {
        switch self {
        case .current: return "Current"
        case .checklist: return "Checklist"
        case .wizard: return "One step"
        case .peopleFirst: return "People first"
        case .stakeFirst: return "Stake first"
        case .liveCard: return "Live card"
        case .plain: return "Plain list"
        case .compact: return "Compact"
        case .sentence: return "Sentence"
        case .ticket: return "Ticket"
        }
    }

    var blurb: String {
        switch self {
        case .current:
            return "The New tab as it is now. Everything on one long page."
        case .checklist:
            return "Shows what’s left. Tap a job, finish it, then start."
        case .wizard:
            return "One question at a time: who, how long, the stake, then start."
        case .peopleFirst:
            return "Who you’re fighting is the whole first job. Type a username and hit Return."
        case .stakeFirst:
            return "The loser action is the headline. Duration and people come after."
        case .liveCard:
            return "A fight card you tap to edit. The card is the form."
        case .plain:
            return "A Settings-style list. No extra cards or summary."
        case .compact:
            return "Short page, duration slider, Start stuck above the tab bar."
        case .sentence:
            return "Fill in the blanks: you vs them, for this long, loser does this."
        case .ticket:
            return "Fill it in, then read a bet ticket before you start."
        }
    }
}

@MainActor
final class NewFightLayoutStore: ObservableObject {
    @Published var layout: NewFightLayout {
        didSet {
            if persists {
                UserDefaults.standard.set(layout.rawValue, forKey: Self.key)
            }
        }
    }

    private static let key = "ff.newFightLayout"
    private let persists: Bool

    init() {
        persists = true
        let raw = UserDefaults.standard.string(forKey: Self.key) ?? NewFightLayout.current.rawValue
        layout = NewFightLayout(rawValue: raw) ?? .current
    }

    init(transient layout: NewFightLayout) {
        persists = false
        self.layout = layout
    }
}

extension AppVersion {
    static var exploresNewFightLayouts: Bool { backend != "prod" }
}

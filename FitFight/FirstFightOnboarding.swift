import Foundation

/// Local progress belongs to one account. Apple Health comes before the companion, so a referred friend's free
/// character is there to use when they choose. Celebration is unnumbered.
struct FirstFightOnboarding: Codable, Equatable {
    enum Page: String, Codable, Hashable {
        case username, health, healthResult, companion, firstFight, reminders, celebration

        var step: Int? {
            switch self {
            case .username: 2
            case .health, .healthResult: 3
            case .companion: 4
            case .firstFight: 5
            case .reminders: 6
            case .celebration: nil
            }
        }

        var previous: Page? {
            switch self {
            case .username, .celebration: nil
            case .health: .username
            case .healthResult: .health
            case .companion: .healthResult
            case .firstFight: .companion
            case .reminders: .firstFight
            }
        }
    }

    var page: Page = .username
    /// Nil in progress saved before Health moved ahead of the companion.
    var order: Int? = 2
    var joinedFightID: UUID?
    var joinedFightName: String?

    /// Going back or exploring cannot undo a membership already accepted by the server.
    var pageAfterReminders: Page? { joinedFightID == nil ? nil : .celebration }
}

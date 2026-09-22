import Foundation

/// Local progress belongs to one account. Health reveal remains step four; celebration is unnumbered.
struct FirstFightOnboarding: Codable, Equatable {
    enum Page: String, Codable, Hashable {
        case username, companion, health, healthResult, firstFight, reminders, celebration

        var step: Int? {
            switch self {
            case .username: 2
            case .companion: 3
            case .health, .healthResult: 4
            case .firstFight: 5
            case .reminders: 6
            case .celebration: nil
            }
        }

        var previous: Page? {
            switch self {
            case .username, .celebration: nil
            case .companion: .username
            case .health: .companion
            case .healthResult: .health
            case .firstFight: .health
            case .reminders: .firstFight
            }
        }
    }

    var page: Page = .username
    var joinedFightID: UUID?
    var joinedFightName: String?

    /// Going back or exploring cannot undo a membership already accepted by the server.
    var pageAfterReminders: Page? { joinedFightID == nil ? nil : .celebration }
}

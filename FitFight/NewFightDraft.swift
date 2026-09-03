import Foundation
import SwiftUI

@MainActor
final class NewFightDraft: ObservableObject {
    static let testDurations = ["1 hour", "6 hours", "1 day"]
    static let realDurations = ["3 days", "1 week", "2 weeks", "1 month"]
    static let durations = testDurations + realDurations
    static let actionLimit = 120
    static let actionStarters = ["Cooks dinner", "Buys coffee", "50 push-ups"]

    @Published var username = ""
    @Published var inviteHandles: [String] = []
    @Published var usernameError: String?
    @Published var duration = "1 week"
    @Published var actionText = ""
    @Published var wizardStep = 0
    @Published var editingField: NewFightEditField?
    @Published var showingTicket = false

    var trimmedAction: String {
        actionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var playerCount: Int { inviteHandles.count + 1 }

    var playerLabel: String {
        "\(playerCount) \(playerCount == 1 ? "player" : "players")"
    }

    var versusLine: String {
        if inviteHandles.isEmpty { return "Add a username to start." }
        return "You vs \(inviteHandles.map { "@\($0)" }.joined(separator: ", "))."
    }

    var endsCaption: String {
        switch duration {
        case "1 hour": return "Ends in 1 hour"
        case "6 hours": return "Ends in 6 hours"
        case "1 day": return "Ends tomorrow"
        case "3 days": return "Ends in 3 days"
        case "1 week": return "Ends in 7 days"
        case "2 weeks": return "Ends in 14 days"
        case "1 month": return "Ends in 30 days"
        default: return "The fight starts now"
        }
    }

    func canStart(session: SessionStore, steps: HealthKitStepsStore, model: AppModel) -> Bool {
        session.isSignedIn
            && steps.hasAsked
            && !inviteHandles.isEmpty
            && !trimmedAction.isEmpty
            && trimmedAction.count <= Self.actionLimit
            && !model.isCreatingFight
    }

    func missing(session: SessionStore, steps: HealthKitStepsStore) -> [String] {
        var items: [String] = []
        if !steps.hasAsked { items.append("Connect Apple Health") }
        if inviteHandles.isEmpty { items.append("Add a username") }
        if trimmedAction.isEmpty { items.append("Name the loser action") }
        return items
    }

    func startTitle(session: SessionStore, steps: HealthKitStepsStore, model: AppModel) -> String {
        if model.isCreatingFight { return "Starting…" }
        if let first = missing(session: session, steps: steps).first { return first }
        return "Start fight"
    }

    func addUsername(session: SessionStore) {
        let handle = SessionStore.strippedHandle(username)
        usernameError = nil

        guard SessionStore.isValidHandle(handle) else {
            usernameError = "Use 2–30 letters, numbers, or underscores."
            return
        }
        if handle == session.profile?.handle {
            usernameError = "Add someone else’s username."
            return
        }
        guard !inviteHandles.contains(handle) else {
            usernameError = "@\(handle) is already in this fight."
            return
        }

        inviteHandles.append(handle)
        username = ""
    }

    func removeHandle(_ handle: String) {
        inviteHandles.removeAll { $0 == handle }
    }

    func clampAction() {
        if actionText.count > Self.actionLimit {
            actionText = String(actionText.prefix(Self.actionLimit))
        }
    }

    func resetAfterStart() {
        username = ""
        inviteHandles = []
        usernameError = nil
        duration = "1 week"
        actionText = ""
        wizardStep = 0
        editingField = nil
        showingTicket = false
    }

    func resetFlowState() {
        wizardStep = 0
        editingField = nil
        showingTicket = false
    }

    func startFight(model: AppModel, session: SessionStore, steps: HealthKitStepsStore) {
        guard canStart(session: session, steps: steps, model: model) else { return }
        guard model.beginCreateFight() else { return }

        let startsAt = Date()
        let durationParts: (component: Calendar.Component, value: Int, seconds: TimeInterval) = switch duration {
        case "1 hour": (.hour, 1, 3_600)
        case "6 hours": (.hour, 6, 21_600)
        case "1 day": (.day, 1, 86_400)
        case "3 days": (.day, 3, 259_200)
        case "1 week": (.day, 7, 604_800)
        case "2 weeks": (.day, 14, 1_209_600)
        case "1 month": (.day, 30, 2_592_000)
        default: (.day, 7, 604_800)
        }
        let endsAt = Calendar.current.date(
            byAdding: durationParts.component,
            value: durationParts.value,
            to: startsAt
        ) ?? startsAt.addingTimeInterval(durationParts.seconds)
        let action = trimmedAction
        let handles = inviteHandles

        Task {
            await model.createAndStartFight(
                startsAt: startsAt,
                endsAt: endsAt,
                actionText: action,
                inviteHandles: handles
            )
            if (model.createError ?? "").isEmpty {
                resetAfterStart()
                model.tab = .fights
            }
        }
    }

    func connectAppleHealth(session: SessionStore, steps: HealthKitStepsStore) {
        Task {
            await steps.refresh(requestAccess: true)
            if session.authSession != nil {
                await steps.syncToBackend(session: session)
            }
        }
    }
}

enum NewFightEditField: Hashable {
    case people, duration, action
}

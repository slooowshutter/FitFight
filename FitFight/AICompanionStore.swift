import SwiftUI

@MainActor
final class AICompanionStore: ObservableObject {
    @Published private(set) var library: [FitFightAILibraryEntry] = []
    @Published private(set) var allowance: FitFightAIAllowance?
    @Published private(set) var action: AICompanionAction?
    @Published private(set) var busy = false
    @Published private(set) var progress = ""
    @Published private(set) var recoveryBlocked = false
    @Published var error = ""

    private var ownerID: UUID?
    private let api = FitFightAPI()
    static let pendingPrefix = "ff.ai.pending."

    var avatars: [FitFightAILibraryEntry] { library.filter { $0.workflow == .avatar } }

    func open(session: SessionStore) async {
        guard let userID = session.profile?.userId else {
            ownerID = nil
            library = []
            allowance = nil
            action = nil
            error = ""
            return
        }
        if !recoveryBlocked { error = "" }
        if ownerID != userID {
            ownerID = userID
            library = []
            allowance = nil
            action = nil
            error = ""
            recoveryBlocked = false
            if let data = UserDefaults.standard.data(forKey: Self.pendingPrefix + userID.uuidString) {
                do { action = try JSONDecoder().decode(AICompanionAction.self, from: data) }
                catch {
                    recoveryBlocked = true
                    self.error = String(localized: "Couldn't restore your generation. Contact support before starting another.")
                    return
                }
            }
        }
        do {
            let token = try await session.freshAccessToken()
            let saved = try await api.aiLibrary(accessToken: token)
            try Task.checkCancellation()
            guard session.profile?.userId == userID, ownerID == userID else { return }
            library = saved
            if let requestID = action?.requestID, saved.contains(where: { $0.requestID == requestID }) {
                action = nil
                UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userID.uuidString)
            }
            let credits = try await api.aiAllowance(accessToken: token)
            try Task.checkCancellation()
            guard session.profile?.userId == userID, ownerID == userID else { return }
            allowance = credits
        } catch {
            if !Task.isCancelled, session.profile?.userId == userID, ownerID == userID {
                self.error = error.localizedDescription
            }
        }
    }

    func begin(workflow: FitFightAIRequest.Workflow, description: String, characters: [FitFightAICharacter], session: SessionStore) async {
        guard !busy, !recoveryBlocked, action == nil, let userID = ownerID, session.profile?.userId == userID else { return }
        let next = AICompanionAction(key: UUID(), workflow: workflow, description: description, characters: characters)
        do {
            let data = try JSONEncoder().encode(next)
            UserDefaults.standard.set(data, forKey: Self.pendingPrefix + userID.uuidString)
            action = next
            await resume(session: session)
        } catch { self.error = error.localizedDescription }
    }

    func resume(session: SessionStore) async {
        guard !busy, var pending = action, let userID = ownerID, session.profile?.userId == userID else { return }
        busy = true
        error = ""
        progress = String(localized: "Generating your images…")
        defer { busy = false }
        do {
            var result: FitFightAIRequest
            let token = try await session.freshAccessToken()
            if let requestID = pending.requestID {
                result = try await api.aiRequest(requestID: requestID, accessToken: token)
            } else {
                switch pending.workflow {
                case .avatar:
                    result = try await api.startAvatarGeneration(description: pending.description, idempotencyKey: pending.key, accessToken: token)
                case .fitness:
                    guard let character = pending.characters.first else {
                        recoveryBlocked = true
                        error = String(localized: "Couldn't restore your generation. Contact support before starting another.")
                        return
                    }
                    result = try await api.startFitnessGeneration(avatarRequestID: character.avatarRequestID, identityDetails: character.identityDetails, idempotencyKey: pending.key, accessToken: token)
                case .groupPhoto:
                    result = try await api.startGroupPhotoGeneration(characters: pending.characters, scene: pending.description, idempotencyKey: pending.key, accessToken: token)
                }
                try Task.checkCancellation()
                guard session.profile?.userId == userID, ownerID == userID else { return }
                pending.requestID = result.requestID
                UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: Self.pendingPrefix + userID.uuidString)
                action = pending
            }
            while result.status == .pending || result.status == .running {
                try await Task.sleep(for: .seconds(max(3, result.pollAfterSeconds ?? 3)))
                guard session.profile?.userId == userID, ownerID == userID else { return }
                result = try await api.aiRequest(requestID: result.requestID, accessToken: try await session.freshAccessToken())
            }
            try Task.checkCancellation()
            guard session.profile?.userId == userID, ownerID == userID else { return }
            UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userID.uuidString)
            guard session.profile?.userId == userID, ownerID == userID else { return }
            action = nil
            progress = String(localized: "Saved to your library.")
            await open(session: session)
        } catch {
            guard !Task.isCancelled, session.profile?.userId == userID, ownerID == userID else { return }
            if let failure = error as? FitFightAIError {
                if let requestID = failure.requestID, failure.code != "ai_in_progress" {
                    pending.requestID = requestID
                    action = pending
                    do { UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: Self.pendingPrefix + userID.uuidString) }
                    catch { self.error = error.localizedDescription; return }
                }
                let rejected = ["ai_insufficient_credits", "ai_rate_limited", "ai_daily_limit", "ai_busy", "ai_unavailable", "ai_in_progress"]
                let terminal = ["ai_failed", "ai_invalid_result", "ai_cancelled", "ai_request_expired"]
                if terminal.contains(failure.code) || (pending.requestID == nil && rejected.contains(failure.code)) {
                    action = nil
                    UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userID.uuidString)
                }
            } else if pending.requestID == nil, let failure = error as? FitFightAPIError,
                      case .http(let status, _, _) = failure, status == 400 || status == 404 {
                action = nil
                UserDefaults.standard.removeObject(forKey: Self.pendingPrefix + userID.uuidString)
            }
            self.error = error.localizedDescription
        }
    }
}

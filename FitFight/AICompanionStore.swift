import SwiftUI
import UIKit

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
        guard let userID = session.profile?.userId else { return }
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
            if !Task.isCancelled { self.error = error.localizedDescription }
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
                    guard let character = pending.characters.first else { throw MediaUploader.UploadError.invalidImage }
                    result = try await api.startFitnessGeneration(avatarRequestID: character.avatarRequestID, identityDetails: character.identityDetails, idempotencyKey: pending.key, accessToken: token)
                case .groupPhoto:
                    result = try await api.startGroupPhotoGeneration(characters: pending.characters, scene: pending.description, idempotencyKey: pending.key, accessToken: token)
                }
                pending.requestID = result.requestID
                UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: Self.pendingPrefix + userID.uuidString)
                guard session.profile?.userId == userID, ownerID == userID else { return }
                action = pending
            }
            while result.status == .pending || result.status == .running {
                try await Task.sleep(for: .seconds(max(3, result.pollAfterSeconds ?? 3)))
                guard session.profile?.userId == userID, ownerID == userID else { return }
                result = try await api.aiRequest(requestID: result.requestID, accessToken: try await session.freshAccessToken())
            }
            try Task.checkCancellation()
            guard session.profile?.userId == userID, ownerID == userID else { return }
            progress = String(localized: "Saving images to your account…")
            let outputs: [(String, URL)]
            if let images = result.fitnessImages {
                outputs = [("resting", images.resting), ("soft", images.soft), ("average", images.average), ("fit", images.fit), ("strong", images.strong)]
            } else if let url = result.imageURL {
                outputs = [("image_url", url)]
            } else {
                throw MediaUploader.UploadError.invalidImage
            }
            for (stage, url) in outputs where pending.uploaded[stage] == nil {
                guard session.profile?.userId == userID, ownerID == userID else { return }
                // Provider URLs come from the authenticated API, never from editable text.
                var request = URLRequest(url: url)
                request.timeoutInterval = 60
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
                      data.count <= 8_388_608, let image = UIImage(data: data) else {
                    throw MediaUploader.UploadError.invalidImage
                }
                try Task.checkCancellation()
                guard session.profile?.userId == userID, ownerID == userID else { return }
                let media = try await MediaUploader.upload(image, purpose: "profile", preserveTransparency: true, session: session)
                pending.uploaded[stage] = media
                UserDefaults.standard.set(try JSONEncoder().encode(pending), forKey: Self.pendingPrefix + userID.uuidString)
                try Task.checkCancellation()
                guard session.profile?.userId == userID, ownerID == userID else { return }
                action = pending
            }
            let input = FitFightAISaveImages(
                description: pending.description,
                images: outputs.compactMap { stage, _ in
                    pending.uploaded[stage].map { .init(stage: stage, mediaID: $0.id) }
                }
            )
            try await api.saveAIImages(requestID: result.requestID, input: input, accessToken: try await session.freshAccessToken())
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

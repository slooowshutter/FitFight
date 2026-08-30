import Foundation

@MainActor
final class HealthKitTUSUploader: NSObject, URLSessionTaskDelegate {
    private static let sessionPrefix = "com.fitfight.mvp.healthkit-tus."
    private static weak var current: HealthKitTUSUploader?
    private static var pendingBackgroundEvents: (identifier: String, completion: () -> Void)?

    private var sessions: [String: URLSession] = [:]
    private var backgroundCompletions: [String: () -> Void] = [:]

    override init() {
        super.init()
        Self.current = self
        if let pending = Self.pendingBackgroundEvents {
            Self.pendingBackgroundEvents = nil
            cancelLegacyBackgroundEvents(
                identifier: pending.identifier,
                completion: pending.completion
            )
        }
    }

    static func registerBackgroundEvents(
        identifier: String,
        completion: @escaping () -> Void
    ) {
        guard identifier.hasPrefix(sessionPrefix) else {
            completion()
            return
        }
        if let current {
            current.cancelLegacyBackgroundEvents(identifier: identifier, completion: completion)
        } else {
            pendingBackgroundEvents = (identifier, completion)
        }
    }

    func discardLegacy(userId: UUID) async {
        let session = session(
            identifier: Self.sessionPrefix + userId.uuidString.lowercased()
        )
        await withCheckedContinuation { continuation in
            session.getAllTasks { [weak self] tasks in
                tasks.forEach { $0.cancel() }
                continuation.resume()
                if tasks.isEmpty {
                    Task { @MainActor [weak self] in
                        self?.finish(session)
                    }
                }
            }
        }
    }

    private func cancelLegacyBackgroundEvents(
        identifier: String,
        completion: @escaping () -> Void
    ) {
        backgroundCompletions[identifier] = completion
        let session = session(identifier: identifier)
        session.getAllTasks { [weak self] tasks in
            tasks.forEach { $0.cancel() }
            if tasks.isEmpty {
                Task { @MainActor [weak self] in
                    self?.finish(session)
                }
            }
        }
    }

    private func session(identifier: String) -> URLSession {
        if let session = sessions[identifier] { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: .main
        )
        sessions[identifier] = session
        return session
    }

    private func finish(_ session: URLSession) {
        guard let identifier = session.configuration.identifier,
              sessions[identifier] === session else { return }
        let completion = backgroundCompletions.removeValue(forKey: identifier)
        sessions[identifier] = nil
        session.finishTasksAndInvalidate()
        completion?()
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        session.getAllTasks { [weak self] tasks in
            guard tasks.isEmpty else { return }
            Task { @MainActor in
                self?.finish(session)
            }
        }
    }

    nonisolated func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        Task { @MainActor [weak self] in
            self?.finish(session)
        }
    }
}

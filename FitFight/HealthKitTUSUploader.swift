import Foundation
import TUSKit

final class HealthKitTUSUploader: NSObject, TUSClientDelegate {
    private static weak var current: HealthKitTUSUploader?
    private static var pendingBackgroundEvents: (identifier: String, completion: () -> Void)?
    private var client: TUSClient?
    private var continuation: CheckedContinuation<UUID, Error>?
    private var expectedTaskId: UUID?
    private var clientUserId: UUID?
    private let headerBox = TUSHeaderBox()

    override init() {
        super.init()
        Self.current = self
    }

    static func registerBackgroundEvents(
        identifier: String,
        completion: @escaping () -> Void
    ) {
        if let client = current?.client {
            client.registerBackgroundHandler(completion, forSession: identifier)
        } else {
            pendingBackgroundEvents = (identifier, completion)
        }
    }

    func discard(taskId: UUID?) {
        if let taskId {
            try? client?.cancelAndDelete(id: taskId)
        }
        client?.stopAndCancelAll()
        client = nil
        clientUserId = nil
    }

    func upload(
        fileURL: URL,
        capability: FitFightProviderUploadCapability,
        userId: UUID,
        existingTaskId: UUID?,
        taskScheduled: (UUID) throws -> Void
    ) async throws {
        headerBox.replace(with: capability.tusHeaders)
        let storage = try HealthKitUploadState.directory(userId: userId)
            .appendingPathComponent("tus", isDirectory: true)
        try FileManager.default.createDirectory(
            at: storage,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try HealthKitUploadState.protectAndExcludeFromBackup(storage)

        let client: TUSClient
        if let current = self.client, clientUserId == userId {
            client = current
        } else {
            let configuration = URLSessionConfiguration.background(
                withIdentifier: "com.fitfight.mvp.healthkit-tus.\(userId.uuidString.lowercased())"
            )
            configuration.sessionSendsLaunchEvents = true
            configuration.isDiscretionary = false
            client = try TUSClient(
                server: capability.tusURL,
                sessionIdentifier: "FitFight HealthKit",
                sessionConfiguration: configuration,
                storageDirectory: storage,
                chunkSize: 6 * 1_024 * 1_024,
                generateHeaders: { [headerBox] _, storedHeaders, completion in
                    completion(storedHeaders.merging(headerBox.current) { _, refreshed in refreshed })
                }
            )
            client.delegate = self
            self.client = client
            clientUserId = userId
            if let pending = Self.pendingBackgroundEvents {
                client.registerBackgroundHandler(pending.completion, forSession: pending.identifier)
                Self.pendingBackgroundEvents = nil
            }
        }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            if let existingTaskId {
                expectedTaskId = existingTaskId
                if let stored = try? client.getStoredUploads().first(where: { $0.id == existingTaskId }),
                   stored.uploadedRange?.count == stored.size {
                    client.cleanup()
                    self.continuation = nil
                    continuation.resume(returning: existingTaskId)
                    return
                }
                let restored = client.start().contains { $0.0 == existingTaskId }
                if !restored, (try? client.retry(id: existingTaskId)) != true,
                   (try? client.resume(id: existingTaskId)) != true {
                    self.continuation = nil
                    continuation.resume(throwing: HealthKitTUSError.missingResumeState)
                }
            } else {
                do {
                    let id = try client.uploadFileAt(
                        filePath: fileURL,
                        uploadURL: capability.tusURL,
                        customHeaders: capability.tusHeaders,
                        context: capability.tusMetadata
                    )
                    expectedTaskId = id
                    do {
                        try taskScheduled(id)
                    } catch {
                        try? client.cancelAndDelete(id: id)
                        throw error
                    }
                } catch {
                    self.continuation = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func didFinishUpload(
        id: UUID,
        url: URL,
        context: [String: String]?,
        client: TUSClient
    ) {
        guard id == expectedTaskId else { return }
        continuation?.resume(returning: id)
        continuation = nil
        expectedTaskId = nil
        client.cleanup()
    }

    func uploadFailed(
        id: UUID,
        error: Error,
        context: [String: String]?,
        client: TUSClient
    ) {
        guard id == expectedTaskId else { return }
        continuation?.resume(throwing: error)
        continuation = nil
        expectedTaskId = nil
    }

    func didStartUpload(id: UUID, context: [String: String]?, client: TUSClient) {}
    func fileError(id: UUID?, error: TUSClientError, client: TUSClient) {
        continuation?.resume(throwing: error)
        continuation = nil
        expectedTaskId = nil
    }
    func fileError(error: TUSClientError, client: TUSClient) {
        fileError(id: nil, error: error, client: client)
    }
    func totalProgress(bytesUploaded: Int, totalBytes: Int, client: TUSClient) {}
    func progressFor(
        id: UUID,
        context: [String: String]?,
        bytesUploaded: Int,
        totalBytes: Int,
        client: TUSClient
    ) {}
}

enum HealthKitTUSError: Error {
    case missingResumeState
}

private final class TUSHeaderBox: @unchecked Sendable {
    private let lock = NSLock()
    private var headers: [String: String] = [:]

    var current: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return headers
    }

    func replace(with headers: [String: String]) {
        lock.lock()
        self.headers = headers
        lock.unlock()
    }
}

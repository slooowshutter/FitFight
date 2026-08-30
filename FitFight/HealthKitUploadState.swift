import Foundation

enum HealthKitConnectionState: String, Codable {
    case notConnected
    case syncing
    case upToDate
    case noAccessibleSteps
    case syncFailed
    case archiveTooLarge
}

enum HealthKitUploadPhase: String, Codable {
    case archived
    case issued
    case uploading
    case uploaded
    case processing
    case committed
    case completed
}

struct HealthKitUploadState: Codable {
    var connection: HealthKitConnectionState
    var activeAnchor: Data?
    var candidateAnchor: Data?
    var uploadId: UUID?
    var archivePath: String?
    var byteSize: Int?
    var sha256: String?
    var phase: HealthKitUploadPhase?
    var tusTaskId: UUID?
    var earliestSample: Date?

    static func load(userId: UUID) throws -> HealthKitUploadState {
        let url = try stateURL(userId: userId)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return HealthKitUploadState(connection: .notConnected)
        }
        return try JSONDecoder().decode(
            HealthKitUploadState.self,
            from: Data(contentsOf: url)
        )
    }

    func save(userId: UUID) throws {
        let url = try Self.stateURL(userId: userId)
        try JSONEncoder().encode(self).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try Self.protectAndExcludeFromBackup(url)
    }

    mutating func complete(userId: UUID) throws {
        activeAnchor = candidateAnchor
        candidateAnchor = nil
        if let archivePath {
            try FileManager.default.removeItem(atPath: archivePath)
        }
        uploadId = nil
        archivePath = nil
        byteSize = nil
        sha256 = nil
        phase = nil
        tusTaskId = nil
        connection = .upToDate
        try save(userId: userId)
    }

    mutating func discardPending(userId: UUID) throws {
        if let archivePath, FileManager.default.fileExists(atPath: archivePath) {
            try FileManager.default.removeItem(atPath: archivePath)
        }
        let tusDirectory = try Self.directory(userId: userId)
            .appendingPathComponent("tus", isDirectory: true)
        if FileManager.default.fileExists(atPath: tusDirectory.path) {
            try FileManager.default.removeItem(at: tusDirectory)
        }
        candidateAnchor = nil
        uploadId = nil
        archivePath = nil
        byteSize = nil
        sha256 = nil
        phase = nil
        tusTaskId = nil
        connection = .syncFailed
        try save(userId: userId)
    }

    static func directory(userId: UUID) throws -> URL {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root
            .appendingPathComponent("HealthKit", isDirectory: true)
            .appendingPathComponent(userId.uuidString.lowercased(), isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        )
        try protectAndExcludeFromBackup(directory)
        return directory
    }

    static func protectAndExcludeFromBackup(_ url: URL) throws {
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func stateURL(userId: UUID) throws -> URL {
        try directory(userId: userId).appendingPathComponent("state.json")
    }
}

private extension HealthKitUploadState {
    init(connection: HealthKitConnectionState) {
        self.connection = connection
    }
}

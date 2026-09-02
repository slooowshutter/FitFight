import Foundation

enum HealthKitConnectionState: String, Codable {
    case notConnected
    case syncing
    case upToDate
    case noAccessibleSteps
    case syncFailed
}

enum HealthKitUploadState {
    static func discardLegacy(userId: UUID) throws {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = root
            .appendingPathComponent("HealthKit", isDirectory: true)
            .appendingPathComponent(userId.uuidString.lowercased(), isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

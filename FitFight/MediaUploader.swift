import AVFoundation
import CryptoKit
import CoreTransferable
import UniformTypeIdentifiers
import UIKit

struct PickedVideo: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: false)
                .appendingPathExtension(ext)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

enum MediaUploader {
    enum UploadError: LocalizedError {
        case invalidImage
        case invalidVideo
        case tooLarge
        case tooLong
        case fileTooLarge

        var errorDescription: String? {
            switch self {
            case .invalidImage: return String(appLocalized: "That photo could not be read.")
            case .invalidVideo: return String(appLocalized: "That video could not be read.")
            case .tooLarge: return String(appLocalized: "Choose a smaller photo or video.")
            case .tooLong: return String(appLocalized: "Choose a video under 3 minutes.")
            case .fileTooLarge: return String(appLocalized: "Choose a smaller file.")
            }
        }
    }

    static func upload(
        _ image: UIImage,
        purpose: String,
        session: SessionStore,
        api: FitFightAPI = FitFightAPI()
    ) async throws -> FitFightMedia {
        let maxDimension: CGFloat = 2048
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 0 ? min(1, maxDimension / longest) : 1
        let size = CGSize(
            width: max(1, floor(image.size.width * scale)),
            height: max(1, floor(image.size.height * scale))
        )
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = rendered.jpegData(compressionQuality: 0.82) else {
            throw UploadError.invalidImage
        }
        if data.count > 8_388_608 {
            throw UploadError.tooLarge
        }
        return try await put(
            data: data,
            purpose: purpose,
            kind: "photo",
            filename: "photo.jpg",
            contentType: "image/jpeg",
            width: Int(rendered.size.width * rendered.scale),
            height: Int(rendered.size.height * rendered.scale),
            durationMs: nil,
            session: session,
            api: api
        )
    }

    static func uploadVideo(
        _ url: URL,
        purpose: String,
        session: SessionStore,
        api: FitFightAPI = FitFightAPI()
    ) async throws -> FitFightMedia {
        let fileSize = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        if fileSize < 1 || fileSize > 52_428_800 {
            throw UploadError.tooLarge
        }
        let asset = AVURLAsset(url: url)
        let seconds = CMTimeGetSeconds(try await asset.load(.duration))
        guard seconds.isFinite, seconds > 0 else {
            throw UploadError.invalidVideo
        }
        let durationMs = Int((seconds * 1000).rounded())
        if durationMs > 180_000 {
            throw UploadError.tooLong
        }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw UploadError.invalidVideo
        }
        let natural = try await track.load(.naturalSize)
        let rendered = natural.applying(try await track.load(.preferredTransform))
        let width = max(1, Int(abs(rendered.width).rounded()))
        let height = max(1, Int(abs(rendered.height).rounded()))
        if width > 8192 || height > 8192 {
            throw UploadError.tooLarge
        }
        let isQuickTime = url.pathExtension.lowercased() == "mov"
        return try await put(
            data: try Data(contentsOf: url, options: .mappedIfSafe),
            purpose: purpose,
            kind: "video",
            filename: isQuickTime ? "video.mov" : "video.mp4",
            contentType: isQuickTime ? "video/quicktime" : "video/mp4",
            width: width,
            height: height,
            durationMs: durationMs,
            session: session,
            api: api
        )
    }

    static func uploadFile(
        _ url: URL,
        purpose: String,
        session: SessionStore,
        api: FitFightAPI = FitFightAPI()
    ) async throws -> FitFightMedia {
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .nameKey])
        let fileSize = values.fileSize ?? 0
        if fileSize < 1 || fileSize > 52_428_800 {
            throw UploadError.fileTooLarge
        }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var name = (values.name ?? url.lastPathComponent)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "file" }
        if name.count > 200 { name = String(name.prefix(200)) }
        let raw = (UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream")
            .lowercased()
        let mime = raw.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)
            .flatMap { $0.contains("/") ? $0 : nil }
            ?? "application/octet-stream"
        return try await put(
            data: data,
            purpose: purpose,
            kind: "file",
            filename: name,
            contentType: mime,
            width: 1,
            height: 1,
            durationMs: nil,
            session: session,
            api: api
        )
    }

    private static func put(
        data: Data,
        purpose: String,
        kind: String,
        filename: String,
        contentType: String,
        width: Int,
        height: Int,
        durationMs: Int?,
        session: SessionStore,
        api: FitFightAPI
    ) async throws -> FitFightMedia {
        let token = try await session.freshAccessToken()
        let issued = try await api.createMediaUpload(
            purpose: purpose,
            kind: kind,
            filename: filename,
            contentType: contentType,
            byteSize: data.count,
            width: width,
            height: height,
            durationMs: durationMs,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            accessToken: token
        )
        var request = URLRequest(url: issued.upload.url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(issued.upload.token)", forHTTPHeaderField: "Authorization")
        request.setValue("false", forHTTPHeaderField: "x-upsert")
        let (_, response) = try await URLSession.shared.upload(for: request, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            throw FitFightAPIError.http(status: status, code: "storage_error", message: nil)
        }
        let committed = try await api.commitMedia(id: issued.media.id, accessToken: try await session.freshAccessToken())
        return committed.media
    }
}

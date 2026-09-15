import ImageIO
import SwiftUI
import UIKit

enum RemoteImageKind {
    case avatar
    case photo

    var maxPixel: CGFloat {
        switch self {
        case .avatar: return 256
        case .photo: return 1400
        }
    }
}

@MainActor
final class RemoteImageLoader {
    static let shared = RemoteImageLoader()

    private let memory = NSCache<NSString, UIImage>()
    private var inflight: [String: Task<Data?, Never>] = [:]
    private let session: URLSession
    private let folder: URL

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 32 * 1_048_576, diskCapacity: 64 * 1_048_576)
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 45
        configuration.httpMaximumConnectionsPerHost = 6
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration)
        memory.countLimit = 200
        memory.totalCostLimit = 40 * 1_048_576
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemotePhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func cached(url: URL, kind: RemoteImageKind) -> UIImage? {
        memory.object(forKey: memoryKey(RemoteImageCache.key(for: url), kind: kind) as NSString)
    }

    func prefetch(_ urls: [URL], kind: RemoteImageKind) {
        for url in urls {
            Task { _ = await image(for: url, kind: kind) }
        }
    }

    func image(for url: URL, kind: RemoteImageKind) async -> UIImage? {
        let objectKey = RemoteImageCache.key(for: url)
        let storedKey = memoryKey(objectKey, kind: kind)
        if let cached = memory.object(forKey: storedKey as NSString) {
            return cached
        }

        let disk = await Task.detached(priority: .utility) {
            Self.readDisk(objectKey)
        }.value
        if let disk {
            return await displayImage(disk, kind: kind, storedKey: storedKey)
        }

        if let inflight = inflight[objectKey] {
            guard let data = await inflight.value else { return nil }
            return await displayImage(data, kind: kind, storedKey: storedKey)
        }

        let session = session
        let task = Task.detached(priority: .utility) {
            await Self.download(url, session: session)
        }
        inflight[objectKey] = task
        let data = await task.value
        inflight[objectKey] = nil
        guard let data else { return nil }
        let folder = folder
        Task.detached(priority: .utility) {
            Self.writeDisk(objectKey, data: data, folder: folder)
        }
        return await displayImage(data, kind: kind, storedKey: storedKey)
    }

    private func memoryKey(_ objectKey: String, kind: RemoteImageKind) -> String {
        "\(objectKey)|\(Int(kind.maxPixel))"
    }

    private func displayImage(_ data: Data, kind: RemoteImageKind, storedKey: String) async -> UIImage? {
        let decoded = await Task.detached(priority: .utility) {
            Self.decode(data, maxPixel: kind.maxPixel)
        }.value
        return store(decoded, key: storedKey)
    }

    private func store(_ image: UIImage?, key: String) -> UIImage? {
        guard let image else { return nil }
        memory.setObject(image, forKey: key as NSString, cost: image.cost)
        return image
    }

    nonisolated private static func download(_ url: URL, session: URLSession) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        for attempt in 0..<3 {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { return nil }
                if (200..<300).contains(http.statusCode), !data.isEmpty { return data }
                if (400..<500).contains(http.statusCode) { return nil }
            } catch {
                if Task.isCancelled { return nil }
            }
            if attempt < 2 {
                try? await Task.sleep(nanoseconds: 400_000_000 * UInt64(attempt + 1))
            }
        }
        return nil
    }

    nonisolated private static func decode(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }
        let thumbnail = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    nonisolated private static var diskFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RemotePhotos", isDirectory: true)
    }

    nonisolated private static func readDisk(_ objectKey: String) -> Data? {
        let url = diskFolder.appendingPathComponent(RemoteImageCache.fileName(for: objectKey))
        return try? Data(contentsOf: url)
    }

    nonisolated private static func writeDisk(_ objectKey: String, data: Data, folder: URL) {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(RemoteImageCache.fileName(for: objectKey))
        try? data.write(to: url, options: .atomic)
        evictIfNeeded(folder: folder)
    }

    nonisolated private static func evictIfNeeded(folder: URL) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey]
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: Array(keys)
        ) else { return }
        let limit = 200 * 1_048_576
        var total = files.reduce(0) { sum, file in
            sum + ((try? file.resourceValues(forKeys: keys).fileSize) ?? 0)
        }
        guard total > limit else { return }
        let oldest = files.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: keys).contentModificationDate) ?? .distantPast
            return left < right
        }
        for file in oldest {
            guard total > limit else { return }
            total -= (try? file.resourceValues(forKeys: keys).fileSize) ?? 0
            try? FileManager.default.removeItem(at: file)
        }
    }
}

private extension UIImage {
    var cost: Int {
        Int(size.width * scale * size.height * scale * 4)
    }
}

struct RemotePhoto<Placeholder: View>: View {
    let url: URL?
    var kind: RemoteImageKind = .photo
    var contentMode: ContentMode = .fill
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            placeholder()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            }
        }
        .contentShape(Rectangle())
        .onAppear {
            if let url, let cached = RemoteImageLoader.shared.cached(url: url, kind: kind) {
                image = cached
            }
        }
        .task(id: url?.absoluteString ?? "") {
            guard let url else {
                image = nil
                return
            }
            var delay: UInt64 = 400_000_000
            while !Task.isCancelled {
                if let loaded = await RemoteImageLoader.shared.image(for: url, kind: kind) {
                    image = loaded
                    return
                }
                try? await Task.sleep(nanoseconds: delay)
                if delay < 8_000_000_000 { delay *= 2 }
            }
        }
    }
}

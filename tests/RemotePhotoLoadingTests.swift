import Foundation

@MainActor
private final class RemoteImageLoader {
    static let shared = RemoteImageLoader()
    var requests = 0
    var pending: CheckedContinuation<String?, Never>?

    func cached(url: URL, kind: Int) -> String? { nil }

    func image(for url: URL, kind: Int) async -> String? {
        requests += 1
        if url.path == "/missing" { return nil }
        if url.path == "/old" {
            return await withCheckedContinuation { pending = $0 }
        }
        return url.path
    }
}

@MainActor
private final class RemotePhotoHarness {
    var url: URL?
    let kind = 0
    var image: String?

    func load() async {
        // REMOTE_PHOTO_TASK
    }
}

@main
private struct RemotePhotoLoadingTests {
    @MainActor
    static func main() async {
        let loader = RemoteImageLoader.shared
        let missing = RemotePhotoHarness()
        missing.url = URL(string: "https://example.test/missing")!
        let missingTask = Task { await missing.load() }
        try? await Task.sleep(for: .milliseconds(600))
        missingTask.cancel()
        await missingTask.value
        let retriedFailure = loader.requests != 1

        let photo = RemotePhotoHarness()
        photo.url = URL(string: "https://example.test/old")!
        let oldTask = Task { await photo.load() }
        while loader.pending == nil { await Task.yield() }
        oldTask.cancel()
        photo.url = URL(string: "https://example.test/new")!
        await photo.load()
        loader.pending?.resume(returning: "/old")
        loader.pending = nil
        await oldTask.value
        let replacedNewImage = photo.image != "/new"

        photo.url = nil
        await photo.load()
        precondition(photo.image == nil, "Removing a photo must clear the old image")
        if retriedFailure { print("FAIL: permanently missing photo triggers repeated loader requests") }
        if replacedNewImage { print("FAIL: cancelled old URL load replaces the current photo") }
        if retriedFailure || replacedNewImage { exit(1) }
        print("Remote photo checks passed: bounded loading, cancelled URL race, removed image")
    }
}

import Foundation

private final class LegacyReleaseProtocol: URLProtocol {
    static var data = Data()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
@MainActor
private struct AppStorePromptLegacyTests {
    static func main() async throws {
        precondition(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
                     "Native checks run on GitHub-hosted macOS only")
        let suite = "fitfight-legacy-app-store.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LegacyReleaseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://staging.fitfight.app/api/app-release")!
        let store = AppRelease(version: "1.1.1", build: 202,
                               updateURL: URL(string: "https://apps.apple.com/app/id6804230516")!)
        let beta = AppRelease(version: "1.1.2", build: 205, updateURL: URL(string: "itms-beta://")!)
        LegacyReleaseProtocol.data = try JSONEncoder().encode(
            AppReleasePolicy(latest: store, review: beta, enforced: false, internalLatest: beta)
        )

        let publicBeta = AppUpdateChecker(version: "1.1.1", build: "201", releaseURL: url,
                                          isTestFlight: true, defaults: defaults, session: session)
        await publicBeta.check()
        precondition(publicBeta.status == .updateAvailable && publicBeta.offeredRelease == store,
                     "The released public beta can open the App Store through its existing update dialog")
        publicBeta.dismissUpdate()
        await publicBeta.check()
        precondition(publicBeta.status == .current && publicBeta.allowsUse,
                     "Redirecting an existing dialog cannot remove its Cancel button")

        for build in ["204", "205"] {
            let newerBeta = AppUpdateChecker(version: "1.1.2", build: build, releaseURL: url,
                                             isTestFlight: true, defaults: defaults, session: session)
            await newerBeta.check()
            precondition(newerBeta.status == .current && newerBeta.allowsUse,
                         "Legacy comparison does not offer an older App Store release to a newer beta")
        }
        print("Released build 201: App Store target works; cancellation and newer-beta limits confirmed")
    }
}

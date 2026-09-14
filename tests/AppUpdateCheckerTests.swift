import Foundation

private final class ReleaseProtocol: URLProtocol {
    static var responseData = Data()
    static var responseStatus = 200
    static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.responseStatus,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@main
@MainActor
private struct AppUpdateCheckerTests {
    static func main() async throws {
        precondition(ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true",
                     "Native checks run on GitHub-hosted macOS only")
        let suite = "fitfight-release-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://staging.fitfight.app/api/app-release")!
        let latest = AppRelease(version: "1.0.0", build: 184, updateURL: URL(string: "itms-beta://")!)
        let internalLatest = AppRelease(version: "1.0.0", build: 187, updateURL: URL(string: "itms-beta://")!)
        let policy = AppReleasePolicy(latest: latest, review: nil, enforced: true)
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)

        let outdated = AppUpdateChecker(version: "1.0.0", build: "183", releaseURL: url,
                                          defaults: defaults, session: session)
        precondition(outdated.status == .checking, "First launch starts checking until a result arrives")
        precondition(outdated.allowsUse, "An unverified launch must remain usable")
        await outdated.check()
        precondition(outdated.status == .updateRequired, "An old public build must be blocked")
        precondition(!outdated.allowsUse, "A known mandatory update must block the app and API")
        await outdated.check()
        precondition(outdated.status == .updateRequired, "Checking again must not dismiss the gate")
        precondition(outdated.policy?.latest?.updateURL.absoluteString == "itms-beta://")
        precondition(outdated.policy?.offeredRelease?.build == 184)

        let relaunched = AppUpdateChecker(version: "1.0.0", build: "183", releaseURL: url,
                                          defaults: defaults, session: session)
        precondition(relaunched.status == .updateRequired, "Relaunch must preserve a known mandatory update")
        ReleaseProtocol.responseStatus = 503
        await relaunched.check()
        precondition(relaunched.status == .updateRequired, "A failed check must not clear a known update")
        precondition(!relaunched.allowsUse, "Offline must not dismiss a known mandatory update")

        let installed = AppUpdateChecker(version: "1.0.0", build: "184", releaseURL: url,
                                         defaults: defaults, session: session)
        precondition(installed.status == .current, "A cached admitted build stays usable before a fresh check")
        await installed.check()
        precondition(installed.status == .unavailable, "A failed check is recorded as unavailable")
        precondition(installed.allowsUse, "A failed check must not lock an admitted build")
        ReleaseProtocol.responseStatus = 200
        await installed.check()
        precondition(installed.status == .current, "Friends on the public latest must not be asked to update")
        let previousRequests = ReleaseProtocol.requests
        let permitted = await installed.permitsRequests()
        precondition(permitted && ReleaseProtocol.requests == previousRequests,
                     "API use must not wait on another version check")

        ReleaseProtocol.responseData = Data("{broken".utf8)
        await installed.check()
        precondition(installed.status == .unavailable, "Malformed metadata is treated as a failed check")
        precondition(installed.allowsUse, "Malformed metadata must not lock the app")
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)
        let otherVersion = AppUpdateChecker(version: "1.1.0", build: "184", releaseURL: url,
                                            defaults: defaults, session: session)
        await otherVersion.check()
        precondition(otherVersion.status == .updateRequired, "Matching build numbers alone are insufficient")
        let unregistered = AppUpdateChecker(version: "1.0.0", build: "185", releaseURL: url,
                                            defaults: defaults, session: session)
        await unregistered.check()
        precondition(unregistered.status == .updateRequired, "An arbitrary newer build is not a review exception")

        let split = AppReleasePolicy(latest: latest, review: internalLatest, enforced: true,
                                      internalLatest: internalLatest)
        ReleaseProtocol.responseData = try JSONEncoder().encode(split)
        let friends = AppUpdateChecker(version: "1.0.0", build: "184", releaseURL: url,
                                       defaults: defaults, session: session)
        await friends.check()
        precondition(friends.status == .current, "Friends on 184 must not be told to install an internal build")
        let tester = AppUpdateChecker(version: "1.0.0", build: "187", releaseURL: url,
                                       defaults: defaults, session: session)
        await tester.check()
        precondition(tester.status == .current, "Internal testers on the latest internal build must not see an update")
        let behind = AppUpdateChecker(version: "1.0.0", build: "186", releaseURL: url,
                                       defaults: defaults, session: session)
        await behind.check()
        precondition(behind.status == .updateRequired, "Internal testers behind 187 must be offered that build")
        precondition(behind.policy?.offeredRelease?.build == 187)

        let reviewOnly = AppReleasePolicy(latest: latest, review: internalLatest, enforced: true)
        ReleaseProtocol.responseData = try JSONEncoder().encode(reviewOnly)
        let reviewCompat = AppUpdateChecker(version: "1.0.0", build: "187", releaseURL: url,
                                              defaults: defaults, session: session)
        await reviewCompat.check()
        precondition(reviewCompat.status == .current,
                     "Existing binaries admit the internal latest through review")

        let candidate = AppRelease(version: "1.1.0", build: 170,
                                   updateURL: URL(string: "https://apps.apple.com/app/id1234")!)
        ReleaseProtocol.responseData = try JSONEncoder().encode(
            AppReleasePolicy(latest: nil, review: candidate, enforced: false)
        )
        let reviewer = AppUpdateChecker(version: "1.1.0", build: "170", releaseURL: url,
                                        defaults: defaults, session: session)
        await reviewer.check()
        precondition(reviewer.status == .current, "Apple must be able to review the first production build")
        reviewer.rejectRequest(updateRequired: true)
        precondition(reviewer.status == .updateRequired, "An API rejection must immediately block the app")
        reviewer.rejectRequest(updateRequired: false)
        precondition(reviewer.status == .updateRequired, "An API outage must not clear a known requirement")

        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)
        let concurrent = AppUpdateChecker(version: "1.0.0", build: "184", releaseURL: url,
                                          defaults: defaults, session: session)
        let beforeConcurrent = ReleaseProtocol.requests
        async let first = concurrent.check()
        async let second = concurrent.check()
        let allowed = await (first, second)
        precondition(allowed.0 && allowed.1 && ReleaseProtocol.requests == beforeConcurrent + 1,
                     "Launch and session checks must share one request and the same result")
        concurrent.rejectRequest(updateRequired: false)
        precondition(concurrent.status == .unavailable, "An API release-check failure is recorded as unavailable")
        precondition(concurrent.allowsUse, "An API release-check failure must not lock the app")

        let offlineSuite = "fitfight-release-tests-offline.\(UUID().uuidString)"
        let offlineDefaults = UserDefaults(suiteName: offlineSuite)!
        defer { offlineDefaults.removePersistentDomain(forName: offlineSuite) }
        ReleaseProtocol.responseStatus = 503
        let offline = AppUpdateChecker(version: "1.0.0", build: "184", releaseURL: url,
                                       defaults: offlineDefaults, session: session)
        precondition(offline.status == .checking, "No cache means the first launch still checks")
        precondition(offline.allowsUse, "No internet must not lock the app before the first check")
        await offline.check()
        precondition(offline.status == .unavailable, "An offline check is recorded as unavailable")
        precondition(offline.allowsUse, "No internet must not lock the app after a failed check")
        print("App update checks passed: overlay gate, public vs internal, persistence, review, concurrency and offline use")
    }
}

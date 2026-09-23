import Foundation

private final class ReleaseProtocol: URLProtocol {
    static var responseData = Data()
    static var responseStatus = 200
    static var requests = 0
    static var holdResponses = false
    static var heldRequest: ReleaseProtocol?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests += 1
        if Self.holdResponses {
            Self.heldRequest = self
            return
        }
        finishLoading()
    }

    func finishLoading() {
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
        try await testTestFlightUpdates()
        // Preserve the mandatory production policy separately from optional TestFlight updates.
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
        let lockedReviewer = AppUpdateChecker(version: "1.1.0", build: "170", releaseURL: url,
                                              defaults: defaults, session: session)
        precondition(lockedReviewer.status == .updateRequired,
                     "A 426 lock must survive relaunch even if the cached policy still admits the build")
        let otherReview = AppRelease(version: "1.1.0", build: 171,
                                     updateURL: URL(string: "https://apps.apple.com/app/id1234")!)
        ReleaseProtocol.responseData = try JSONEncoder().encode(
            AppReleasePolicy(latest: nil, review: otherReview, enforced: true)
        )
        await reviewer.check()
        precondition(reviewer.status == .updateRequired,
                     "A later check without latest must not clear a 426 lock")
        precondition(!reviewer.allowsUse, "A 426 lock must keep the overlay")
        let relaunchedReviewer = AppUpdateChecker(version: "1.1.0", build: "170", releaseURL: url,
                                                  defaults: defaults, session: session)
        precondition(relaunchedReviewer.status == .updateRequired,
                     "A 426 lock must survive relaunch after a no-latest policy")
        precondition(relaunchedReviewer.policy?.review?.build == 170,
                     "A no-latest policy must not replace the cached update offer")

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

        let publishSuite = "fitfight-release-tests-publish.\(UUID().uuidString)"
        let publishDefaults = UserDefaults(suiteName: publishSuite)!
        defer { publishDefaults.removePersistentDomain(forName: publishSuite) }
        publishDefaults.set(try JSONEncoder().encode(policy), forKey: "fitfight.release-policy.\(url.absoluteString)")
        ReleaseProtocol.responseStatus = 503
        let justInstalled = AppUpdateChecker(version: "1.1.0", build: "200", releaseURL: url,
                                             defaults: publishDefaults, session: session)
        precondition(justInstalled.status == .checking,
                     "A cached older policy must not lock a newly installed build before a fresh check")
        precondition(justInstalled.allowsUse, "The Fastlane publish gap must remain usable")
        await justInstalled.check()
        precondition(justInstalled.status == .unavailable, "A failed refresh during publish is unavailable")
        precondition(justInstalled.allowsUse, "A 503 during publish must not stick the Update overlay")
        ReleaseProtocol.responseStatus = 200
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)
        await justInstalled.check()
        precondition(justInstalled.status == .updateRequired,
                     "A readable policy that does not admit the build still requires an update")
        print("App update checks passed: TestFlight reminders, public availability, stale metadata, API access, and production gate")
    }

    static func testTestFlightUpdates() async throws {
        let suite = "fitfight-testflight-updates.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let url = URL(string: "https://staging.fitfight.app/api/app-release")!
        let latest = AppRelease(version: "1.0.0", build: 190, updateURL: URL(string: "itms-beta://")!)
        let internalLatest = AppRelease(version: "1.1.0", build: 200, updateURL: latest.updateURL)
        let policy = AppReleasePolicy(latest: latest, review: internalLatest, enforced: true,
                                      internalLatest: internalLatest)
        ReleaseProtocol.responseStatus = 200
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)
        var testNow = Date(timeIntervalSince1970: 1_800_000_000)

        // Reproduce a lock saved by the old binary before the manifest or Apple caught up.
        defaults.set(true, forKey: "fitfight.release-required.\(url.absoluteString).1.0.0.189")
        defaults.set(ReleaseProtocol.responseData, forKey: "fitfight.release-policy.\(url.absoluteString)")
        defaults.set(try JSONEncoder().encode(latest),
                     forKey: "fitfight.release-dismissed.\(url.absoluteString).1.0.0.189")
        let outdated = AppUpdateChecker(version: "1.0.0", build: "189", releaseURL: url,
                                         isTestFlight: true, defaults: defaults, session: session,
                                         now: { testNow })
        precondition(outdated.allowsUse && !outdated.requiresUpdate && outdated.pendingToastRelease == nil,
                     "A saved TestFlight lock must not block launch")
        await outdated.check()
        precondition(outdated.status == .updateAvailable && outdated.pendingToastRelease == latest,
                     "A newer public release offers a toast on app open")
        precondition(defaults.object(forKey: "fitfight.release-reminded.\(url.absoluteString).1.0.0.189.date") as? Date == testNow,
                     "The reminder time must survive app relaunches")
        precondition(outdated.offeredRelease == latest, "Never offer the internal-only build to Friends")
        precondition(outdated.allowsUse, "A TestFlight notice must not block background work")
        let permitted = await outdated.permitsRequests()
        precondition(permitted, "The TestFlight notice must allow real API requests")

        // Closing a toast while the minute refresh is in flight must not reopen it.
        ReleaseProtocol.holdResponses = true
        let refresh = Task { await outdated.check() }
        while ReleaseProtocol.heldRequest == nil { await Task.yield() }
        outdated.dismissToast()
        precondition(outdated.status == .updateAvailable && outdated.pendingToastRelease == nil,
                     "Closing the toast must leave the optional update available")
        ReleaseProtocol.heldRequest!.finishLoading()
        ReleaseProtocol.heldRequest = nil
        ReleaseProtocol.holdResponses = false
        await refresh.value
        precondition(outdated.pendingToastRelease == nil, "An in-flight check must respect the close")
        await outdated.check()
        precondition(outdated.pendingToastRelease == nil, "Minute checks must not repeat the same toast")
        let relaunched = AppUpdateChecker(version: "1.0.0", build: "189", releaseURL: url,
                                           isTestFlight: true, defaults: defaults, session: session,
                                           now: { testNow })
        await relaunched.check()
        precondition(relaunched.pendingToastRelease == nil,
                     "Closing the app must not repeat the toast before three days")
        testNow.addTimeInterval(3 * 24 * 60 * 60 - 1)
        await relaunched.check()
        precondition(relaunched.pendingToastRelease == nil,
                     "The same release stays quiet until three full days pass")
        testNow.addTimeInterval(1)
        await relaunched.check()
        precondition(relaunched.pendingToastRelease == latest,
                     "The same release can be offered after three days")
        relaunched.rejectRequest(updateRequired: true)
        precondition(relaunched.allowsUse && !relaunched.requiresUpdate
                     && relaunched.pendingToastRelease == nil,
                     "A stale server 426 must not create a persistent TestFlight lock")
        await relaunched.check()
        precondition(relaunched.status == .updateAvailable && relaunched.pendingToastRelease == nil,
                     "A 426 must not repeat the same toast during the reminder interval")
        let next = AppRelease(version: "1.1.1", build: 201, updateURL: latest.updateURL)
        ReleaseProtocol.responseData = try JSONEncoder().encode(
            AppReleasePolicy(latest: next, review: nil, enforced: false)
        )
        await relaunched.check()
        precondition(relaunched.pendingToastRelease == nil,
                     "A newer public release must not interrupt the three-day reminder interval")
        testNow.addTimeInterval(3 * 24 * 60 * 60 - 1)
        await relaunched.check()
        precondition(relaunched.pendingToastRelease == nil,
                     "A newer release stays quiet until three full days pass")
        testNow.addTimeInterval(1)
        await relaunched.check()
        precondition(relaunched.pendingToastRelease == next,
                     "The reminder offers the newest public release when the interval ends")
        relaunched.dismissToast()
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)

        for (version, build) in [("1.0.0", "190"), ("1.0.0", "191"), ("1.1.0", "199"), ("1.1.0", "200"), ("1.1.1", "201")] {
            let installed = AppUpdateChecker(version: version, build: build, releaseURL: url,
                                               isTestFlight: true, defaults: defaults, session: session)
            await installed.check()
            precondition(installed.status == .current && installed.allowsUse
                         && installed.pendingToastRelease == nil,
                         "Public, intermediate internal, and newly uploaded builds must not get a false update")
        }

        ReleaseProtocol.responseData = try JSONEncoder().encode(
            AppReleasePolicy(latest: next, review: nil, enforced: false)
        )
        await relaunched.check()
        precondition(relaunched.status == .updateAvailable && relaunched.pendingToastRelease == nil,
                     "Minute checks must not repeat the newest release")
        let updatedButBehind = AppUpdateChecker(version: "1.0.0", build: "191", releaseURL: url,
                                                isTestFlight: true, defaults: defaults, session: session,
                                                now: { testNow })
        await updatedButBehind.check()
        precondition(updatedButBehind.pendingToastRelease == next,
                     "Installing a different build starts a fresh reminder interval")
        ReleaseProtocol.responseData = try JSONEncoder().encode(policy)
        await relaunched.check()
        precondition(relaunched.status == .updateAvailable && relaunched.pendingToastRelease == nil,
                     "A manifest rollback must not repeat an older update during the interval")
        let later = AppRelease(version: "1.1.1", build: 202, updateURL: latest.updateURL)
        ReleaseProtocol.responseData = try JSONEncoder().encode(
            AppReleasePolicy(latest: later, review: nil, enforced: false)
        )
        await relaunched.check()
        precondition(relaunched.status == .updateAvailable && relaunched.pendingToastRelease == nil,
                     "Another newer public build must respect the same interval")
        testNow.addTimeInterval(3 * 24 * 60 * 60)
        await relaunched.check()
        precondition(relaunched.pendingToastRelease == later,
                     "The reminder offers the latest build after another three days")
        ReleaseProtocol.responseStatus = 503
        await relaunched.check()
        precondition(relaunched.status == .unavailable && relaunched.allowsUse
                     && relaunched.pendingToastRelease == nil,
                     "An outage must clear a previously visible TestFlight toast")
        ReleaseProtocol.responseStatus = 200
        await relaunched.check()
        ReleaseProtocol.responseData = Data("{broken".utf8)
        await relaunched.check()
        precondition(relaunched.status == .unavailable && relaunched.allowsUse
                     && relaunched.pendingToastRelease == nil,
                     "Malformed metadata must not preserve a TestFlight toast")
        ReleaseProtocol.responseData = try JSONEncoder().encode(
            AppReleasePolicy(latest: nil, review: next, enforced: true, internalLatest: next)
        )
        await relaunched.check()
        precondition(relaunched.status == .unavailable && relaunched.allowsUse,
                     "Review and internal builds alone must never be advertised as installable")
        precondition(relaunched.offeredRelease == nil)

        let productionURL = URL(string: "https://fitfight.app/api/app-release")!
        let production = AppUpdateChecker(version: "1.0.0", build: "189", releaseURL: productionURL,
                                           defaults: defaults, session: session)
        production.rejectRequest(updateRequired: true)
        production.dismissToast()
        precondition(!production.allowsUse && production.pendingToastRelease == nil,
                     "Closing a toast must not bypass the production gate")
    }
}

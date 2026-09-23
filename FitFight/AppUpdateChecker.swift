import Combine
import Foundation

struct AppRelease: Codable, Equatable {
    let version: String
    let build: Int
    let updateURL: URL

    enum CodingKeys: String, CodingKey {
        case version, build
        case updateURL = "update_url"
    }

    func matches(version: String, build: String) -> Bool {
        self.version == version && String(self.build) == build
    }

    func isNewer(thanVersion version: String, build: String) -> Bool {
        guard let installedBuild = Int(build) else { return false }
        let versionOrder = self.version.compare(version, options: .numeric)
        return versionOrder == .orderedDescending
            || (versionOrder == .orderedSame && self.build > installedBuild)
    }
}

struct AppReleasePolicy: Codable, Equatable {
    let latest: AppRelease?
    let review: AppRelease?
    let internalLatest: AppRelease?
    let enforced: Bool

    enum CodingKeys: String, CodingKey {
        case latest, review, enforced
        case internalLatest = "internal"
    }

    init(latest: AppRelease?, review: AppRelease?, enforced: Bool, internalLatest: AppRelease? = nil) {
        self.latest = latest
        self.review = review
        self.internalLatest = internalLatest
        self.enforced = enforced
    }

    func allows(version: String, build: String) -> Bool {
        [latest, review, internalLatest].compactMap { $0 }.contains { $0.matches(version: version, build: build) }
    }

    var offeredRelease: AppRelease? { internalLatest ?? latest ?? review }
}

extension AppRelease {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(String.self, forKey: .version)
        let build = try values.decode(Int.self, forKey: .build)
        let updateURL = try values.decode(URL.self, forKey: .updateURL)
        guard build > 0,
              version.range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil,
              updateURL.absoluteString == "itms-beta://"
                || updateURL.absoluteString.range(
                    of: #"^https://apps\.apple\.com/app/id\d+$"#, options: .regularExpression
                ) != nil else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "Invalid app release"))
        }
        self.init(version: version, build: build, updateURL: updateURL)
    }
}

@MainActor
final class AppUpdateChecker: ObservableObject {
    enum Status: Equatable { case checking, current, updateAvailable, updateRequired, unavailable }

    @Published private(set) var status: Status = .checking
    @Published private(set) var policy: AppReleasePolicy?
    @Published private(set) var isChecking = false
    @Published private(set) var pendingToastRelease: AppRelease?

    var allowsUse: Bool { status != .updateRequired }
    var requiresUpdate: Bool { status == .updateRequired }
    var offeredRelease: AppRelease? { isTestFlight ? policy?.latest : policy?.offeredRelease }
    let isTestFlight: Bool

    private let version: String
    private let build: String
    private let releaseURL: URL
    private let defaults: UserDefaults
    private let session: URLSession
    private let now: () -> Date
    private let cacheKey: String
    private let requiredKey: String
    private let reminderKey: String
    private let reminderDateKey: String
    private var lastNotifiedRelease: AppRelease?
    private var lastNotifiedAt: Date?
    private var inFlight: Task<Bool, Never>?

    init(version: String, build: String, releaseURL: URL, isTestFlight: Bool = false,
         defaults: UserDefaults = .standard,
         session: URLSession = .shared,
         now: @escaping () -> Date = Date.init) {
        self.version = version
        self.build = build
        self.releaseURL = releaseURL
        self.isTestFlight = isTestFlight
        self.defaults = defaults
        self.session = session
        self.now = now
        cacheKey = "fitfight.release-policy.\(releaseURL.absoluteString)"
        requiredKey = "fitfight.release-required.\(releaseURL.absoluteString).\(version).\(build)"
        let reminderKey = "fitfight.release-reminded.\(releaseURL.absoluteString).\(version).\(build)"
        self.reminderKey = reminderKey
        reminderDateKey = "\(reminderKey).date"
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(AppReleasePolicy.self, from: data) {
            policy = cached
        }
        if isTestFlight {
            defaults.removeObject(forKey: requiredKey)
            if let data = defaults.data(forKey: reminderKey) {
                lastNotifiedRelease = try? JSONDecoder().decode(AppRelease.self, from: data)
            }
            lastNotifiedAt = defaults.object(forKey: reminderDateKey) as? Date
        }
        if !isTestFlight && defaults.bool(forKey: requiredKey) {
            status = .updateRequired
        } else if let policy, policy.allows(version: version, build: build) {
            status = .current
        }
    }

    @discardableResult
    func check() async -> Bool {
        if let inFlight { return await inFlight.value }
        isChecking = true
        let task = Task { @MainActor in
            defer {
                self.inFlight = nil
                self.isChecking = false
            }
            do {
                var request = URLRequest(url: self.releaseURL)
                request.cachePolicy = .reloadIgnoringLocalCacheData
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await self.session.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw URLError(.badServerResponse)
                }
                let policy = try JSONDecoder().decode(AppReleasePolicy.self, from: data)
                if self.isTestFlight {
                    self.policy = policy
                    self.defaults.set(data, forKey: self.cacheKey)
                    self.defaults.removeObject(forKey: self.requiredKey)
                    if policy.allows(version: self.version, build: self.build) {
                        self.status = .current
                        self.pendingToastRelease = nil
                    } else if let latest = policy.latest {
                        // Internal/review membership does not prove what this tester can install.
                        let isNewer = latest.isNewer(thanVersion: self.version, build: self.build)
                        self.status = isNewer ? .updateAvailable : .current
                        if isNewer {
                            let alreadyNotified = self.lastNotifiedRelease.map {
                                !latest.isNewer(thanVersion: $0.version, build: String($0.build))
                            } == true && self.lastNotifiedAt.map {
                                self.now().timeIntervalSince($0) < 3 * 24 * 60 * 60
                            } == true
                            if !alreadyNotified {
                                let notifiedAt = self.now()
                                self.lastNotifiedRelease = latest
                                self.lastNotifiedAt = notifiedAt
                                self.defaults.set(try? JSONEncoder().encode(latest), forKey: self.reminderKey)
                                self.defaults.set(notifiedAt, forKey: self.reminderDateKey)
                                self.pendingToastRelease = latest
                            }
                        } else {
                            self.pendingToastRelease = nil
                        }
                    } else {
                        self.status = .unavailable
                        self.pendingToastRelease = nil
                    }
                } else if policy.allows(version: self.version, build: self.build) {
                    self.policy = policy
                    self.defaults.set(data, forKey: self.cacheKey)
                    self.defaults.removeObject(forKey: self.requiredKey)
                    self.status = .current
                } else if policy.latest != nil {
                    self.policy = policy
                    self.defaults.set(data, forKey: self.cacheKey)
                    self.defaults.set(true, forKey: self.requiredKey)
                    self.status = .updateRequired
                } else if self.status == .updateRequired {
                    self.defaults.set(true, forKey: self.requiredKey)
                } else {
                    self.policy = policy
                    self.defaults.set(data, forKey: self.cacheKey)
                    self.status = .unavailable
                }
            } catch {
                if self.isTestFlight || self.status != .updateRequired { self.status = .unavailable }
                if self.isTestFlight { self.pendingToastRelease = nil }
            }
            return self.allowsUse
        }
        inFlight = task
        return await task.value
    }

    func permitsRequests() async -> Bool {
        allowsUse
    }

    func dismissToast() {
        pendingToastRelease = nil
    }

    func rejectRequest(updateRequired: Bool) {
        if isTestFlight {
            // An older backend may still send 426 during deployment; it must not lock the app.
            status = .unavailable
            pendingToastRelease = nil
            defaults.removeObject(forKey: requiredKey)
        } else if updateRequired {
            status = .updateRequired
            defaults.set(true, forKey: requiredKey)
        } else if status != .updateRequired {
            status = .unavailable
        }
    }
}

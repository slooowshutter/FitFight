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

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        latest = try values.decodeIfPresent(AppRelease.self, forKey: .latest)
        review = try values.decodeIfPresent(AppRelease.self, forKey: .review)
        internalLatest = try values.decodeIfPresent(AppRelease.self, forKey: .internalLatest)
        enforced = try values.decode(Bool.self, forKey: .enforced)
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(latest, forKey: .latest)
        try values.encode(review, forKey: .review)
        try values.encodeIfPresent(internalLatest, forKey: .internalLatest)
        try values.encode(enforced, forKey: .enforced)
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

    var allowsUse: Bool { status != .updateRequired }
    var showsUpdate: Bool { status == .updateAvailable || status == .updateRequired }
    var offeredRelease: AppRelease? { isTestFlight ? policy?.latest : policy?.offeredRelease }
    var offersAppStore: Bool { isTestFlight && offeredRelease?.updateURL.host == "apps.apple.com" }
    let isTestFlight: Bool

    private let version: String
    private let build: String
    private let releaseURL: URL
    private let defaults: UserDefaults
    private let session: URLSession
    private let cacheKey: String
    private let requiredKey: String
    private let dismissedKey: String
    private var dismissedRelease: AppRelease?
    private var inFlight: Task<Bool, Never>?

    init(version: String, build: String, releaseURL: URL, isTestFlight: Bool = false,
         defaults: UserDefaults = .standard,
         session: URLSession = .shared) {
        self.version = version
        self.build = build
        self.releaseURL = releaseURL
        self.isTestFlight = isTestFlight
        self.defaults = defaults
        self.session = session
        cacheKey = "fitfight.release-policy.\(releaseURL.absoluteString)"
        requiredKey = "fitfight.release-required.\(releaseURL.absoluteString).\(version).\(build)"
        dismissedKey = "fitfight.release-dismissed.\(releaseURL.absoluteString).\(version).\(build)"
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(AppReleasePolicy.self, from: data) {
            policy = cached
        }
        if isTestFlight {
            defaults.removeObject(forKey: requiredKey)
            if let data = defaults.data(forKey: dismissedKey) {
                dismissedRelease = try? JSONDecoder().decode(AppRelease.self, from: data)
            }
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
                    } else if let latest = policy.latest {
                        // Internal/review membership does not prove what this tester can install.
                        let isAppStore = latest.updateURL.host == "apps.apple.com"
                        let isNewer = isAppStore || latest.isNewer(thanVersion: self.version, build: self.build)
                        let isDismissed = self.dismissedRelease.map {
                            isAppStore ? $0 == latest
                                : $0.updateURL == latest.updateURL
                                    && !latest.isNewer(thanVersion: $0.version, build: String($0.build))
                        } ?? false
                        self.status = isNewer && !isDismissed ? .updateAvailable : .current
                    } else {
                        self.status = .unavailable
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
            }
            return self.allowsUse
        }
        inFlight = task
        return await task.value
    }

    func permitsRequests() async -> Bool {
        allowsUse
    }

    func dismissUpdate() {
        guard isTestFlight, let release = offeredRelease else { return }
        dismissedRelease = release
        defaults.set(try? JSONEncoder().encode(release), forKey: dismissedKey)
        status = .current
    }

    func rejectRequest(updateRequired: Bool) {
        if isTestFlight {
            // An older backend may still send 426 during deployment; it must not lock the app.
            status = .unavailable
            defaults.removeObject(forKey: requiredKey)
        } else if updateRequired {
            status = .updateRequired
            defaults.set(true, forKey: requiredKey)
        } else if status != .updateRequired {
            status = .unavailable
        }
    }
}
